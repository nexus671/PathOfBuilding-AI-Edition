local economy = require("Modules.LootFilterEconomy")
local ui = require("Modules.PlanningUI")
local json = require("dkjson")
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
		"Review tagged currency stack rules against PC exchange prices. The cutoff only moves down when current prices justify showing smaller stacks.",
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
		if not target or target <= 0 or target > 1000 or target ~= target then
			status("Enter a stack value between 0 and 1,000 chaos.")
			return
		end
		local requested = c.league.buf:match("^%s*(.-)%s*$")
		local function active() return main.popups[1] == popup end
		local function request(path, callback)
			launch:DownloadPage(economy.endpoint .. path, function(response, err)
				if not active() then return end
				callback(not err and response and response.body or nil)
			end)
		end
		busy = true
		status("Checking trade leagues...")
		request("leagues", function(body)
			local leagues = body and json.decode(body)
			local league
			for index, entry in ipairs(type(leagues) == "table" and leagues or {}) do
				if type(entry) == "table" and type(entry.id) == "string"
					and (entry.id == requested or requested == "" and index == 1) then league = entry.id; break end
			end
			if not league then busy = false; status("Could not resolve the league. Use an active poe.ninja league ID."); return end
			local quotes, failed = {}, {}
			local categories = economy.feedCategories(raw)
			local function fetch(index)
				local category = categories[index]
				if category then
					status("Fetching " .. league .. " prices (" .. index .. "/" .. #categories .. ")...")
					request("exchange/current/overview?league=" .. urlEncode(league) .. "&type=" .. category, function(data)
						local ok, result = pcall(economy.quotes, data)
						if ok then economy.merge(quotes, result, category) else failed[#failed + 1] = category end
						fetch(index + 1)
					end)
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
					entries[#entries + 1] = {id = tostring(i), label = change.name, details = {
						"Hide up to " .. change.old .. " → " .. change.cutoff .. (change.maps and " in maps" or ""),
						string.format("%.4g chaos each | %.0f chaos quoted volume", change.price, change.volume),
					}}
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
