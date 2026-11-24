-- Run the shared daily sync engine without opening a build or saving desktop settings.
local M = {}

local function exitStatus(failed)
	-- Return a failing task result so Windows can retry a failed refresh.
	local ffi = require("ffi")
	ffi.cdef("void __stdcall ExitProcess(unsigned int exitCode);")
	ffi.C.ExitProcess(failed and 1 or 0)
end

function M.start(app, scheduled)
	local startedMs = app.startTime or GetTime()
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
		-- GetTime and the native launch startTime are milliseconds. Reserve 30 seconds
		-- for the final settings commit, process shutdown, and the Windows task wrapper.
		app.lootSyncLatestStart = scheduled and startedMs + 1000 *
			(sync.taskExecutionSeconds-sync.refreshTimeoutSeconds-sync.workerFinalizationSeconds) or nil
		local errors
		app.lootSyncDue, errors = sync.dueProfiles(app.lootSyncStarted,scheduled)
		app.lootSyncFailed = #errors>0
		for _, failure in ipairs(errors) do
			ConPrintf("Loot filter background sync could not read profile %s: %s",failure.id,failure.message)
		end
		if #app.lootSyncDue == 0 then
			exitStatus(app.lootSyncFailed)
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
	local function failure(message)
		app.lootSyncFailed = true
		ConPrintf("Loot filter background sync attempt failed: %s",tostring(message))
	end
	local function advance(...)
		local ok, problem = pcall(sync.tick,...)
		if ok then return end
		app.lootSyncFailed = true
		local job = sync.busy
		sync.busy = nil
		if job and job.onFailure then
			local recorded, why = pcall(job.onFailure,tostring(problem))
			if not recorded then failure(why) end
		else failure(problem) end
	end
	local ok, finished = pcall(function()
		if sync.busy then advance(os.time()) end
		if sync.busy then return false end
		local nextIndex = app.lootSyncIndex + 1
		local nextProfile = app.lootSyncDue[nextIndex]
		if not nextProfile then return true end
		if app.lootSyncLatestStart and GetTime()>=app.lootSyncLatestStart then
			app.lootSyncDeferred = #app.lootSyncDue-app.lootSyncIndex
			sync.status = string.format("Deferred %d profiles until the next scheduled check.",app.lootSyncDeferred)
			return true
		end
		app.lootSyncIndex = nextIndex
		advance(os.time(),false,app.lootSyncScheduled,nextProfile.id,failure)
		return false
	end)
	if ok and not finished then return end
	ConPrintf("Loot filter background sync: %s", ok and sync.status or tostring(finished))
	exitStatus(not ok or app.lootSyncFailed)
end

return M
