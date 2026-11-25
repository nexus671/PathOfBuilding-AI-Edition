local economy = require("Modules.LootFilterEconomy")
local sync = require("Modules.LootFilterDailySync")
local ui = require("Modules.PlanningUI")
local M = {}

function M.Open(profile, raw, export)
	if not economy.supports(raw) then
		main:OpenMessagePopup("Loot filter economy review", "Import a filter with a tagged economy section first.")
		return
	end
	local c = {}
	local width = math.min(640, main.screenW - 40)
	local popup, busy
	local function status(message)
		c.status.list = ui.rows({message}, width - 64, 14)
	end
	local function button(key, x, label, action)
		c[key] = new("ButtonControl"):ButtonControl(ui.anchor, {x, 234, 136, 28}, label, action)
	end
	ui.description(c, "info", 16, 24, width - 32, 52, {
		"Review managed currency, card, map, and exact gem hides against PC trade prices. The cutoff only moves down when current prices justify showing smaller stacks.",
	}, 14)
	ui.label(c, "leagueLabel", 16, 90, "League ID", 14)
	ui.label(c, "targetLabel", 246, 90, "Chaos per stack", 14)
	c.league = new("EditControl"):EditControl(ui.anchor, {16, 110, 210, 26}, "", "Current trade league", nil, 80)
	c.target = new("EditControl"):EditControl(ui.anchor, {246, 110, 128, 26}, "1", nil, nil, 10)
	c.status = new("TextListControl"):TextListControl(ui.anchor, {16, 150, width - 32, 72}, nil, {})
	status("Fetch prices to review a new export.")
	button("close", width - 152, "Close", function() main:ClosePopup() end)
	button("fetch", 16, "Fetch prices", function()
		local target = tonumber(c.target.buf)
		if busy then return end
		if not economy.endpoint then status(economy.endpointError); return end
		if launch.noSSL then status("Enable HTTPS certificate verification in PoB."); return end
		if not target or target <= 0 or target > 1000 or target ~= target then
			status("Enter a stack value between 0 and 1,000 chaos.")
			return
		end
		local validFeedList, categories, gemRequests = pcall(economy.feedCategories, raw)
		if not validFeedList then status(ui.errorText(categories)); return end
		local requested = c.league.buf:match("^%s*(.-)%s*$")
		local function active() return main.popups[1] == popup end
		local function cooldown(wait)
			busy = false
			status(string.format("Market provider cooldown. Try again in %d minutes.",math.ceil(wait/60)))
		end
		local function request(path, callback, maxBytes)
			local wait = sync.providerWait(os.time())
			if wait>0 then cooldown(wait); return end
			launch:DownloadPage(economy.endpoint .. path, function(response, err)
				local code = err and tonumber(err:match("^Response code: (%d+)$"))
				local delay = sync.noteProviderLimit(response,code,os.time())
				if not active() then return end
				if delay then cooldown(delay); return end
				callback(not err and response or nil)
			end, {followRedirects=false,timeout=20,maxBytes=maxBytes or 65536,header="Accept: application/json"})
		end
		busy = true
		status("Checking trade leagues...")
		request("leagues", function(response)
			local valid, leagues, seen = pcall(function()
				return economy.tradeLeagues(sync.fresh(response,os.time()))
			end)
			local league = valid and (requested=="" and leagues[1].id or seen[requested] and requested)
			if not league then busy = false; status("Could not resolve the league. Use an active poe.ninja league ID."); return end
			local quotes, failed = {}, {}
			local function fetch(index)
				local category = categories[index]
				if category then
					status("Fetching " .. league .. " prices (" .. index .. "/" .. #categories .. ")...")
					request(economy.feedPath(league, category), function(response)
						local fresh, data = pcall(sync.fresh, response, os.time())
						local ok, result = false
						if fresh then ok, result = pcall(economy.quotes, data, category, gemRequests) end
						if ok then economy.merge(quotes, result, category) else failed[#failed + 1] = category end
						fetch(index + 1)
					end, economy.maxFeedBytes(category))
					return
				end
				busy = false
				local ok, candidate, changes = pcall(economy.review, raw, quotes, target)
				if not ok then status(ui.errorText(candidate)); return end
				if #changes > 0 then
					for _, diagnostic in ipairs(require("Modules.LootFilterParser").parse(candidate).diagnostics) do
						if diagnostic.error then status("Candidate has a filter error at line " .. diagnostic.line .. ". Export blocked."); return end
					end
				end
				local dataStatus = #failed == 0 and "All requested categories loaded." or "Unavailable: " .. table.concat(failed, ", ")
				local entries = {{id = "summary", label = league .. " stack review", details = {
					"Price check: " .. os.date("!%Y-%m-%d %H:%M UTC"),
					#changes .. " adjustments at " .. target .. " chaos per stack.",
					dataStatus,
					"Missing or thin markets keep existing rules. Later filter rules can still affect visibility.",
				}}}
				for i, change in ipairs(changes) do
					local details = {
						change.uniqueBase and "Unidentified unique base stays visible"
							or "Hide up to " .. change.old .. " → " .. change.cutoff .. (change.maps and " in maps" or ""),
						string.format("%.4g chaos each | %.0f %s",change.price,change.volume,change.liquidityUnit or "chaos quoted volume"),
						change.gemLevel and string.format("Level %d, %d%% quality, %s",change.gemLevel,change.gemQuality,
							change.corrupted and "corrupted" or "uncorrupted") or nil,
					}
					if change.reward then details[#details+1] = economy.rewardDescription(change.reward) end
					if change.exampleUnique then details[#details+1] = "Highest supported variant: "..change.exampleUnique end
					local priceId = economy.evidencePriceId(change.priceId)
					if priceId then details[#details+1] = "Price ID · "..priceId end
					entries[#entries + 1] = {id = tostring(i), label = change.name, details = details}
				end
				status("Review complete.")
				require("Classes.PlanningBrowserControl").Open("Review exchange prices", entries, {
					action = "Export candidate",
					canChoose = function() return #changes > 0 end,
					choose = function()
						main:ClosePopup()
						local output = copyTable(profile)
						output.id = "economy-review"
						output.template = candidate
						export(output, candidate)
					end,
				})
			end
			fetch(1)
		end)
	end)
	c.fetch.enabled = function() return not busy end
	ui.style(c)
	popup = main:OpenPopup(width, 284, "Loot filter economy review", c, nil, nil, "close")
end

return M
