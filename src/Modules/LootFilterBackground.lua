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
		app.lootSyncDue = sync.dueProfiles(app.lootSyncStarted,scheduled)
		if #app.lootSyncDue == 0 then
			exitStatus(false)
			return
		end
		app.lootSync = sync
		app.lootSyncScheduled = scheduled
		app.lootSyncIndex = 0
		-- The native host dispatches asynchronous downloads from its frame loop.
		RenderInit("DPI_AWARE")
	end)
	if not ok then
		ConPrintf("Loot filter background sync could not start: %s", tostring(problem))
		exitStatus(true)
	end
end

function M.frame(app)
	local sync = app.lootSync
	local ok, finished = pcall(function()
		if sync.busy then sync.tick(os.time()) end
		if sync.busy then return false end
		local completed = app.lootSyncDue[app.lootSyncIndex]
		if completed then
			local config = sync.configuration(completed.id)
			local failure = config and config.lastFailure
			if config and config.revision == completed.revision and failure and failure.startedAt >= app.lootSyncStarted then
				app.lootSyncFailed = true
			end
		end
		app.lootSyncIndex = app.lootSyncIndex + 1
		local nextProfile = app.lootSyncDue[app.lootSyncIndex]
		if not nextProfile then return true end
		sync.tick(os.time(),false,app.lootSyncScheduled,nextProfile.id)
		return false
	end)
	if ok and not finished then return end
	ConPrintf("Loot filter background sync: %s", ok and sync.status or tostring(finished))
	exitStatus(not ok or app.lootSyncFailed)
end

return M
