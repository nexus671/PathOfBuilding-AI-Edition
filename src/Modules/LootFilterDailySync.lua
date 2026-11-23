local json = require("dkjson")
local sha = require("sha1")
local market = require("Modules.LootFilterEconomy")
local validate = require("Modules.LootFilterSyncValidation")
local M = { status = "Daily sync is disabled." }
local volumeLimit = 2 * 1024 * 1024
local nextPoll, retryAt, rateLimitUntil = 0, 0, 0
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


-- The AI bridge gets a bounded, path-free view. File names, local settings,
-- protected sample definitions and transport errors stay on the desktop.
local publicCache
function M.publicStatus(now)
	if publicCache and publicCache.at == now and publicCache.status == M.status then return publicCache.value end
	local ok, config = pcall(get)
	if not ok then return {configured=false,state="settings_error"} end
	if not config then return {configured=false,state="unconfigured"} end
	local review = type(config.review)=="table" and config.review or {}
	local output = {
		configured=true,
		state=M.busy and "running" or not config.enabled and "disabled" or config.paused and "paused" or "enabled",
		league=type(config.league)=="string" and config.league:match("^[%w%s_-]+$") and config.league:sub(1,80) or nil,
		lastSuccess=type(config.lastSuccess)=="number" and config.lastSuccess or nil,
		latestChanges={},
	}
	if output.state == "enabled" and (M.status:match("^Sync skipped:") or M.status:match("^Daily sync timed out")) then
		output.state = "error"
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
	publicCache = {at=now, status=M.status, value=output}
	return output
end

local function filterPath(path)
	assert(type(path) == "string" and #path <= 1000 and path:match("^%a:[/\\]") and not path:find("[%c]") and path:lower():match("%.filter$"),
		"Enter an absolute Windows .filter path")
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

function M.externalDiff()
	local config = assert(get(), "No saved sync setup")
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

local function prepare(target, baselineFile, league, options)
	options = options or {}
	local targetValue = options.targetValue or 1
	local hour = options.hour or 9
	assert(type(hour) == "number" and hour >= 0 and hour <= 23 and hour == math.floor(hour), "Enter an hour from 0 to 23")
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
	validate(baseline, {}, true, targetValue, protections)
	validate(original, {}, true, targetValue, protections)
	local a, b = market.sectionBounds(original), market.sectionBounds(baseline)
	assert(a and b and original:sub(1,a-1) == baseline:sub(1,b-1), "Baseline and target must share the protected rule prefix")
	local key = sha(baseline)
	return {
		enabled=true, target=target, baseline=main.userPath.."LootFilterBaseline-"..key..".filter",
		baselineHash=key, current=sha(original), revision=sha(tostring({})..tostring(os.time())),
		league=league, hour=hour, targetValue=targetValue, protections=protections, protectionFile=options.protectionFile,
	}, original, baseline
end

function M.configure(target, baselineFile, league, options)
	assert(not M.busy, "Wait for the current sync to finish")
	local config = platform().lock(settingsPath() .. ".lock", function()
		local nextConfig, original, baseline = prepare(target, baselineFile, league, options)
		if not read(nextConfig.baseline) then put(nextConfig.baseline, baseline) end
		assert(read(nextConfig.baseline) == baseline, "Stored baseline does not match")
		keepExpected(original)
		save(nextConfig)
		return nextConfig
	end)
	nextPoll, retryAt = 0, 0
	M.status = string.format("Daily sync enabled at %02d:00 local time while PoB is open.", config.hour)
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
		keepExpected(backup)
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

