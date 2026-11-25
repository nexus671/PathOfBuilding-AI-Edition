local sync = require("Modules.LootFilterDailySync")
local account = require("Modules.LootFilterAccount")
local parser = require("Modules.LootFilterParser")
local ui = require("Modules.PlanningUI")
local M = {}

local function sameText(before, after)
	return type(before) == "string" and type(after) == "string" and before:gsub("\r\n","\n") == after:gsub("\r\n","\n")
end

local function prepare(id, raw, verified, remote)
	assert(type(remote) == "table" and remote.id == id and remote.realm == verified.realm,
		"The selected account filter no longer matches the reviewed realm")
	assert(type(remote.filter) == "string" and #remote.filter <= 2*1024*1024
		and type(remote.filter_name) == "string" and #remote.filter_name <= 120, "Account filter text or name is unavailable")
	assert(not sameText(raw, remote.filter), "The account filter already contains this verified output")
	return {id=id,realm=remote.realm,name=remote.filter_name,remote=remote.filter,
		raw=raw,digest=verified.digest,revision=verified.revision}
end

local function stillVerified(profileId, plan)
	local raw, verified = sync.verifiedOutput(profileId)
	assert(verified.digest == plan.digest and verified.revision == plan.revision and verified.realm == plan.realm and raw == plan.raw,
		"The verified local output changed. Open a new publication review.")
end

local function request(method,id,payload,callback)
	assert(not launch.noSSL, "Enable HTTPS certificate verification in PoB")
	account.request(main.api,method,id,payload,callback)
end

local function reviewedPublication(profileId, plan)
	local width = math.min(760,main.screenW-40)
	local c, owner = {}, nil
	local submitting, reviewed = false, false
	local function message(title, problem)
		main:OpenMessagePopup(title,ui.errorText(problem))
	end
	ui.description(c,"summary",16,24,width-32,100,{
		"Account filter: "..plan.name,
		"Realm: "..plan.realm,
		string.format("Exact verified local output: %d bytes, checksum %s",#plan.raw,plan.digest),
		"Review the full diff before approving this account update. Your local filter stays available.",
	},14)
	c.diff = new("ButtonControl"):ButtonControl(ui.anchor,{16,140,156,28},"View full diff",function()
		require("Classes.LootFilterDiffControl").Open(plan.remote,plan.raw,true)
		reviewed = true
	end)
	c.copy = new("ButtonControl"):ButtonControl(ui.anchor,{184,140,156,28},"Copy verified output",function() Copy(plan.raw) end)
	c.publish = new("ButtonControl"):ButtonControl(ui.anchor,{16,196,184,28},"Publish exact output",function()
		submitting = true
		local function fail(why)
			submitting = false
			if main.popups[1] == owner then message("Account filter publication",why) end
		end
		local ok, problem = pcall(function()
			stillVerified(profileId,plan)
			request("GET",plan.id,nil,function(response,err)
				if main.popups[1] ~= owner then return end
				if err then fail(err); return end
				local remote = response and response.filter
				if type(remote) ~= "table" or remote.id ~= plan.id or remote.realm ~= plan.realm or remote.filter_name ~= plan.name
					or not sameText(remote.filter,plan.remote) then
					fail("The account filter changed after your review. Open a new publication review.")
					return
				end
				account.afterRequest(function()
					if main.popups[1] ~= owner then return end
					local sent, sendError = pcall(function()
						stillVerified(profileId,plan)
						request("POST",plan.id,{filter=plan.raw},function(value,writeError)
							submitting = false
							if main.popups[1] ~= owner then return end
							if writeError then fail(writeError); return end
							local accepted = value and value.filter
							if not accepted or accepted.id ~= plan.id or accepted.realm ~= plan.realm or accepted.filter_name ~= plan.name
								or not sameText(accepted.filter,plan.raw) then
								fail("The server response did not confirm the exact reviewed filter. Check the account before retrying.")
								return
							end
							main:ClosePopup()
							message("Account filter published","The server confirmed the reviewed output as valid.")
						end)
					end)
					if not sent then fail(sendError) end
				end)
			end)
		end)
		if not ok then fail(problem) end
	end)
	c.publish.enabled = function() return reviewed and not submitting and not account.busy and not account.pending and os.time() >= account.nextRequest end
	c.diff.enabled = function() return not submitting end
	c.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,196,120,28},"Close",function() main:ClosePopup() end)
	ui.style(c,{publish=true})
	owner = main:OpenPopup(width,244,"Review verified account output",c,nil,nil,"close")
