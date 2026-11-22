local json = require("dkjson")
local sha = require("sha1")
local market = require("Modules.LootFilterEconomy")
local validate = require("Modules.LootFilterSyncValidation")
local M = { status = "Daily sync is disabled." }
local volumeLimit = 2 * 1024 * 1024
local nextPoll, retryAt = 0, 0
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
		lock = function(path, run)
			-- Zero sharing serializes updates across app windows. Windows releases
			-- the handle on exit, so a crash cannot leave a held lock.
			local handle = kernel.CreateFileW(wide(path), 0x40000000, 0, nil, 4, 0x80, nil)
			assert(handle ~= ffi.cast("void *", -1), "Another PoB window is updating this filter, or the directory is unavailable")
			local ok, result = pcall(run)
			kernel.CloseHandle(handle)
			assert(ok, result)
			return result
		end,
	}
	return windows
end

local function put(path, value)
	local temp = path .. ".tmp"
	local file = assert(io.open(temp, "wb"))
	local written, why = file:write(value)
	local closed = file:close()
	assert(written and closed, "Could not write sync data: " .. tostring(why))
	platform().replace(temp, path)
end

local function settingsPath()
	return main.userPath .. "LootFilterDailySync.json"
end

local function get()
	local raw = read(settingsPath())
	if not raw then return nil end
	local config = json.decode(raw)
	assert(type(config) == "table", "Invalid daily filter sync configuration")
	return config
end

local function save(config)
	put(settingsPath(), json.encode(config))
end

function M.configuration()
	return get()
end

function M.nextEligible(config, now)
	if not config or not config.enabled or config.paused then return nil end
	local date = os.date("*t", now)
	if config.day == os.date("%Y-%m-%d", now) then date.day = date.day + 1 end
	date.hour, date.min, date.sec, date.isdst = config.hour or 9, 0, 0, nil
	local scheduled = math.max(now, os.time(date))
	return nowText(math.max(scheduled, retryAt))
end

local function filterPath(path)
	assert(type(path) == "string" and #path <= 1000 and path:match("^%a:[/\\]") and not path:find("[%c]") and path:lower():match("%.filter$"),
		"Enter an absolute Windows .filter path")
	return path
end

function M.configure(target, baselineFile, league, options)
	options = options or {}
	local targetValue = options.targetValue or 1
	local hour = options.hour or 9
	assert(type(hour) == "number" and hour >= 0 and hour <= 23 and hour == math.floor(hour), "Enter an hour from 0 to 23")
	assert(type(targetValue) == "number" and targetValue > 0 and targetValue <= 1000, "Enter a stack target above 0 and up to 1,000 chaos")
	assert(not M.busy, "Wait for the current sync to finish")
	platform().lock(settingsPath() .. ".lock", function()
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
		validate(baseline, {}, true, targetValue, protections)
		validate(original, {}, true, targetValue, protections)
		local a, b = market.sectionBounds(original), market.sectionBounds(baseline)
		assert(a and b and original:sub(1,a-1) == baseline:sub(1,b-1), "Baseline and target must share the protected rule prefix")
		local key = sha(baseline)
		local path = main.userPath .. "LootFilterBaseline-" .. key .. ".filter"
		if not read(path) then put(path, baseline) end
		assert(read(path) == baseline, "Stored baseline does not match")
		save({enabled=true, target=target, baseline=path, baselineHash=key, current=sha(original), revision=sha(tostring({}) .. tostring(os.time())), league=league, hour=hour, targetValue=targetValue, protections=protections, protectionFile=options.protectionFile})
	end)
	nextPoll, retryAt = 0, 0
	M.status = string.format("Daily sync enabled at %02d:00 local time while PoB is open.", hour)
end

function M.disable()
	assert(not M.busy, "Wait for the current sync to finish")
	platform().lock(settingsPath() .. ".lock", function()
		local config = get()
		if config then config.enabled = false; save(config) end
	end)
	M.status = "Daily sync is disabled."
end

function M.pause(paused)
	assert(not M.busy, "Wait for the current sync to finish")
	platform().lock(settingsPath() .. ".lock", function()
		local config = assert(get(), "Enable daily sync first")
		config.paused = paused
		save(config)
	end)
	nextPoll, retryAt = 0, 0
	M.status = paused and "Daily sync is paused." or "Daily sync resumed."
end

