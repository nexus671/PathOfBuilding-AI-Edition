local json = require("dkjson")
local sha = require("sha1")
local market = require("Modules.LootFilterEconomy")
local validate = require("Modules.LootFilterSyncValidation")
local M = { status = "Daily sync is disabled." }
local volumeLimit = 2 * 1024 * 1024
local polls, nextSweep, rateLimitUntil = {}, 0, 0
local function nowText(now) return os.date("%Y-%m-%d %H:%M", now) end

local function read(path)
	local file = io.open(path, "rb")
	if not file then return nil end
	local data = file:read(volumeLimit + 1)
	file:close()
	assert(data and #data <= volumeLimit, "Filter or sync record exceeds the size limit")
	return data
end

local windows
local function platform()
	if windows then return windows end
	local ffi = require("ffi")
	assert(ffi.os == "Windows", "Daily filter sync requires the Windows desktop runtime")
	ffi.cdef[[
		int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char *, int, uint16_t *, int);
		int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const uint16_t *, int, char *, int, const char *, int *);
		unsigned long __stdcall GetFinalPathNameByHandleW(void *, uint16_t *, unsigned long, unsigned long);
		int __stdcall MoveFileExW(const uint16_t *, const uint16_t *, unsigned long);
		void * __stdcall CreateFileW(const uint16_t *, unsigned long, unsigned long, void *, unsigned long, unsigned long, void *);
	]]
	-- Use an alias type through a cast so other Windows modules can bind CloseHandle too.
	local kernel = ffi.load("kernel32")
	ffi.cdef[[int __stdcall CloseHandle(void *);]]
	local function wide(path)
		local size = kernel.MultiByteToWideChar(65001, 8, path, -1, nil, 0)
		assert(size > 0, "Invalid file path")
		local buffer = ffi.new("uint16_t[?]", size)
		assert(kernel.MultiByteToWideChar(65001, 8, path, -1, buffer, size) == size, "Invalid file path")
		return buffer
	end
	windows = {
		replace = function(from, to)
			assert(kernel.MoveFileExW(wide(from), wide(to), 9) ~= 0, "Could not replace the file. Check access and file locks.")
		end,
		acquire = function(path)
			-- Zero sharing serializes updates across app windows. Windows releases
			-- the handle on exit, so a crash cannot leave a held lock.
			local handle = kernel.CreateFileW(wide(path), 0x40000000, 0, nil, 4, 0x80, nil)
			assert(handle ~= ffi.cast("void *", -1), "Another PoB window is updating this filter, or the directory is unavailable")
			return function() kernel.CloseHandle(handle) end
		end,
		canonical = function(path)
			local handle = kernel.CreateFileW(wide(path), 0, 7, nil, 3, 0, nil)
			if handle == ffi.cast("void *", -1) then return nil end
			local buffer = ffi.new("uint16_t[32768]")
			local length = kernel.GetFinalPathNameByHandleW(handle, buffer, 32768, 0)
			kernel.CloseHandle(handle)
			if length == 0 or length >= 32768 then return nil end
			local bytes = ffi.new("char[?]", length * 4)
			local count = kernel.WideCharToMultiByte(65001, 0, buffer, length, bytes, length * 4, nil, nil)
			if count > 0 then return ffi.string(bytes, count):lower() end
		end,
	}
	return windows
end

local function put(path, value)
	local temp = path .. ".tmp"
	local file = assert(io.open(temp, "wb"))
	local written, why = file:write(value)
	local closed, closeError = file:close()
	if not written or not closed then
		os.remove(temp)
		error("Could not write sync data: " .. tostring(why or closeError), 0)
	end
	local replaced, replaceError = pcall(platform().replace, temp, path)
	if not replaced then
		os.remove(temp)
		error(replaceError, 0)
	end
end

