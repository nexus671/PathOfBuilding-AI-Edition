-- Run the shared daily sync engine without opening a build or saving desktop settings.
local M = {}

local function exitStatus(failed)
	-- Return a failing task result so Windows can retry a failed refresh.
	local ffi = require("ffi")
	ffi.cdef("void __stdcall ExitProcess(unsigned int exitCode);")
	ffi.C.ExitProcess(failed and 1 or 0)
end

function M.start(app, scheduled)
	local ok, problem = pcall(function()
		assert(require("ffi").os == "Windows", "Loot filter background sync requires Windows")
		local userPath
		if app.devMode or (GetScriptPath() == GetRuntimePath() and not app.installedMode) then
			userPath = GetScriptPath() .. "/"
		else
			userPath = assert(GetUserPath(), "PoB's Windows Documents folder is unavailable") .. "/Path of Building/"
		end
		LoadModule("Modules/Common")
		main = {userPath=userPath}
		local settings = require("xml").LoadXMLFile(userPath .. "Settings.xml")
		for _, node in ipairs(settings and settings[1] or {}) do
			if type(node) == "table" and node.elem == "Misc" then
				app.connectionProtocol = tonumber(node.attrib.connectionProtocol)
				app.proxyURL = node.attrib.proxyURL
				break
			end
		end
		local sync = require("Modules.LootFilterDailySync")
		app.lootSyncStarted = os.time()
		local config = sync.configuration()
		if not sync.isDue(config, app.lootSyncStarted) or scheduled and config.backgroundEnabled ~= true then
			exitStatus(false)
			return
		end
		app.lootSync = sync
		app.lootSyncRevision = config.revision
		-- The native host dispatches asynchronous downloads from its frame loop.
		RenderInit("DPI_AWARE")
		sync.tick(app.lootSyncStarted, false, scheduled)
	end)
	if not ok then
		ConPrintf("Loot filter background sync could not start: %s", tostring(problem))
		exitStatus(true)
	end
end

function M.frame(app)
	local sync = app.lootSync
	local ok, failed = pcall(function()
		if sync.busy then sync.tick(os.time()) end
		if sync.busy then return end
		local config = sync.configuration()
		local failure = config and config.lastFailure
		local sameProfile = config and config.revision == app.lootSyncRevision
		return sameProfile and failure and failure.startedAt >= app.lootSyncStarted or false
	end)
	if ok and failed == nil then return end
	ConPrintf("Loot filter background sync: %s", ok and sync.status or tostring(failed))
	exitStatus(not ok or failed)
end

return M