function M.rollback()
	assert(not M.busy, "Wait for the current sync to finish")
	platform().lock(settingsPath() .. ".lock", function()
		local config = assert(get(), "Enable daily sync first")
		assert(config.backup and config.backup:match("^[a-f0-9]+$") and #config.backup == 40, "No verified backup is available")
		local target = filterPath(config.target)
		local original = assert(read(target), "Target filter is missing")
		assert(sha(original) == config.current, "Target was edited outside PoB")
		local backup = assert(read(target .. ".before-pob-sync-" .. config.backup .. ".bak"), "Backup is missing")
		assert(sha(backup) == config.backup, "Backup checksum mismatch")
		config.pending = config.backup
		config.paused = true
		save(config)
		assert(read(target) == original, "Target changed before rollback")
		put(target, backup)
		assert(read(target) == backup, "Rollback verification failed")
		config.current, config.pending, config.backup = config.backup, nil, nil
		config.summary = "Restored the verified backup. Daily sync is paused."
		config.review = nil
		save(config)
	end)
	M.status = "Restored the verified backup. Daily sync is paused."
end

local months = {Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}
local function days(year, month, day)
	year = year - (month < 3 and 1 or 0)
	local era = math.floor(year / 400)
	local y = year - era * 400
	local m = month + (month > 2 and -3 or 9)
	return era * 146097 + y * 365 + math.floor(y / 4) - math.floor(y / 100) + math.floor((153 * m + 2) / 5) + day - 719469
end

function M.fresh(response, now)
	local header = response.header or ""
	-- Redirects and proxies can emit several header blocks. Use the last response.
	for block in header:gmatch("(HTTP/[%d%.]+[^\r]*\r?\n.-\r?\n)\r?\n") do header = block end
	local date = ("\n"..header):match("\n[Dd][Aa][Tt][Ee]:%s*([^\r\n]+)")
	local d, mo, y, h, mi, s
	if date then d, mo, y, h, mi, s = date:match("^%a+, (%d%d) (%a+) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$") end
	assert(y and months[mo], "Exchange response has no valid freshness date")
	local timestamp = days(tonumber(y), months[mo], tonumber(d))*86400 + h*3600 + mi*60 + s
	local age = tonumber(("\n"..header:lower()):match("\nage:[ \t]*(%d+)")) or 0
	assert(not header:lower():find("cf%-cache%-status:[ \t]*stale") and timestamp <= now + 300
		and math.max(now - timestamp, age) <= 3600, "Exchange snapshot is stale")
	return response.body
end

local function publish(config, bodies, day, force, now)
	return platform().lock(settingsPath() .. ".lock", function()
		local current = get()
		assert(current and current.enabled and current.baselineHash == config.baselineHash and current.target == config.target
			and current.revision == config.revision and current.league == config.league and current.targetValue == config.targetValue and current.hour == config.hour and current.protectionFile == config.protectionFile, "Daily sync settings changed during the refresh")
		if not force and current.day == day then return "Already synced today." end
		local original = assert(read(current.target), "Target filter is missing")
		local before = sha(original)
		assert(before == current.current or before == current.pending, "Target was edited outside PoB. Review and re-enable sync to adopt your edits.")
		local baseline = assert(read(current.baseline), "Baseline filter is missing")
		assert(sha(baseline) == current.baselineHash, "Baseline checksum changed")
		local candidate, count, changes, skipped = validate(baseline, bodies, false, current.targetValue, current.protections)
		if candidate ~= original then
			local backup = current.target .. ".before-pob-sync-" .. before .. ".bak"
			if not read(backup) then put(backup, original) end
			current.backup = before
			assert(read(backup) == original and read(current.target) == original, "Backup or target changed during sync")
			current.current, current.pending = before, sha(candidate)
			save(current)
			assert(read(current.target) == original, "Target changed before replacement")
			put(current.target, candidate)
		end
		assert(read(current.target) == candidate, "Installed filter verification failed")
		current.current, current.pending, current.day = sha(candidate), nil, day
		current.summary = string.format("%s: %d stack adjustments from the baseline. Protected drops verified.", nowText(now), count)
		current.lastSuccess = now
		current.review = {changes=changes, skipped=skipped, checkedAt=now, backup=current.backup}
		current.history = current.history or {}
		table.insert(current.history, 1, {checkedAt=now, adjustments=count, backup=current.backup})
		if #current.history > 30 then table.remove(current.history) end
		save(current)
		return current.summary
	end)
end

function M.tick(now, force)
	if M.busy then
		if now > M.deadline then
			M.busy = nil
			M.status = "Daily sync timed out. The existing filter was kept."
		end
		return
	end
	if not force and (now < nextPoll or now < retryAt) then return end
	nextPoll = now + 60
	local ok, config = pcall(get)
	if not ok then M.status = tostring(config); return end
	if not config or not config.enabled or config.paused then return end
	if launch.noSSL then M.status = "Sync skipped: enable HTTPS certificate verification in PoB."; return end
	local day = os.date("%Y-%m-%d", now)
	if not force and (config.day == day or tonumber(os.date("%H", now)) < (config.hour or 9)) then
		M.status = config.summary or M.status
		return
	end
	if not force then retryAt = now + 1800 end
	local job, bodies = {}, {}
	M.busy, M.deadline = job, now + 180
	local function finish(success, message)
		M.busy = nil
		M.status = success and message or ("Sync skipped: " .. tostring(message))
		if ConPrintf then ConPrintf("%s", M.status) end
	end
	local function fetch(index)
		local category = market.categories[index]
		if not category then finish(pcall(publish, config, bodies, day, force, now)); return end
		M.status = "Fetching " .. config.league .. " prices: " .. category
		local url = market.endpoint .. "exchange/current/overview?league=" .. urlEncode(config.league) .. "&type=" .. category
		launch:DownloadPage(url, function(response, err)
			if M.busy ~= job then return end
			if err then finish(false, category .. ": " .. err); return end
			local current, data = pcall(M.fresh, response, os.time())
			if not current then finish(false, category .. ": " .. tostring(data)); return end
			bodies[index] = data
			fetch(index + 1)
		end, {timeout=20,header="Accept: application/json\r\nCache-Control: no-cache"})
	end
	fetch(1)
end

return M