local function settingsPath(id)
	if id == nil or id == "default" then return main.userPath .. "LootFilterDailySync.json" end
	assert(type(id) == "string" and #id == 40 and id:match("^[a-f0-9]+$"), "Invalid sync profile")
	return main.userPath .. "LootFilterDailySync-" .. id .. ".json"
end

local function lockSettings(run)
	local release = platform().acquire(settingsPath() .. ".lock")
	local ok, result = pcall(run)
	release()
	assert(ok, result)
	return result
end

function M.acquireBackgroundSetup()
	return platform().acquire(settingsPath() .. ".background.lock")
end

local function get(id)
	local raw = read(settingsPath(id))
	if not raw then return nil end
	local config = json.decode(raw)
	assert(type(config) == "table", "Invalid daily filter sync configuration")
	return config
end

local function save(config, id)
	put(settingsPath(id), assert(json.encode(config)))
end

local function registryPath()
	return main.userPath .. "LootFilterSyncProfiles.json"
end

function M.profiles()
	local raw = read(registryPath())
	local entries = raw and json.decode(raw) or (not raw and {})
	assert(type(entries) == "table" and #entries <= 24, "Invalid sync profile list")
	local result, seen = {{id="default",name="Default"}}, {}
	for key in pairs(entries) do
		assert(type(key) == "number" and key == math.floor(key) and key >= 1 and key <= #entries, "Invalid sync profile list")
	end
	for i=1,#entries do
		local row = entries[i]
		assert(type(row) == "table" and type(row.id) == "string" and #row.id == 40 and row.id:match("^[a-f0-9]+$")
			and type(row.name) == "string" and #row.name > 0 and #row.name <= 80 and not row.name:find("[%c]")
			and not seen[row.id], "Invalid sync profile entry")
		seen[row.id] = true
		result[#result+1] = row
	end
	return result
end

local function newRevision()
	return sha(tostring({})..tostring(os.time()))
end

function M.createProfile(name)
	assert(type(name) == "string" and #name <= 80 and not name:find("[%c]"), "Enter a profile name of up to 80 characters")
	name = name:match("^%s*(.-)%s*$")
	assert(name ~= "", "Enter a profile name")
	return lockSettings(function()
		local profiles = M.profiles()
		assert(#profiles < 25, "Up to 25 sync profiles are supported")
		for _, other in ipairs(profiles) do
			assert(other.name:lower() ~= name:lower(), "A profile with that name already exists")
		end
		table.remove(profiles, 1)
		local id = newRevision()
		profiles[#profiles+1] = {id=id,name=name}
		put(registryPath(),assert(json.encode(profiles)))
		return id
	end)
end

local function targetOwner(id, target)
	local canonical = assert(platform().canonical(target), "Could not resolve the destination filter")
	local known = false
	for _, entry in ipairs(M.profiles()) do
		local other = get(entry.id)
		known = known or entry.id == id
		if other and other.baseline then
			assert(platform().canonical(other.baseline) ~= canonical, "Choose a live filter instead of a stored baseline")
		end
		if entry.id ~= id and other and other.target and platform().canonical(other.target) == canonical then return entry.name end
	end
	assert(known, "Choose a saved sync profile")
end

local function enabledStatus(config)
	return string.format("Daily sync enabled at %02d:%02d local time while PoB is open.", config.hour or 9, config.minute or 0)
end

local function failureStatus(record)
	return string.format("%s: %s", nowText(record.checkedAt), record.message)
end

function M.configuration(id)
	return get(id)
end

local function localSchedule(config, date)
	date.hour, date.min, date.sec, date.isdst = config.hour or 9, config.minute or 0, 0, nil
	return os.time(date)
end

local function scheduledAt(config, now)
	local today = localSchedule(config,os.date("*t",now))
	local year, month, day
	if type(config.day) == "string" then year, month, day = config.day:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$") end
	if not year then return today end
	local nextDate = {year=tonumber(year), month=tonumber(month), day=tonumber(day) + (config.intervalDays or 1)}
	return math.max(today,localSchedule(config,nextDate))
end

local function retryAfter(config)
	return config.lastFailure and config.lastFailure.startedAt + 1800 or 0
end

function M.isDue(config, now)
	return config and config.enabled and not config.paused
		and now >= math.max(scheduledAt(config, now), retryAfter(config), config.providerRetryAfter or 0)
end

function M.nextEligible(config, now)
	if not config or not config.enabled or config.paused then return nil end
	local scheduled = scheduledAt(config, now)
	return nowText(math.max(now, scheduled, rateLimitUntil, retryAfter(config), config.providerRetryAfter or 0))
end


-- The AI bridge gets a bounded, path-free view. File names, local settings,
-- protected sample definitions and transport errors stay on the desktop.
local publicCache
function M.publicStatus(now, id)
	id = id or "default"
	if publicCache and publicCache.at == now and publicCache.id == id and publicCache.status == M.status then return publicCache.value end
	local ok, config = pcall(get,id)
	if not ok then return {configured=false,state="settings_error"} end
	if not config then return {configured=false,state="unconfigured"} end
	local review = type(config.review)=="table" and config.review or {}
	local output = {
		configured=true,
		state=M.busy and M.busy.profileId == id and "running" or not config.enabled and "disabled" or config.paused and "paused" or "enabled",
		league=type(config.league)=="string" and config.league:match("^[%w%s_-]+$") and config.league:sub(1,80) or nil,
		lastSuccess=type(config.lastSuccess)=="number" and config.lastSuccess or nil,
		backgroundEnabled=config.backgroundEnabled==true,
		backgroundNotifications=config.backgroundNotifications==true,
		latestChanges={},
	}
	if output.state == "enabled" and type(config.lastFailure) == "table" then
		output.state = "error"
		output.lastFailure = config.lastFailure.checkedAt
		output.warning = "Open the PoB Daily price sync dialog for the latest failure."
	end
	local timeValid, eligible = pcall(M.nextEligible,config,now)
	if timeValid then output.nextEligible = eligible end
	local changes = type(review.changes)=="table" and review.changes or {}
	output.adjustmentCount = #changes
	output.skippedCount = type(review.skipped)=="table" and #review.skipped or 0
	for index, item in ipairs(changes) do
		if index > 40 then break end
		if type(item)=="table" and type(item.name)=="string" and #item.name<=200 and not item.name:find("[%c/\\]")
			and type(item.old)=="number" and type(item.cutoff)=="number" then
			output.latestChanges[#output.latestChanges+1] = {item=item.name,previousCutoff=item.old,proposedCutoff=item.cutoff,
				mapOnly=item.maps==true}
		end
	end
	publicCache = {at=now, id=id, status=M.status, value=output, review=config.review}
	return output
end

local function safeText(value, limit)
	if type(value) == "string" and #value <= limit and not value:find("[%c/\\]") then return value end
end

local function finiteNumber(value)
	if type(value) == "number" and value == value and value > -math.huge and value < math.huge then return value end
end

local function publicImpactSample(sample)
	if type(sample)~="table" then return nil end
	local parser=require("Modules.LootFilterParser")
	return {action=safeText(sample.action,20),class=safeText(sample.class,100),count=finiteNumber(sample.count),
		line=finiteNumber(sample.line),before=safeText(sample.before,20),beforeLine=finiteNumber(sample.beforeLine),area=finiteNumber(sample.area),
		beforeMissing=sample.before=="Unknown" and parser.safeMissingProperties(sample.beforeMissing) or nil,
		afterMissing=sample.action=="Unknown" and parser.safeMissingProperties(sample.afterMissing) or nil}
end

-- Share the verified cutoff decisions, not filter source, target paths or
-- protected drop definitions. These decisions are saved after publication.
function M.publicDiff(now, id)
	local status = M.publicStatus(now,id)
	if not status.configured or not publicCache or type(publicCache.review) ~= "table" then return nil end
	if publicCache.diff then return publicCache.diff end
	local review = publicCache.review
	local changes = {}
	local source = type(review.changes) == "table" and review.changes or {}
	for index, change in ipairs(source) do
		if index > 250 then break end
		local item = type(change) == "table" and safeText(change.name,200)
		if item and finiteNumber(change.old) and finiteNumber(change.cutoff) then
			local sample = publicImpactSample(change.sample)
			local samples={};if type(change.samples)=="table" then for index,entry in ipairs(change.samples) do if index>20 then break end;samples[#samples+1]=publicImpactSample(entry) end end
			changes[#changes+1] = {
				item=item, source=safeText(change.source,40), previousCutoff=change.old,
				proposedCutoff=change.cutoff, quotedPrice=finiteNumber(change.currentPrice or change.price),
				priceUsed=finiteNumber(change.price), volume=finiteNumber(change.volume),
				liquidityUnit=safeText(change.liquidityUnit,40),
				mapOnly=change.maps==true, scope=safeText(change.scope,20),
				sample=sample,samples=#samples>0 and samples or nil,samplesTruncated=type(change.samples)=="table" and #change.samples>20 or nil,
			}
		end
	end
	local ages = {}
	for index, age in ipairs(type(review.ages) == "table" and review.ages or {}) do
		if index > 20 then break end
		local standardAge = finiteNumber(age)
		if standardAge and standardAge >= 0 and standardAge <= 3600 then ages[#ages+1] = standardAge end
	end
	local feeds = {}
	for index, feed in ipairs(type(review.feeds) == "table" and review.feeds or {}) do
		if index > 20 then break end
		local category = type(feed) == "table" and safeText(feed.category,40)
		local age = category and finiteNumber(feed.age)
		if age and age >= 0 and age <= 3600 then
			feeds[#feeds+1] = {category=category, responseAge=age, revalidated=feed.revalidated==true}
		end
	end
	publicCache.diff = {
		checkedAt=finiteNumber(review.checkedAt), verifiedProtection=true,
		responseAges=ages, feeds=feeds, changeCount=#source, changes=changes,
	}
	return publicCache.diff
end

function M.diagnosticReport(now, id)
	local status = M.publicStatus(now,id)
	local config = status.configured and get(id)
	local report = {version=1, capturedAt=now, status=status}
	if config then
		report.dailyTime = string.format("%02d:%02d", config.hour or 9, config.minute or 0)
		report.intervalDays = config.intervalDays or 1
		report.targetChaos = config.targetValue
		report.backupLimit = config.backupLimit
		report.retentionSkipped = config.retentionSkipped
		report.successfulRuns = {}
		for index, run in ipairs(config.history or {}) do
			if index > 30 then break end
			report.successfulRuns[index] = {
				checkedAt=run.checkedAt, adjustments=run.adjustments, oldestResponseAge=run.oldest,
			}
		end
		report.lastReview = M.publicDiff(now,id)
	end
	return assert(json.encode(report, {indent=true}))
end

local function filterPath(path)
	assert(type(path) == "string" and #path <= 1000 and path:match("^%a:[/\\]") and not path:find("[%c]") and path:lower():match("%.filter$"),
		"Enter an absolute Windows .filter path")
	return path
end

function M.selectedLocalFilter(gameDirectory)
	assert(type(gameDirectory) == "string" and gameDirectory:match("^%a:[/\\]"),
		"Path of Exile's local configuration folder is unavailable")
	local config = assert(read(gameDirectory .. "/production_Config.ini"), "Path of Exile's settings file was not found")
	local section, selection
	for line in config:gmatch("[^\r\n]+") do
		local name = line:match("^%s*%[([^%]]+)%]%s*$")
		if name then section = name end
		if section == "UI" then
			local value = line:match("^%s*item_filter%s*=%s*(.-)%s*$")
			if value then
				assert(selection == nil, "Path of Exile's settings have more than one filter selection")
				selection = value
			end
		end
	end
	assert(selection and selection:lower():match("%.filter$") and not selection:find('[%c/\\:*?"<>|]'),
		"Select a local .filter file in Path of Exile")
	local path = filterPath(gameDirectory .. "/" .. selection)
	assert(read(path), "The local filter selected in Path of Exile was not found")
	return path
end

local function expectedPath(hash)
	assert(type(hash) == "string" and #hash == 40 and hash:match("^[a-f0-9]+$"), "Invalid expected filter checksum")
	return main.userPath .. "LootFilterExpected-" .. hash .. ".filter"
end

local function keepExpected(raw)
	local path = expectedPath(sha(raw))
	if not read(path) then put(path,raw) end
	assert(read(path) == raw, "Expected filter snapshot could not be verified")
end

function M.verifiedOutput(id)
	local config = assert(get(id), "Enable and run daily sync first")
	assert(not M.busy and config.lastSuccess and config.review and not config.pending,
		"A completed, verified local refresh is required")
	local raw = assert(read(filterPath(config.target)), "Target filter file was not found")
	assert(sha(raw) == config.current, "The local filter changed after the verified refresh")
	validate(raw,{},true,config.targetValue,config.protections,nil,nil,nil,config.pickupPolicy)
	return raw, {digest=config.current, revision=config.revision, realm=config.realm or "pc", checkedAt=config.lastSuccess}
end

function M.externalDiff(id)
	local config = assert(get(id), "No saved sync setup")
	assert(not M.busy, "Wait for the current sync to finish")
	local actual = assert(read(filterPath(config.target)), "Target filter file was not found")
	assert(sha(actual) ~= config.current and sha(actual) ~= config.pending, "The live filter matches the saved sync state")
	local expected = read(expectedPath(config.current))
	if not expected then
		local baseline = read(config.baseline)
		if baseline and sha(baseline)==config.current then expected = baseline end
	end
	assert(expected and sha(expected)==config.current, "No verified previous filter is available for this setup. Preview against the fixed baseline instead.")
	return expected, actual
end

local function verifyUnmanagedRules(target, baseline)
	local targetStart, targetEnd = market.sectionBounds(target)
	local baseStart, baseEnd = market.sectionBounds(baseline)
	assert(targetStart and targetEnd and baseStart and baseEnd
		and target:sub(1,targetStart-1) == baseline:sub(1,baseStart-1)
		and target:sub(targetEnd) == baseline:sub(baseEnd),
		"Baseline and target have different rules outside the economy section. Review edits and choose an updated baseline.")
end

local function prepare(target, baselineFile, league, options)
	options = options or {}
	local targetValue = options.targetValue or 1
	local pickupPolicy = market.pickupPolicy(targetValue, options.pickupPolicy)
	local hour, minute = options.hour or 9, options.minute or 0
	local intervalDays = options.intervalDays or 1
	assert(type(intervalDays) == "number" and intervalDays >= 1 and intervalDays <= 7
		and intervalDays == math.floor(intervalDays), "Enter a refresh interval from 1 to 7 days")
	assert(type(hour) == "number" and hour >= 0 and hour <= 23 and hour == math.floor(hour), "Enter an hour from 0 to 23")
	assert(type(minute) == "number" and minute >= 0 and minute <= 59 and minute == math.floor(minute), "Enter a minute from 0 to 59")
	assert(type(targetValue) == "number" and targetValue > 0 and targetValue <= 1000, "Enter a stack target above 0 and up to 1,000 chaos")
	target = filterPath(target)
	assert(type(league) == "string" and #league <= 80 and league:match("^[%w%s_-]+$"), "Enter the poe.ninja league ID")
	local original = assert(read(target), "Target filter file was not found")
	local baseline = assert(read(filterPath(baselineFile)), "Baseline filter was not found")
	local protections
	if options.protectionFile and options.protectionFile ~= "" then
		assert(options.protectionFile:lower():match("%.json$"), "Choose a protected sample JSON file")
		local samples = assert(read(options.protectionFile), "Protected sample file was not found")
		local decoded, _, why = json.decode(samples)
		protections = assert(decoded, why or "Invalid protected sample JSON")
	elseif not baseline:find("# CUSTOM: Always show Cord Belts", 1, true) then
		error("Choose a protected sample JSON file for this baseline")
	end
	validate(baseline, {}, true, targetValue, protections, nil, nil, nil, pickupPolicy)
	validate(original, {}, true, targetValue, protections, nil, nil, nil, pickupPolicy)
	verifyUnmanagedRules(original, baseline)
	local key = sha(baseline)
	return {
		enabled=true, target=target, baseline=main.userPath.."LootFilterBaseline-"..key..".filter",
		baselineHash=key, current=sha(original),
		league=league, realm="pc", hour=hour, minute=minute, intervalDays=intervalDays, targetValue=targetValue, pickupPolicy=pickupPolicy,
		protections=protections, protectionFile=options.protectionFile,
	}, original, baseline
end

function M.setBackground(enabled, previousRevision, id)
	lockSettings(function()
		local config = assert(get(id), "Enable daily sync first")
		assert(config.revision == previousRevision, "Daily sync settings changed in another PoB window. Try again.")
		config.backgroundEnabled = enabled
		config.revision = newRevision()
		save(config,id)
	end)
end

function M.setBackgroundNotifications(enabled, id)
	lockSettings(function()
		local config = assert(get(id), "Enable daily sync first")
		assert(config.backgroundEnabled, "Enable background sync first")
		config.backgroundNotifications = enabled
		save(config,id)
	end)
end

function M.configure(target, baselineFile, league, options)
	local id = options and options.profileId or "default"
	assert(not M.busy, "Wait for the current sync to finish")
	local config = lockSettings(function()
		local nextConfig, original, baseline = prepare(target, baselineFile, league, options)
		local owner = targetOwner(id,target)
		assert(not owner, "This destination already belongs to " .. tostring(owner))
		local current = get(id)
		nextConfig.backgroundEnabled = current and current.backgroundEnabled == true
		nextConfig.backgroundNotifications = current and current.backgroundNotifications == true
		nextConfig.providerRetryAfter = current and current.providerRetryAfter
		nextConfig.backupLimit = current and current.backupLimit
		if current and current.league == nextConfig.league and current.baselineHash == nextConfig.baselineHash then
			nextConfig.priceHistory = current.priceHistory
			if nextConfig.backupLimit and current.target == nextConfig.target and current.current == nextConfig.current and not current.pending then
				nextConfig.backup, nextConfig.history = current.backup, current.history
				nextConfig.restoreBackups = current.restoreBackups
			end
		end
		nextConfig.revision = newRevision()
		if not read(nextConfig.baseline) then put(nextConfig.baseline, baseline) end
		assert(read(nextConfig.baseline) == baseline, "Stored baseline does not match")
		keepExpected(original)
		save(nextConfig,id)
		return nextConfig
	end)
	polls[id or "default"], nextSweep = nil, 0
	M.status = enabledStatus(config)
end

function M.disable(id)
	assert(not M.busy, "Wait for the current sync to finish")
	lockSettings(function()
		local config = get(id)
		if config then config.enabled = false; save(config,id) end
	end)
	M.status = "Daily sync is disabled."
end

function M.pause(paused, id)
	assert(not M.busy, "Wait for the current sync to finish")
	lockSettings(function()
		local config = assert(get(id), "Enable daily sync first")
		config.paused = paused
		save(config,id)
	end)
	polls[id or "default"], nextSweep = nil, 0
	M.status = paused and "Daily sync is paused." or "Daily sync resumed."
end

local function backupChoices(config, limit)
	local entries, seen = {}, {}
	local function add(digest, checkedAt)
		if type(digest) == "string" and #digest == 40 and digest:match("^[a-f0-9]+$")
			and digest ~= config.current and not seen[digest] then
			seen[digest] = true
			entries[#entries+1] = {digest=digest,checkedAt=checkedAt}
		end
	end
	add(config.backup)
	local recorded = {}
	for _, run in ipairs(config.history or {}) do
		if type(run)=="table" and type(run.backup)=="string" then
			recorded[#recorded+1] = {digest=run.backup,checkedAt=run.checkedAt}
		end
	end
	for _, saved in ipairs(config.restoreBackups or {}) do
		if type(saved)=="table" and type(saved.digest)=="string" then
			recorded[#recorded+1] = {digest=saved.digest,checkedAt=saved.checkedAt}
		end
	end
	table.sort(recorded,function(left,right)
		local leftTime, rightTime = tonumber(left.checkedAt) or 0, tonumber(right.checkedAt) or 0
		if leftTime==rightTime then return left.digest<right.digest end
		return leftTime>rightTime
	end)
	for _, entry in ipairs(recorded) do
		if #entries >= (limit or 30) then break end
		add(entry.digest,tonumber(entry.checkedAt))
	end
	return entries, seen
end

function M.setBackupLimit(id, limit, revision)
	assert(not M.busy, "Wait for the current sync to finish")
	assert(type(limit) == "number" and limit >= 0 and limit <= 30 and limit == math.floor(limit),
		"Enter a whole number from 0 to 30")
	lockSettings(function()
		local config = assert(get(id), "Enable daily sync first")
		assert(config.revision == revision, "Daily sync settings changed. Reopen backup retention.")
		config.backupLimit, config.revision = limit>0 and limit or nil, newRevision()
		config.retentionSkipped = nil
		save(config,id)
	end)
end

local function pruneBackups(config, choices)
	local removed, skipped = {}, 0
	for index=config.backupLimit+1,#choices do
		local digest = choices[index].digest
		local path = config.target .. ".before-pob-sync-" .. digest .. ".bak"
		local checked, raw = pcall(read,path)
		if checked and raw and sha(raw)==digest and os.remove(path) then
			removed[digest] = true
		else
			skipped = skipped+1
		end
	end
	for _, run in ipairs(config.history) do
		if removed[run.backup] then run.backup = nil end
	end
	for index=#(config.restoreBackups or {}),1,-1 do
		if removed[config.restoreBackups[index].digest] then table.remove(config.restoreBackups,index) end
	end
	config.retentionSkipped = skipped>0 and skipped or nil
end

local restoreSummary = "Restored the verified backup. Daily sync is paused."

local function finishRestore(config, digest, undo)
	if undo then
		local list = config.restoreBackups or {}
		for index=#list,1,-1 do
			if list[index].digest==undo then table.remove(list,index) end
		end
		table.insert(list,1,{digest=undo,checkedAt=os.time()})
		if #list>30 then table.remove(list) end
		config.restoreBackups = list
	end
	config.current, config.pending, config.backup = digest, nil, undo
	config.pendingRestore = nil
	config.summary, config.review = restoreSummary, nil
	config.revision = newRevision()
end

function M.backups(id)
	return lockSettings(function()
		local config = assert(get(id), "Enable daily sync first")
		if config.pendingRestore then
			local target = assert(read(filterPath(config.target)), "Target filter is missing")
			local actual = sha(target)
			if actual == config.pending then
				finishRestore(config,actual,config.pendingRestore.undo)
			else
				assert(actual == config.current, "Target changed during the interrupted restore")
				config.pending, config.pendingRestore = nil, nil
			end
			save(config,id)
		end
		return backupChoices(config)
	end)
end

local function readBackup(target, digest)
	local raw = assert(read(target .. ".before-pob-sync-" .. digest .. ".bak"), "Backup is missing")
	assert(sha(raw) == digest, "Backup checksum mismatch")
	return raw
end

local function verifyRestorable(config, requested)
	local target = filterPath(config.target)
	local original = assert(read(target), "Target filter is missing")
	assert(sha(original) == config.current, "Target was edited outside PoB")
	local _, available = backupChoices(config)
	assert(available[requested], "Choose a backup recorded for this sync profile")
	local backup = readBackup(target,requested)
	local baseline = assert(read(config.baseline), "Baseline filter is missing")
	assert(sha(baseline) == config.baselineHash, "Baseline checksum changed")
	verifyUnmanagedRules(backup,baseline)
	validate(backup,{},true,config.targetValue,config.protections,nil,nil,nil,config.pickupPolicy)
	return original, backup, target
end

function M.previewBackup(id, digest)
	assert(not M.busy, "Wait for the current sync to finish")
	return lockSettings(function()
		local config = assert(get(id), "Enable daily sync first")
		assert(not config.pending, "Finish recovering the interrupted sync before restoring a backup")
		local before, after = verifyRestorable(config,digest)
		return {before=before,after=after,digest=digest,revision=config.revision,current=config.current}
	end)
end

function M.rollback(id, reviewed)
	assert(not M.busy, "Wait for the current sync to finish")
	lockSettings(function()
		local config = assert(get(id), "Enable daily sync first")
		local digest = reviewed and reviewed.digest or config.backup
		assert(digest, "No verified backup is available")
		assert(not config.pendingRestore, "Reopen Review backups to recover the interrupted restore")
		local original, backup, target = verifyRestorable(config,digest)
		local undo
		if reviewed then
			assert(not config.pending and config.revision == reviewed.revision and config.current == reviewed.current
				and original == reviewed.before and backup == reviewed.after, "Filter or sync settings changed after the review")
			undo = config.current
			local undoPath = target .. ".before-pob-sync-" .. undo .. ".bak"
			if not read(undoPath) then put(undoPath,original) end
			assert(read(undoPath) == original, "Current filter backup could not be verified")
		end
		keepExpected(backup)
		config.pending, config.paused = digest, true
		config.pendingRestore = {undo=undo}
		save(config,id)
		assert(read(target) == original, "Target changed before rollback")
		put(target, backup)
		assert(read(target) == backup, "Rollback verification failed")
		finishRestore(config,digest,undo)
		save(config,id)
	end)
	M.status = restoreSummary
end

local months = {Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}
local function days(year, month, day)
	year = year - (month < 3 and 1 or 0)
	local era = math.floor(year / 400)
	local y = year - era * 400
	local m = month + (month > 2 and -3 or 9)
	return era * 146097 + y * 365 + math.floor(y / 4) - math.floor(y / 100) + math.floor((153 * m + 2) / 5) + day - 719469
end

local function headers(response)
	local input = type(response) == "table" and response.header or ""
	if type(input) ~= "string" then return {} end
	local result = {}
	-- Proxy and redirect headers can precede the final response.
	for line in input:gmatch("[^\r\n]+") do
		if line:match("^HTTP/[%d%.]+") then result = {} end
		local key, value = line:match("^([%w-]+):[ \t]*(.-)[ \t]*$")
		if key then
			key = key:lower()
			if key=="age" or key=="date" or key=="etag" or key=="retry-after" or key=="cf-cache-status" then
				assert(result[key]==nil, "Duplicate exchange freshness or cache header")
				result[key] = value
			end
		end
	end
	return result
end

local function httpDate(date)
	local d, mo, y, h, mi, s
	if date then d, mo, y, h, mi, s = date:match("^%a+, (%d%d) (%a+) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$") end
	if not (y and months[mo]) then return nil end
	d, y, h, mi, s = tonumber(d), tonumber(y), tonumber(h), tonumber(mi), tonumber(s)
	local month = months[mo]
	local leap = y%4==0 and (y%100~=0 or y%400==0)
	local length = ({31,leap and 29 or 28,31,30,31,30,31,31,30,31,30,31})[month]
	if y < 1970 or d < 1 or d > length or h > 23 or mi > 59 or s > 59 then return nil end
	return days(y, month, d)*86400 + h*3600 + mi*60 + s
end

local function responseAge(header, now, cachedAge)
	local timestamp = httpDate(header.date)
	assert(timestamp or cachedAge and not header.date, "Exchange response has no valid freshness date")
	local age = header.age and tonumber(header.age:match("^%d+$")) or (not header.age and 0)
	assert(age, "Exchange response has an invalid Age header")
	local resident = math.max(timestamp and now - timestamp or 0, age, cachedAge or 0)
	assert((header["cf-cache-status"] or ""):lower() ~= "stale" and (not timestamp or timestamp <= now + 300)
		and resident <= 3600, "Exchange snapshot is stale")
	return resident
end

function M.fresh(response, now)
	local header = headers(response)
	local resident = responseAge(header, now)
	local tag = header.etag
	if tag and (#tag > 160 or tag:find("[%c]") or not (tag:match('^"[^"]*"$') or tag:match('^W/"[^"]*"$'))) then tag = nil end
	return response.body, resident, tag
end

local function rememberFailure(config, startedAt, message, id)
	-- A failed attempt may race with another window. Only record it for
	-- this configuration and preserve a newer successful or failed attempt.
	pcall(function()
		lockSettings(function()
			local current = get(id)
			if not current or current.revision ~= config.revision or not current.enabled or current.paused
				or current.lastSuccess and current.lastSuccess >= startedAt
				or current.lastFailure and current.lastFailure.startedAt > startedAt then return end
			if rateLimitUntil > os.time() then
				current.providerRetryAfter = math.max(current.providerRetryAfter or 0, rateLimitUntil)
			end
			current.lastFailure = {
				startedAt=startedAt, checkedAt=os.time(),
				message=tostring(message):gsub("[%c]", " "):sub(1,350),
			}
			save(current,id)
		end)
	end)
end

local function publish(config, bodies, feeds, day, force, now, id)
	return lockSettings(function()
		local current = get(id)
		assert(current and current.enabled and not current.paused and current.baselineHash == config.baselineHash and current.target == config.target
			and current.revision == config.revision and current.league == config.league and current.targetValue == config.targetValue and current.hour == config.hour and current.minute == config.minute and current.protectionFile == config.protectionFile, "Daily sync settings changed during the refresh")
		if not force and current.day == day then return "Already synced today." end
		local original = assert(read(current.target), "Target filter is missing")
		local before = sha(original)
		assert(before == current.current or before == current.pending, "Target was edited outside PoB. Review and re-enable sync to adopt your edits.")
		local baseline = assert(read(current.baseline), "Baseline filter is missing")
		assert(sha(baseline) == current.baselineHash, "Baseline checksum changed")
		verifyUnmanagedRules(original, baseline)
		local candidate, count, changes, skipped, snapshots = validate(
			baseline, bodies, false, current.targetValue, current.protections, current.priceHistory, day, now, current.pickupPolicy)
		current.priceHistory = snapshots
		keepExpected(candidate)
		if candidate ~= original then
			local backup = current.target .. ".before-pob-sync-" .. before .. ".bak"
			if not read(backup) then put(backup, original) end
			current.backup = before
			assert(read(backup) == original and read(current.target) == original, "Backup or target changed during sync")
			current.current, current.pending = before, sha(candidate)
			save(current,id)
			assert(read(current.target) == original, "Target changed before replacement")
			put(current.target, candidate)
		end
		assert(read(current.target) == candidate, "Installed filter verification failed")
		current.current, current.pending, current.day = sha(candidate), nil, day
		current.pendingRestore = nil
		current.summary = string.format("%s: %d stack adjustments from the baseline. Protected drops verified.", nowText(now), count)
		current.lastSuccess, current.lastFailure, current.providerRetryAfter = now, nil, nil
		local ages = {}
		for index, feed in ipairs(feeds) do ages[index] = feed.age end
		current.review = {changes=changes, skipped=skipped, checkedAt=now, backup=current.backup, ages=ages, feeds=feeds}
		current.history = current.history or {}
		table.insert(current.history, 1, {checkedAt=now, adjustments=count, backup=current.backup, oldest=math.max(unpack(ages))})
		local limit = current.backupLimit
		local backups = type(limit)=="number" and limit>=1 and limit<=30 and limit==math.floor(limit) and backupChoices(current,62)
		if #current.history > 30 then table.remove(current.history) end
		save(current,id)
		if backups then
			pruneBackups(current,backups)
			pcall(save,current,id)
		end
		return current.summary
	end)
end

local cache = {}
local function storeFeed(url, entry)
	if not cache[url] then
		local count, oldest, oldestTime = 0, nil, math.huge
		for key, value in pairs(cache) do
			count = count + 1
			if value.checkedAt < oldestTime then oldest, oldestTime = key, value.checkedAt end
		end
		if count >= 24 then cache[oldest] = nil end
	end
	cache[url] = entry
end

local function fetchPrices(config, baseline, now, complete, onFailure, id)
	local categories = market.feedCategories(baseline)
	local job, bodies, responses = {onFailure=onFailure,profileId=id}, {}, {}
	M.busy, M.deadline = job, now + 300
	local function finish(success, message)
		M.busy = nil
		M.status = success and message or ("Sync skipped: " .. tostring(message))
		if not success and onFailure then onFailure(M.status) end
		if ConPrintf then ConPrintf("%s", M.status) end
	end
	local function diagnoseLeague(problem)
		if os.time()+15 >= M.deadline then finish(false,problem); return end
		M.status = "Checking current PC trade league availability."
		launch:DownloadPage(market.endpoint.."leagues",function(response,err)
			if M.busy ~= job then return end
			if not err then
				local valid, _, leagues = pcall(function()
					return market.tradeLeagues(M.fresh(response,os.time()))
				end)
				if valid and not leagues[config.league] then
					finish(false,"The configured league is no longer listed by the price provider. Use Choose league to review available seasons. The existing filter was kept.")
					return
				end
			end
			finish(false,problem)
		end,{timeout=15,maxBytes=65536,header="Accept: application/json"})
	end
	local function fetch(index, attempt)
		local category = categories[index]
		if not category then
			local finishedAt = os.time()
			local feeds = {}
			for index, response in ipairs(responses) do
				local age = response.initialAge + math.max(0, finishedAt - response.checkedAt)
				if age > 3600 then finish(false, categories[index] .. ": snapshot expired before the refresh finished."); return end
				feeds[index] = {category=categories[index], age=age, revalidated=response.revalidated}
			end
			finish(pcall(complete, bodies, feeds))
			return
		end
		M.status = "Fetching " .. config.league .. " prices: " .. category
		local url = market.endpoint .. market.feedPath(config.league, category)
		local cached, time = cache[url], os.time()
		local cachedAge = cached and (time - cached.sourceAt)
		local requestHeaders = "Accept: application/json"
		if cached and cached.tag and cachedAge >= 0 and cachedAge <= 3600 then
			requestHeaders = requestHeaders .. "\r\nIf-None-Match: " .. cached.tag
		else
			cached = nil
		end
		local function defer(delay, message, callback)
			job.resumeAt, job.resume = time + delay, callback
			M.status = message
		end
		launch:DownloadPage(url, function(response, err)
			if M.busy ~= job then return end
			time = os.time()
			if err == "Response code: 304" and cached and time >= cached.sourceAt and time-cached.sourceAt <= 3600 then
				local valid, age = pcall(function() return responseAge(headers(response), time, time-cached.sourceAt) end)
				if not valid then finish(false, category .. ": " .. tostring(age)); return end
				cached.sourceAt = time-age
				bodies[index], responses[index] = cached.body, {initialAge=age, checkedAt=time, revalidated=true}
				fetch(index + 1, 1)
				return
			end
			if err then
				local status = tonumber(err:match("^Response code: (%d+)$"))
				local retryable = status == 429 or status and status >= 500 and status <= 599 or not status
				local delay = 5
				if status == 429 or status == 503 then
					local ok, values = pcall(headers, response)
					local value = ok and values["retry-after"]
					local retryDate = value and httpDate(value)
					delay = math.max(15, tonumber(value) or (retryDate and retryDate-time) or 60)
				end
				if retryable and attempt < 2 and delay <= 90 and time + delay + 20 < M.deadline then
					defer(delay, category .. ": retrying the exchange request.", function() fetch(index, attempt + 1) end)
					return
				end
				if status == 429 or status == 503 then rateLimitUntil = math.max(rateLimitUntil, time + delay) end
				local problem = category .. ": " .. err
				if index == 1 and status == 404 then diagnoseLeague(problem) else finish(false,problem) end
				return
			end
			local fresh, data, age, tag = pcall(M.fresh, response, time)
			if not fresh then finish(false, category .. ": " .. tostring(data)); return end
			local valid, why = pcall(market.quotes, data, category)
			if not valid then
				local problem = category .. ": " .. tostring(why)
				if index == 1 and tostring(why):find("No priced exchange items",1,true) then
					diagnoseLeague(problem)
				else
					finish(false,problem)
				end
				return
			end
			storeFeed(url,{body=data,tag=tag,sourceAt=time-age,checkedAt=time})
			bodies[index], responses[index] = data, {initialAge=age, checkedAt=time, revalidated=false}
			fetch(index + 1, 1)
		end, {timeout=20,maxBytes=2*1024*1024,header=requestHeaders})
	end
	fetch(1, 1)
end

function M.tick(now, force, scheduled, id)
	id = id or "default"
	if M.busy then
		if now > M.deadline then
			local onFailure = M.busy.onFailure
			M.busy = nil
			M.status = "Daily sync timed out. The existing filter was kept."
			if onFailure then onFailure(M.status) end
		elseif M.busy.resumeAt and now >= M.busy.resumeAt then
			local run = M.busy.resume
			M.busy.resumeAt, M.busy.resume = nil, nil
			run()
		end
		return
	end
	if now < rateLimitUntil then
		if force then M.status = "Waiting before contacting the exchange again." end
		return
	end
	if not force and now < (polls[id] or 0) then return end
	polls[id] = now + 60
	local ok, config = pcall(get,id)
	if not ok then M.status = tostring(config); return end
	if not config or not config.enabled or config.paused or scheduled and not config.backgroundEnabled then return end
	if now < (config.providerRetryAfter or 0) then
		if force then M.status = "Waiting before contacting the exchange again." end
		return
	end
	local day = os.date("%Y-%m-%d", now)
	if not force and not M.isDue(config, now) then
		M.status = config.lastFailure and failureStatus(config.lastFailure) or config.summary or enabledStatus(config)
		return
	end
	local function onFailure(message) rememberFailure(config, now, message, id) end
	if launch.noSSL then
		M.status = "Sync skipped: enable HTTPS certificate verification in PoB."
		onFailure(M.status)
		return
	end
	local ready, baseline = pcall(function()
		local original = assert(read(filterPath(config.target)), "Target filter is missing")
		local current = sha(original)
		assert(current == config.current or current == config.pending, "Target was edited outside PoB. Compare External edits before re-enabling.")
		local raw = assert(read(config.baseline), "Baseline filter is missing")
		assert(sha(raw) == config.baselineHash, "Baseline checksum changed")
		verifyUnmanagedRules(original, raw)
		return raw
	end)
	if not ready then
		M.status = "Sync skipped: " .. tostring(baseline)
		onFailure(M.status)
		return
	end
	fetchPrices(config, baseline, now, function(bodies, feeds)
		return publish(config, bodies, feeds, day, force, now, id)
	end, onFailure, id)
end

function M.dueProfiles(now, scheduled)
	local due = {}
	if now < rateLimitUntil then return due end
	for _, entry in ipairs(M.profiles()) do
		local ok, config = pcall(get,entry.id)
		if ok and config and (not scheduled or config.backgroundEnabled) and now >= (polls[entry.id] or 0) and M.isDue(config,now) then
			due[#due+1] = {id=entry.id,revision=config.revision}
		end
	end
	return due
end

function M.tickAll(now)
	if M.busy then M.tick(now); return end
	if now < nextSweep then return end
	local ok, due = pcall(M.dueProfiles,now)
	if ok and due[1] then
		M.tick(now,false,false,due[1].id)
	else
		nextSweep = now + 60
		if not ok then M.status = tostring(due) end
	end
end

function M.profileStatus(id)
	if M.busy and M.busy.profileId == (id or "default") then return M.status end
	local config = get(id)
	if not config or not config.enabled then return "Daily sync is disabled." end
	if config.paused then return "Daily sync is paused." end
	return config.lastFailure and failureStatus(config.lastFailure) or config.summary or enabledStatus(config)
end

function M.preview(target, baselineFile, league, options, callback, onFailure)
	assert(not M.busy, "Wait for the current sync to finish")
	assert(not launch.noSSL, "Enable HTTPS certificate verification in PoB")
	assert(os.time() >= rateLimitUntil, "Wait before contacting the rate-limited exchange again")
	local config, original, baseline = prepare(target, baselineFile, league, options)
	local now = os.time()
	local id = options and options.profileId or "default"
	local found, saved = pcall(get,id)
	local history = found and saved and saved.league == config.league and saved.baselineHash == config.baselineHash and saved.priceHistory
	local day = history and os.date("%Y-%m-%d", now) or nil
	fetchPrices(config, baseline, now, function(bodies)
		local candidate = validate(baseline, bodies, false, config.targetValue, config.protections, history, day, now, config.pickupPolicy)
		callback(original, candidate)
		return "Preview complete. Review the proposed filter before enabling sync."
	end, onFailure, id)
end

return M
