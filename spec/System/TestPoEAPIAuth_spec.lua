describe("PoEAPI auth", function()
	local originalLaunchSubScript
	local originalGetenv
	local originalDownloadPage
	local originalSubScripts

	before_each(function()
		originalGetenv = os.getenv
		os.getenv = function(key)
			if key=="POB_GGG_OAUTH_CLIENT_ID" then return "local-test-client" end
			if key=="POB_GGG_OAUTH_CONTACT" then return "operator@example.test" end
			return originalGetenv(key)
		end
		originalLaunchSubScript = _G.LaunchSubScript
		originalDownloadPage = launch.DownloadPage
		originalSubScripts = launch.subScripts
		launch.subScripts = {}
	end)

	after_each(function()
		os.getenv = originalGetenv
		_G.LaunchSubScript = originalLaunchSubScript
		launch.DownloadPage = originalDownloadPage
		launch.subScripts = originalSubScripts
	end)

	it("passes token exchange errors to the auth callback #auth", function()
		local authState
		_G.LaunchSubScript = function(_, _, _, authUrl)
			authState = authUrl:match("state=([^&]+)")
			return 123
		end
		launch.DownloadPage = function(_, url, callback, parameters)
			assert.are.equals("https://www.pathofexile.com/oauth/token", url)
			assert.is_true(parameters.body:find("client_id=local-test-client",1,true)~=nil)
			local verifier=parameters.body:match("code_verifier=([^&]+)")
			assert.are.equals(43,#verifier)
			assert.is_true(verifier:match("^[%w_-]+$")~=nil)
			assert.is_false(parameters.followRedirects)
			callback(nil, "SSL connect error")
		end

		local api = new("PoEAPI"):PoEAPI()
		local callbackArgs
		api:FetchAuthToken(function(errMsg)
			callbackArgs = {
				errMsg = errMsg,
			}
		end)

		assert.is_not_nil(authState)
		assert.is_not_nil(launch.subScripts[123])
		launch.subScripts[123].callback("auth-code", nil, authState, 12345)

		assert.are.equals("SSL connect error", callbackArgs.errMsg)
		assert.is_nil(api.authToken)
	end)

	it("reports OAuth state mismatches without exchanging a token", function()
		_G.LaunchSubScript = function()
			return 123
		end
		launch.DownloadPage = function()
			error("token exchange should not run for mismatched OAuth state")
		end

		local api = new("PoEAPI"):PoEAPI()
		local callbackArgs
		api:FetchAuthToken(function(errMsg)
			callbackArgs = {
				errMsg = errMsg,
			}
		end)

		assert.is_not_nil(launch.subScripts[123])
		launch.subScripts[123].callback("auth-code", nil, "wrong-state", 12345)

		assert.are.equals("OAuth state mismatch", callbackArgs.errMsg)
		assert.is_nil(api.authToken)
	end)
	it("blocks the default and prevents inherited credentials from being sent", function()
		_G.LaunchSubScript = function() error("The auth browser must not open") end
		launch.DownloadPage = function() error("The network must not be used") end
		local configured = os.getenv
		for _, unauthorized in ipairs({"", "pob"}) do
			os.getenv = function(key)
				if key=="POB_GGG_OAUTH_CLIENT_ID" then return unauthorized end
				return configured(key)
			end
			local api = new("PoEAPI"):PoEAPI("old-token","old-refresh",os.time()+1000,"pob")
			assert.is_nil(api.authToken)
			api:FetchAuthToken(function(problem)
				assert.is_true(problem:find("approved for this edition",1,true)~=nil)
			end)
			api:DownloadWithRefresh("/character",function(response,problem)
				assert.is_nil(response)
				assert.is_true(problem:find("approved for this edition",1,true)~=nil)
			end)
		end
		os.getenv = configured
		local api = new("PoEAPI"):PoEAPI("old-token","old-refresh",os.time()+1000,"different-client")
		assert.is_nil(api.authToken)
		local saved = new("PoEAPI"):PoEAPI("same-token","same-refresh",os.time()+1000,"local-test-client")
		assert.are.equals("same-token",saved.authToken)
	end)

	it("binds configured sessions and uses the approved identity for refresh", function()
		local api = new("PoEAPI"):PoEAPI("old-test-token","old-test-refresh",os.time()-10,"local-test-client")
		local savedClient
		api.UpdateMain = function(self)
			savedClient = self.clientId
		end
		launch.DownloadPage = function(_,url,callback,parameters)
			assert.are.equals("https://www.pathofexile.com/oauth/token",url)
			assert.is_true(parameters.body:find("client_id=local-test-client&grant_type=refresh_token",1,true)~=nil)
			assert.is_true(parameters.header:find("OAuth local-test-client/",1,true)~=nil)
			assert.is_false(parameters.followRedirects)
			callback({body='{"access_token":"fresh-test-token","refresh_token":"fresh-test-refresh","expires_in":3600}'})
		end
		api:ValidateAuth(function(valid) assert.is_true(valid) end)
		assert.are.equals("fresh-test-token",api.authToken)
		assert.are.equals("local-test-client",savedClient)
	end)

	it("stays usable after an error", function()
		local api = new("PoEAPI"):PoEAPI("token", "refresh", os.time() + 3600)

		-- Drive the network layer directly so we bypass ValidateAuth/token
		-- refresh and exercise only DownloadWithRateLimit's limiter bookkeeping.
		-- First attempt fails transiently (dropped connection, no HTTP headers),
		-- second attempt succeeds.
		local attempts = 0
		api.DownloadWithRefresh = function(_, _, onComplete)
			attempts = attempts + 1
			if attempts == 1 then
				onComplete(nil, "SSL connect error")
			else
				onComplete({
					body = '{"characters":[]}',
					header = "HTTP/1.1 200 OK\nX-Rate-Limit-Policy: character-list-request-limit\n",
				}, nil)
			end
		end

		local firstErr
		api:DownloadCharacterList("pc", function(_, err) firstErr = err end)
		assert.are.equals("SSL connect error", firstErr)

		local secondErr
		api:DownloadCharacterList("pc", function(_, err) secondErr = err end)

		-- The second request should reach the network again and succeed. Under
		-- the bug it is short-circuited before DownloadWithRefresh is ever
		-- called, so attempts stays at 1 and secondErr is "Response code: 429".
		assert.are.equals(2, attempts)
		assert.is_nil(secondErr)
	end)
end)