end

function M.Open(profileId)
	local unavailable = main.api and main.api.AccountAccessError and main.api:AccountAccessError()
	if unavailable then main:OpenMessagePopup("Publish verified output",unavailable.." Local sync is available."); return end
	local ok, raw, verified = pcall(sync.verifiedOutput,profileId)
	if not ok then main:OpenMessagePopup("Publish verified output",ui.errorText(raw)); return end
	if #parser.parse(raw).imports > 0 then
		main:OpenMessagePopup("Publish verified output","Export a self-contained filter before publishing to the account.")
		return
	end
	local width = math.min(570,main.screenW-40)
	local c, owner = {}, nil
	ui.description(c,"help",16,24,width-32,72,{
		"Choose a PoE 1 "..verified.realm.." account filter to receive the last verified local output.",
		"Account access requires item-filter permission. Local sync works independently.",
	},14)
	local function errorMessage(problem)
		if main.popups[1] == owner then main:OpenMessagePopup("Publish verified output",ui.errorText(problem)) end
	end
	c.login = new("ButtonControl"):ButtonControl(ui.anchor,{16,112,122,28},"Log in",function()
		if launch.noSSL then errorMessage("Enable HTTPS certificate verification in PoB."); return end
		main.api:FetchAuthToken(function(err)
			if err then errorMessage("Login failed. Verify that the OAuth client has item-filter permission.") end
		end,true)
	end)
	c.list = new("ButtonControl"):ButtonControl(ui.anchor,{150,112,122,28},"List filters",function()
		local entered, why = pcall(request,"GET",nil,nil,function(response,err)
			if main.popups[1] ~= owner then return end
			if err then errorMessage(err); return end
			local entries = {}
			for _, entry in ipairs(type(response) == "table" and type(response.filters) == "table" and response.filters or {}) do
				if type(entry) == "table" and entry.realm == verified.realm and type(entry.id) == "string"
					and #entry.id <= 100 and entry.id:match("^[%w_-]+$") and type(entry.filter_name) == "string" then
					entries[#entries+1] = {id=entry.id,label=entry.filter_name,details={"Realm: "..entry.realm}}
				end
			end
			if #entries == 0 then errorMessage("No account filters in the matching realm were returned."); return end
			local selection
			require("Classes.PlanningBrowserControl").Open("Choose an account filter",entries,{
				action="Review output",closeOnChoose=false,enterChooses=false,
				canChoose=function() return not account.busy and os.time() >= account.nextRequest end,
				choose=function(entry)
					local opened, problem = pcall(request,"GET",entry.id,nil,function(result,issue)
						if main.popups[1] ~= selection then return end
						if issue then main:OpenMessagePopup("Account filter review",ui.errorText(issue)); return end
						local ready, plan = pcall(prepare,entry.id,raw,verified,result and result.filter)
						if not ready then main:OpenMessagePopup("Account filter review",ui.errorText(plan)); return end
						main:ClosePopup()
						main:ClosePopup()
						reviewedPublication(profileId,plan)
					end)
					if not opened then main:OpenMessagePopup("Account filter review",ui.errorText(problem)) end
				end,
			})
			selection = main.popups[1]
		end)
		if not entered then errorMessage(why) end
	end)
	c.list.enabled = function() return not account.busy and os.time() >= account.nextRequest end
	c.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-138,112,122,28},"Close",function() main:ClosePopup() end)
	ui.style(c)
	owner = main:OpenPopup(width,164,"Publish verified output",c,nil,nil,"close")
end

return M
