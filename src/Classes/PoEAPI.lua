local base64 = require("base64")
local sha = require("sha2")
local dkjson = require "dkjson"

local scopesOAuth = {
	"account:profile",
	"account:leagues",
	"account:characters",
	"account:trade"
}

local unavailable = "PoE account access requires an OAuth client approved for this edition."
local function formValue(value)
	return (value:gsub("[^%w_.~-]", function(byte) return string.format("%%%02X",byte:byte()) end))
end

local function randomBytes()
	local ffi = require("ffi")
	if ffi.os == "Windows" then
		ffi.cdef("long __stdcall BCryptGenRandom(void *, unsigned char *, unsigned long, unsigned long);")
		local bytes = ffi.new("unsigned char[48]")
		local library = ffi.load("bcrypt")
		assert(library.BCryptGenRandom(nil,bytes,48,2)==0)
		return ffi.string(bytes,48)
	end
	local source = assert(io.open("/dev/urandom","rb"))
	local bytes = source:read(48)
	source:close()
	assert(bytes and #bytes==48)
	return bytes
end

local function configuredClient()
	local id, contact = os.getenv("POB_GGG_OAUTH_CLIENT_ID"), os.getenv("POB_GGG_OAUTH_CONTACT")
	if not id or #id>80 or not id:match("^[%w_.-]+$") or id:lower()=="pob" then return end
	if not contact or #contact>120 or not contact:match("^[%w_.+%-]+@[%w_.%-]+%.[%a]+$") then return end
	return id, contact
end

---@class PoEAPI
local PoEAPIClass = newClass("PoEAPI")

function PoEAPIClass:PoEAPI(authToken, refreshToken, tokenExpiry, savedClientId)
	self.retries = 0
	self.clientId, self.oauthContact = configuredClient()
	if self.clientId and self.clientId == savedClientId then
		self.authToken = authToken
		self.refreshToken = refreshToken
		self.tokenExpiry = tokenExpiry or 0
	end
	self.baseUrl = "https://api.pathofexile.com"
	self.rateLimiter = new("TradeQueryRateLimiter"):TradeQueryRateLimiter()
	self.tokenHasBeenValidated = false

	self.ERROR_NO_AUTH = "No auth token"
	return self
end

function PoEAPIClass:AccountAccessError()
	if not self.clientId then return unavailable end
	if launch.noSSL then return "Enable HTTPS certificate verification in PoB." end
end

function PoEAPIClass:AccountUserAgent()
	return "User-Agent: OAuth "..self.clientId.."/"..(launch.versionNumber or "1.0.0").." (contact: "..self.oauthContact..")"
end

local function readTokens(response)
	local body = type(response)=="table" and response.body
	local decoded = type(body)=="string" and dkjson.decode(body)
	if type(decoded)=="table" and type(decoded.access_token)=="string" and decoded.access_token:match("^[%w_.~+/%-]+=*$")
		and type(decoded.refresh_token)=="string" and #decoded.refresh_token>0
		and type(decoded.expires_in)=="number" and decoded.expires_in>0 and decoded.expires_in<math.huge then
		return decoded
	end
end

-- performs a basic check on the validity of the current login by refreshing the
-- token if necessary. if a refresh is attempted and fails, the login details
-- will be reset.
--- @param callback fun(valid: boolean, errMsg: string?)
function PoEAPIClass:ValidateAuth(callback)
	local problem = self:AccountAccessError()
	if problem then callback(false,problem); return end
	if self.authToken and self.refreshToken and self.tokenExpiry then
		ConPrintf("Validating auth token")
		if self.tokenExpiry < os.time() then
			ConPrintf("Auth token expired")
			-- here recreate the token with the refresh_token
			local formText = "client_id="..formValue(self.clientId).."&grant_type=refresh_token&refresh_token="..formValue(self.refreshToken)
			launch:DownloadPage("https://www.pathofexile.com/oauth/token", function(response, errMsg)
				ConPrintf("Recreating auth token")
				if errMsg then
					ConPrintf("Failed to recreate auth token: %s", errMsg)
					self:ResetDetails()
					callback(false, errMsg)
					return
				end
				local responseLua = readTokens(response)
				if not responseLua then
					self:ResetDetails()
					callback(false, "Malformed response")
				else
					self.authToken = responseLua.access_token
					self.refreshToken = responseLua.refresh_token
					self.tokenExpiry = os.time() + responseLua.expires_in
					self:UpdateMain()
					self.retries = 0
					callback(true)
				end
				
			end, {body=formText,header=self:AccountUserAgent(),followRedirects=false})
		else
			callback(true)
		end
	else
		callback(false)
	end
end

--- @param secret string
local function base64_encode(secret)
	return base64.encode(secret):gsub("+", "-"):gsub("/", "_"):gsub("=+$", "")
end

--- resets current authorization details
function PoEAPIClass:ResetDetails()
	self.authToken = nil
	self.refreshToken = nil
	self.tokenExpiry = nil
	self:UpdateMain()
end

--- updates main so that API details are saved across restarts
function PoEAPIClass:UpdateMain()
	main.lastToken = self.authToken
	main.lastRefreshToken = self.refreshToken
	main.tokenExpiry = self.tokenExpiry
	main.lastOAuthClientId = self.authToken and self.clientId or nil
	main:SaveSettings()
end

--- @param callback fun(errCode: string?)
function PoEAPIClass:FetchAuthToken(callback, includeItemFilters)
	local problem = self:AccountAccessError()
	if problem then callback(problem); return end
	local requestedScopes = { unpack(scopesOAuth) }
	if includeItemFilters then table.insert(requestedScopes, "account:item_filter") end
	local generated, random = pcall(randomBytes)
	if not generated then callback("Could not start a secure PoE account sign-in."); return end
	local code_verifier = base64_encode(random:sub(1,32))
	local code_challenge = base64_encode(sha.hex_to_bin(sha.sha256(code_verifier)))
	local initialState = base64_encode(random:sub(33))

	local authUrl = string.format(
		"https://www.pathofexile.com/oauth/authorize?client_id=%s&response_type=code&scope=%s&state=%s&code_challenge=%s&code_challenge_method=S256"
		, formValue(self.clientId)
		, table.concat(requestedScopes, "%20")
		, initialState
		, code_challenge
	)

	local server = io.open("LaunchServer.lua", "r")
	if not server then callback("Could not start the local PoE sign-in."); return end
	local id = LaunchSubScript(server:read("*a"), "", "ConPrintf,OpenURL,Copy", authUrl)
	server:close()
	if id then
		launch.subScripts[id] = {
			type = "DOWNLOAD",
			callback = function(code, errMsg, state, port)
				if not code then
					ConPrintf("Failed to get code from server: %s", errMsg)
					self:ResetDetails()
					callback(errMsg or self.ERROR_NO_AUTH)
					return
				end

				if initialState ~= state then
					ConPrintf("OAuth state mismatch during authentication")
					self:ResetDetails()
					callback("OAuth state mismatch")
					return
				end
				local formText = "client_id="..formValue(self.clientId).."&grant_type=authorization_code&code="..
				formValue(code) ..
				"&redirect_uri=http://localhost:" ..
				port .. "&scope=" .. table.concat(requestedScopes, " ") .. "&code_verifier=" .. code_verifier
				launch:DownloadPage("https://www.pathofexile.com/oauth/token", function(response, errMsg)
					if errMsg then
						ConPrintf("Failed to get token from server: " .. errMsg)
						self:ResetDetails()
						callback(errMsg)
						return
					end
					local responseLua = readTokens(response)
					if not responseLua then
						self:ResetDetails()
						callback("Malformed response")
						return
					end
					self.authToken = responseLua.access_token
					self.refreshToken = responseLua.refresh_token
					self.tokenExpiry = os.time() + responseLua.expires_in
					self:UpdateMain()
					self.retries = 0
					SetForeground()
					callback()
				end, {body=formText,header=self:AccountUserAgent(),followRedirects=false})
			end
		}
	else
		callback("Could not start the local PoE sign-in.")
	end
end

--- @param endpoint string
--- @param callback fun(response: table?, errorMsg: string)
function PoEAPIClass:DownloadWithRefresh(endpoint, callback)
	local problem = self:AccountAccessError()
	if problem then callback(nil,problem); return end
	self:ValidateAuth(function(valid, validationErrMsg)
		if not valid then
			-- Clean info about token and refresh token
			self:ResetDetails()
			callback(nil, validationErrMsg or self.ERROR_NO_AUTH)
			return
		end

		launch:DownloadPage(self.baseUrl .. endpoint, function(response, errMsg)
			if errMsg and errMsg:match("401") and self.retries < 1 then
				-- try once again with refresh token
				self.retries = 1
				self.tokenExpiry = 0
				self:DownloadWithRefresh(endpoint, callback)
			else
				self.retries = 0
				if errMsg then
					ConPrintf("Failed to download %s: %s", endpoint, errMsg)
				end
				callback(response, errMsg)
			end
		end, {header=self:AccountUserAgent().."\r\nAuthorization: Bearer "..self.authToken,followRedirects=false})
	end)
end

--- @alias DownloadCallback fun(body: table?, err: string?, timeout: integer?)
--- @param policy string
--- @param url string
--- @param callback DownloadCallback
function PoEAPIClass:DownloadWithRateLimit(policy, url, callback)
	local now = os.time()
	local timeNext = self.rateLimiter:NextRequestTime(policy, now)
	if now >= timeNext then
		local requestId = self.rateLimiter:InsertRequest(policy)
		local onComplete = function(response, errMsg)
			self.rateLimiter:FinishRequest(policy, requestId)
			local header = response and response.header or ""
			self.rateLimiter:UpdateFromHeader(header, policy)
			if errMsg then
				callback(response, errMsg, nil)
				return
			end
			if header:match("HTTP/[%d%.]+ (%d+)") == "429" then
				timeNext = self.rateLimiter:NextRequestTime(policy, now)
				callback(nil, "Response code: 429", timeNext)
				return
			end
			local responseLua = dkjson.decode(response.body)
			callback(responseLua, errMsg, nil)
		end
		self:DownloadWithRefresh(url, onComplete)
	else
		callback(nil, "Response code: 429", timeNext)
	end
end

---Fetches character list from PoE's OAuth api
---@param realm string Realm to fetch the list from
---@param callback DownloadCallback
function PoEAPIClass:DownloadCharacterList(realm, callback)
	self:DownloadWithRateLimit("character-list-request-limit",
		"/character" .. (realm == "pc" and "" or "/" .. realm), callback)
end

---Fetches character from PoE's OAuth api
---@param realm string Realm to fetch the character from
---@param name string Character name to fetch
---@param callback DownloadCallback
function PoEAPIClass:DownloadCharacter(realm, name, callback)
	self:DownloadWithRateLimit("character-request-limit",
		"/character" .. (realm == "pc" and "" or "/" .. realm) .. "/" .. name, callback)
end
