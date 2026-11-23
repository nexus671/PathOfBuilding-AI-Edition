local sync = require("Modules.LootFilterDailySync")
local ui = require("Modules.PlanningUI")
local market = require("Modules.LootFilterEconomy")
local json = require("dkjson")
local M = {}

function M.Open()
	local ok, config = pcall(sync.configuration)
	if not ok then main:OpenMessagePopup("Daily filter sync", ui.errorText(config)); return end
	config = config or {}
	local width = math.min(720, main.screenW - 40)
	local c = {}
	local buttonWidth = math.floor((width - 56) / 5)
	local step = buttonWidth + 6
	local function button(key, x, label, action, y)
		c[key] = new("ButtonControl"):ButtonControl(ui.anchor,{x, y or 394, buttonWidth, 28},label,action)
	end
	local function field(key, y, label, value, x, fieldWidth)
		x, fieldWidth = x or 16, fieldWidth or width-32
		ui.label(c, key.."Label", x, y, label, 14)
		c[key] = new("EditControl"):EditControl(ui.anchor,{x, y+20, fieldWidth, 26},value,nil,nil,1000)
	end
	local function options()
		return {hour=tonumber(c.hour.buf) or -1,targetValue=tonumber(c.targetValue.buf) or -1,protectionFile=c.protectionFile.buf}
	end
	local function attempt(action)
		local passed, err = pcall(action)
		if not passed then main:OpenMessagePopup("Daily filter sync", ui.errorText(err)); return end
		main:ClosePopup()
		M.Open()
	end
	field("target", 24, "Live Path of Exile .filter file", config.target or "")
	field("baseline", 82, "Fixed baseline .filter file", config.baseline or "")
	field("league", 140, "poe.ninja league ID", config.league or "Covens", 16, width-166)
	local loadingLeagues = false
	c.chooseLeague = new("ButtonControl"):ButtonControl(ui.anchor,{width-142,160,126,26},"Choose league",function()
		if launch.noSSL then main:OpenMessagePopup("Choose league", "Enable HTTPS certificate verification in PoB."); return end
		local owner = main.popups[1]
		loadingLeagues = true
		launch:DownloadPage(market.endpoint.."leagues",function(response, err)
			loadingLeagues = false
			if main.popups[1] ~= owner then return end
			local result = not err and response and type(response.body) == "string" and #response.body <= 65536 and json.decode(response.body)
			local entries = {}
			for _, league in ipairs(type(result) == "table" and result or {}) do
				if type(league) == "table" and type(league.id) == "string" and type(league.name) == "string"
					and #league.id <= 80 and league.id:match("^[%w%s_-]+$") and #league.name <= 160 then
					entries[#entries+1] = {id=league.id,label=league.name,details={league.id,"PC trade economy"}}
				end
			end
			if #entries == 0 then main:OpenMessagePopup("Choose league", "No PC trade leagues returned. Try again or enter the ID."); return end
			require("Classes.PlanningBrowserControl").Open("Choose PC trade league",entries,{
				action="Use league",
				choose=function(entry) c.league:SetText(entry.id); main:ClosePopup() end,
			})
		end,{timeout=15})
	end)
	c.chooseLeague.enabled = function() return not loadingLeagues and not sync.busy end
	field("hour", 198, "Daily hour (local, 0–23)", tostring(config.hour or 9), 16, 195)
	field("targetValue", 198, "Chaos per stack", tostring(config.targetValue or 1), 236, 160)
	field("protectionFile", 250, "Protected samples JSON (optional for tiered test)", config.protectionFile or "")
	ui.description(c,"help",16,306,width-32,38,{"PoB checks for a due sync while open and keeps a copy of the baseline."},14)
	c.status = new("LabelControl"):LabelControl(ui.anchor,{16,350,width-32,16},"",14)
	c.status.label = function() return ui.fit(sync.status, width-32, 14) end
	button("enable",16,"Enable / update",function() attempt(function() sync.configure(c.target.buf,c.baseline.buf,c.league.buf,options()) end) end)
	button("run",16+step*1,"Sync now",function() sync.tick(os.time(),true) end)
	button("disable",16+step*2,"Disable",function() attempt(sync.disable) end)
	button("pause",16+step*3,config.paused and "Resume" or "Pause",function() attempt(function() sync.pause(not config.paused) end) end)
	button("rollback",16+step*4,"Restore backup",function()
		main:OpenConfirmPopup("Restore filter backup", "Restore the previous filter and pause daily sync?", "Restore", function()
			attempt(sync.rollback)
		end)
	end)
	button("review",16,"Last review",function()
		local saved = sync.configuration()
		local review = saved and saved.review
		if not review then main:OpenMessagePopup("Daily filter sync", "Sync once to get a review."); return end
		local entries = {{
			id="summary", label="Sync status", category="Run",
			details={saved.summary, "Next eligible run: " .. (sync.nextEligible(saved,os.time()) or "Paused or disabled"),
				review.backup and ("Backup: " .. saved.target .. ".before-pob-sync-" .. review.backup .. ".bak") or "No replacement backup yet."},
		}}
		for i, change in ipairs(review.changes or {}) do
			entries[#entries+1] = {id="change-"..i,label=change.name,category="Changed",details={
				string.format("Hide up to %d → %d%s", change.old, change.cutoff, change.maps and " in maps" or ""),
				string.format("%.4g chaos used | %.0f chaos quoted volume",change.price,change.volume),
				string.format("Latest %.4g chaos | %d earlier daily quotes",change.currentPrice or change.price,change.observations or 0),
				change.sample and string.format("Map sample: %d as %s → %s%s", change.sample.count,
					change.sample.class, change.sample.action, change.sample.line and " at line "..change.sample.line or "")
					or "Sample result unavailable.",
			}}
		end
		for i, item in ipairs(review.skipped or {}) do
			entries[#entries+1] = {id="skip-"..i,label=item.name,category="Unchanged",details={item.reason,"Hide up to "..item.old}}
		end
		for i, run in ipairs(saved.history or {}) do
			entries[#entries+1] = {id="run-"..i,label=os.date("%Y-%m-%d %H:%M",run.checkedAt),category="History",details={
				run.adjustments.." cutoff adjustments from the baseline.", "Protected drop checks passed.",
				run.oldest and string.format("Oldest response was %.0f minutes old",run.oldest/60) or "Response age was not recorded.",
			}}
		end
		require("Classes.PlanningBrowserControl").Open("Daily filter sync review", entries)
	end,432)
	button("preview",16+step,"Preview changes",function()
		local owner = main.popups[1]
		local passed, err = pcall(sync.preview,c.target.buf,c.baseline.buf,c.league.buf,options(),function(before, after)
			if main.popups[1] == owner then require("Classes.LootFilterDiffControl").Open(before,after,true) end
		end)
		if not passed then main:OpenMessagePopup("Daily filter sync", ui.errorText(err)) end
	end,432)
	c.preview.enabled = function() return not sync.busy end
	button("close",width-buttonWidth-16,"Close",function() main:ClosePopup() end,432)
	c.enable.enabled = function() return not sync.busy end
	c.disable.enabled = function() return config.enabled and not sync.busy end
	c.run.enabled = function() return config.enabled and not config.paused and not sync.busy end
	c.pause.enabled = function() return config.enabled and not sync.busy end
	local lastStatus, cached = sync.status, config
	c.rollback.enabled = function()
		if not sync.busy and lastStatus ~= sync.status then
			lastStatus = sync.status
			local passed, saved = pcall(sync.configuration)
			if passed and saved then cached = saved end
		end
		return not sync.busy and cached.backup ~= nil
	end
	ui.style(c)
	main:OpenPopup(width, 476, "Daily filter sync", c, nil, nil, "close")
end

return M