function M.fresh(response, now)
	local header = headers(response)
	local timestamp = assert(httpDate(header.date), "Exchange response has no valid freshness date")
	local age = header.age and tonumber(header.age:match("^%d+$")) or (not header.age and 0)
	assert(age, "Exchange response has an invalid Age header")
	local resident = math.max(now - timestamp, age)
	assert((header["cf-cache-status"] or ""):lower() ~= "stale" and timestamp <= now + 300
		and resident <= 3600, "Exchange snapshot is stale")
	local tag = header.etag
	if tag and (#tag > 160 or tag:find("[%c]") or not (tag:match('^"[^"]*"$') or tag:match('^W/"[^"]*"$'))) then tag = nil end
	return response.body, resident, tag
end

local function publish(config, bodies, ages, day, force, now)
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
		local candidate, count, changes, skipped, snapshots = validate(
			baseline, bodies, false, current.targetValue, current.protections, current.priceHistory, day, now)
		current.priceHistory = snapshots
		keepExpected(candidate)
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
		current.review = {changes=changes, skipped=skipped, checkedAt=now, backup=current.backup, ages=ages}
		current.history = current.history or {}
		table.insert(current.history, 1, {checkedAt=now, adjustments=count, backup=current.backup, oldest=math.max(unpack(ages))})
		if #current.history > 30 then table.remove(current.history) end
		save(current)
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

local function fetchPrices(config, baseline, now, complete)
	local categories = market.feedCategories(baseline)
	local job, bodies, ages, observedAt = {}, {}, {}, {}
	M.busy, M.deadline = job, now + 300
	local function finish(success, message)
		M.busy = nil
		M.status = success and message or ("Sync skipped: " .. tostring(message))
		if ConPrintf then ConPrintf("%s", M.status) end
	end
	local function fetch(index, attempt)
		local category = categories[index]
		if not category then
			local finishedAt = os.time()
			for id, age in ipairs(ages) do
				ages[id] = age + math.max(0, finishedAt - observedAt[id])
				if ages[id] > 3600 then finish(false, "An exchange snapshot expired before the refresh finished."); return end
			end
			finish(pcall(complete, bodies, ages))
			return
		end
		M.status = "Fetching " .. config.league .. " prices: " .. category
		local url = market.endpoint .. "exchange/current/overview?league=" .. urlEncode(config.league) .. "&type=" .. category
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
				bodies[index], ages[index], observedAt[index] = cached.body, time-cached.sourceAt, time
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
				finish(false, category .. ": " .. err)
				return
			end
			local fresh, data, age, tag = pcall(M.fresh, response, time)
			if not fresh then finish(false, category .. ": " .. tostring(data)); return end
			local valid, why = pcall(market.quotes, data, category)
			if not valid then finish(false, category .. ": " .. tostring(why)); return end
			storeFeed(url,{body=data,tag=tag,sourceAt=time-age,checkedAt=time})
			bodies[index], ages[index], observedAt[index] = data, age, time
			fetch(index + 1, 1)
		end, {timeout=20,maxBytes=2*1024*1024,header=requestHeaders})
	end
	fetch(1, 1)
end

function M.tick(now, force)
	if M.busy then
		if now > M.deadline then
			M.busy = nil
			M.status = "Daily sync timed out. The existing filter was kept."
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
	local ready, baseline = pcall(function()
		local current = sha(assert(read(filterPath(config.target)), "Target filter is missing"))
		assert(current == config.current or current == config.pending, "Target was edited outside PoB. Compare External edits before re-enabling.")
		local raw = assert(read(config.baseline), "Baseline filter is missing")
		assert(sha(raw) == config.baselineHash, "Baseline checksum changed")
		return raw
	end)
	if not ready then M.status = "Sync skipped: " .. tostring(baseline); return end
	fetchPrices(config, baseline, now, function(bodies, ages)
		return publish(config, bodies, ages, day, force, now)
	end)
end

function M.preview(target, baselineFile, league, options, callback)
	assert(not M.busy, "Wait for the current sync to finish")
	assert(not launch.noSSL, "Enable HTTPS certificate verification in PoB")
	assert(os.time() >= rateLimitUntil, "Wait before contacting the rate-limited exchange again")
	local config, original, baseline = prepare(target, baselineFile, league, options)
	local now = os.time()
	fetchPrices(config, baseline, now, function(bodies)
		local candidate = validate(baseline, bodies, false, config.targetValue, config.protections)
		callback(original, candidate)
		return "Preview complete. Review the proposed filter before enabling sync."
	end)
end

return M
