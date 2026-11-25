describe("Update manifest freshness", function()
	it("rejects older releases before downloading files while allowing upgrades and repairs", function()
		local sha1, xml = require("sha1"), require("xml")
		local function manifest(version, hash)
			return '<PoBVersion><Version number="'..version..'" branch="main" platform="win32"/><Source part="default" url="https://example.invalid/{branch}/"/><Source part="program" url="https://example.invalid/{branch}/src/"/><File name="fixture.lua" part="program" sha1="'..hash..'"/></PoBVersion>'
		end
		local file = assert(io.open("UpdateCheck.lua", "r"))
		local source = file:read("*a"):gsub("^#@", "--"); file:close()
		local function check(localVersion, remoteVersion)
			local localManifest = manifest(localVersion, sha1("old"))
			local remoteManifest = manifest(remoteVersion, sha1("new"))
			local callback
			local easy = { escape=function(_, value) return value end, setopt_url=function() end, setopt=function() end,
				setopt_writefunction=function(_, value) callback = value end,
				perform=function() callback(remoteManifest) end, close=function() end }
			local environment = setmetatable({
				require=function(name)
					if name == "lcurl.safe" then return { easy=function() return easy end } end
					if name == "lzip" then return { } end
					if name == "xml" then return setmetatable({ LoadXMLFile=function() return xml.ParseXML(localManifest) end }, { __index=xml }) end
					return require(name)
				end,
				GetScriptPath=function() return "/fixture" end, GetRuntimePath=function() return "/fixture" end,
				ConPrintf=function() end, MakeDir=function() error("download-started") end,
			}, { __index=_G })
			local fn = assert(loadstring(source, "@UpdateCheck.lua")); setfenv(fn, environment)
			return pcall(fn)
		end
		for _, remote in ipairs({ "2.67.2-ai.464bea54", "2.69.0-ai.preview133", "2.69.0-ai.0.9.9" }) do
			local ok, result = check("2.69.0-ai.1.0.0", remote)
			assert.is_true(ok); assert.are.equal("none", result)
		end
		for _, remote in ipairs({ "2.69.0-ai.1.0.0", "2.69.0-ai.1.0.1", "2.70.0-ai.preview1" }) do
			local ok, result = check("2.69.0-ai.1.0.0", remote)
			assert.is_false(ok); assert.matches("download%-started", result)
		end
	end)
	it("bypasses a stale branch manifest before planning any file operations", function()
		local sha1 = require("sha1")
		local xml = require("xml")
		local current = '<PoBVersion><Version number="2.67.2-ai.current" branch="main" platform="win32"/><Source part="default" url="https://example.invalid/{branch}/"/><Source part="program" url="https://example.invalid/{branch}/src/"/><File name="fixture.lua" part="program" sha1="'..sha1("fixture")..'"/></PoBVersion>'
		local stale = current:gsub(sha1("fixture"),sha1("previous"))
		local url, write
		local easy = { }
		function easy:escape(value) return value end
		function easy:setopt_url(value) url = value end
		function easy:setopt() end
		function easy:setopt_writefunction(callback) write = callback end
		function easy:perform() write(url:find("?check=12345",1,true) and current or stale) end
		function easy:close() end
		local file = assert(io.open("UpdateCheck.lua","r"))
		local source = file:read("*a"):gsub("^#@","--"); file:close()
		local environment = setmetatable({
			require=function(name)
				if name == "lcurl.safe" then return { easy=function() return easy end } end
				if name == "lzip" then return { } end
				if name == "xml" then return setmetatable({LoadXMLFile=function() return xml.ParseXML(current) end},{__index=xml}) end
				return require(name)
			end,
			os={ time=function() return 12345 end },
			GetScriptPath=function() return "/fixture" end, GetRuntimePath=function() return "/fixture" end,
			ConPrintf=function() end, MakeDir=function() error("Stale manifest queued a write") end,
			io={open=function(path) return {read=function() return path:match("manifest.xml$") and current or "fixture" end,close=function() end} end},
		}, {__index=_G})
		local check = assert(loadstring(source,"@UpdateCheck.lua"))
		setfenv(check,environment)
		assert.are.equal("none",check())
		assert.is_truthy(url:find("https://example.invalid/main/manifest.xml?check=12345",1,true))
	end)
end)
