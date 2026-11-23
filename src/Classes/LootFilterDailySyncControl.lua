local sync = require("Modules.LootFilterDailySync")
local background = require("Modules.LootFilterBackgroundTask")
local ui = require("Modules.PlanningUI")
local market = require("Modules.LootFilterEconomy")
local json = require("dkjson")
local M = {}

local function editPickupPolicy(width, target, policy, save)
	local controls = {}
	ui.label(controls,"campaignLabel",16,16,"Campaign chaos per stack",14)
	ui.label(controls,"mapsLabel",width/2+4,16,"Maps chaos per stack",14)
	local function targetField(key,x)
		controls[key] = new("EditControl"):EditControl(ui.anchor,{x,38,width/2-32,26},
			policy[key] and tostring(policy[key]) or "", "Use default target", nil, 10)
	end
	targetField("campaign",16)
	targetField("maps",width/2+4)
	ui.description(controls,"capsLabel",16,80,width-32,48,{
		"Optional item caps allow tightening after three earlier liquid daily quotes.",
		"Enter exact commodity names and their highest hide cutoff, for example: " .. '{"Orb of Alteration": 6}',
	},14)
	controls.caps = new("EditControl"):EditControl(ui.anchor,{16,134,width-32,122},
		next(policy.caps or {}) and json.encode(policy.caps,{indent=true}) or "{}",nil,nil,24000,nil,18)
	controls.apply = new("ButtonControl"):ButtonControl(ui.anchor,{16,274,180,28},"Use with next update",function()
		local passed, checked = pcall(function()
			local caps, nextIndex, why = json.decode(controls.caps.buf)
			assert(type(caps) == "table" and not controls.caps.buf:sub(nextIndex):find("%S"), why or "Enter a JSON object of item caps")
			return market.pickupPolicy(target, {
				campaign=controls.campaign.buf ~= "" and (tonumber(controls.campaign.buf) or -1) or nil,
				maps=controls.maps.buf ~= "" and (tonumber(controls.maps.buf) or -1) or nil,
				caps=caps,
			})
		end)
		if not passed then main:OpenMessagePopup("Pickup policy",ui.errorText(checked)); return end
		main:ClosePopup()
		save(checked)
	end)
	controls.cancel = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,274,120,28},"Cancel",function() main:ClosePopup() end)
	ui.style(controls)
	main:OpenPopup(width,320,"Pickup policy",controls,nil,nil,"cancel")
end

function M.Open(profileId, profileName)
	profileId, profileName = profileId or "default", profileName or "Default"
	local ok, config = pcall(sync.configuration,profileId)
	if not ok then main:OpenMessagePopup("Daily filter sync", ui.errorText(config)); return end
	config = config or {}
	local pickupPolicy = config.pickupPolicy or {}
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
		local hour, minute = c.time.buf:match("^%s*(%d%d?):(%d%d)%s*$")
		return {profileId=profileId,hour=tonumber(hour) or -1,minute=tonumber(minute) or -1,intervalDays=tonumber(c.intervalDays.buf) or -1,
			targetValue=tonumber(c.targetValue.buf) or -1,protectionFile=c.protectionFile.buf,pickupPolicy=pickupPolicy}
	end
	local function attempt(action)
		local passed, err = pcall(action)
		if not passed then main:OpenMessagePopup("Daily filter sync", ui.errorText(err)); return end
		main:ClosePopup()
		M.Open(profileId,profileName)
	end
	local function browse(key, y, x, options)
		c[key.."Browse"] = new("ButtonControl"):ButtonControl(ui.anchor,{x,y,82,26},"Browse",function()
			local documents = GetUserPath()
			local initial = c[key].buf ~= "" and c[key].buf or documents and (documents.."/My Games/Path of Exile/") or main.userPath
			require("Classes.LootFilterFileBrowser").Open(initial,function(path) c[key]:SetText(path) end,options)
		end)
	end
	field("target", 24, "Live Path of Exile 1 .filter file", config.target or "", 16, width-254)
	browse("target",44,width-230)
	c.detectTarget = new("ButtonControl"):ButtonControl(ui.anchor,{width-142,44,126,26},"Use PoE selection",function()
		local documents = GetUserPath()
		if not documents then main:OpenMessagePopup("Find PoE filter", "The Windows Documents folder is unavailable."); return end
		local passed, result = pcall(sync.selectedLocalFilter, documents.."/My Games/Path of Exile")
		if not passed then main:OpenMessagePopup("Find PoE filter", ui.errorText(result)); return end
		c.target:SetText(result)
	end)
	c.detectTarget.enabled = function() return not sync.busy end
	field("baseline", 82, "Fixed baseline .filter file", config.baseline or "", 16, width-128)
	browse("baseline",102,width-98)
	field("league", 140, "PoE 1 PC trade league", config.league or "Covens", 16, width-166)
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
	field("time", 198, "Daily time (local, HH:MM)", string.format("%02d:%02d", config.hour or 9, config.minute or 0), 16, 195)
	field("targetValue", 198, "Chaos per stack", tostring(config.targetValue or 1), 228, 160)
	field("intervalDays", 198, "Repeat every (days)", tostring(config.intervalDays or 1), 404, 150)
	field("protectionFile", 250, "Protected samples JSON", config.protectionFile or "", 16, width-128)
	browse("protectionFile",270,width-98,{title="Choose protected samples",itemLabel="JSON",accept=function(name) return name:lower():match("%.json$") end})
	ui.description(c,"help",16,306,width-32,38,{"Profile: "..profileName, "PoB keeps a fixed copy of the baseline."},14)
	c.status = new("LabelControl"):LabelControl(ui.anchor,{16,350,width-32,16},"",14)
	local cachedAt, cachedStatus
	c.status.label = function()
		local now = os.time()
		if cachedAt ~= now then
			cachedAt = now
			local passed, value = pcall(sync.profileStatus,profileId)
			cachedStatus = passed and value or ui.errorText(value)
		end
		return ui.fit(cachedStatus, width-32, 14)
	end
	button("enable",16,"Enable / update",function() attempt(function() sync.configure(c.target.buf,c.baseline.buf,c.league.buf,options()) end) end)
	button("run",16+step*1,"Sync now",function() sync.tick(os.time(),true,false,profileId) end)
	button("disable",16+step*2,"Disable",function() attempt(function() sync.disable(profileId) end) end)
	button("pause",16+step*3,config.paused and "Resume" or "Pause",function() attempt(function() sync.pause(not config.paused,profileId) end) end)
	button("rollback",16+step*4,"Restore backup",function()
		main:OpenConfirmPopup("Restore filter backup", "Restore the previous filter and pause daily sync?", "Restore", function()
			attempt(function() sync.rollback(profileId) end)
		end)
	end)
	button("review",16,"Last review",function()
		local saved = sync.configuration(profileId)
		local review = saved and saved.review
		if not review then main:OpenMessagePopup("Daily filter sync", "Sync once to get a review."); return end
		local entries = {{
			id="summary", label="Sync status", category="Run",
			details={saved.summary, "Next eligible run: " .. (sync.nextEligible(saved,os.time()) or "Paused or disabled"),
				review.backup and ("Backup: " .. saved.target .. ".before-pob-sync-" .. review.backup .. ".bak") or "No replacement backup yet."},
		}}
		for i, change in ipairs(review.changes or {}) do
			local scope = change.scope == "campaign" and " in campaign areas" or change.maps and " in maps" or ""
			local details = {
				string.format("Hide up to %d → %d%s", change.old, change.cutoff, scope),
				string.format("%.4g chaos used | %.0f %s",change.price,change.volume,change.liquidityUnit or "chaos quoted volume"),
				string.format("Latest %.4g chaos | %d earlier daily quotes",change.currentPrice or change.price,change.observations or 0),
			}
			local samples = change.samples or (change.sample and {change.sample}) or {}
			for _, sample in ipairs(samples) do
				local area = (sample.area or 83) >= 68 and "Maps" or "Campaign"
				details[#details+1] = string.format("%s, %d as %s: %s%s", area, sample.count, sample.class,
					sample.before and (sample.before.." → "..sample.action) or sample.action,
					sample.line and (" at line "..sample.line) or "")
			end
			if #samples == 0 then details[#details+1] = "Sample result unavailable." end
			entries[#entries+1] = {id="change-"..i,label=change.name,category="Changed",details=details}
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
	button("externalEdits",16+step*2,"External edits",function()
		local passed,before,after = pcall(sync.externalDiff,profileId)
		if not passed then main:OpenMessagePopup("External filter edits", ui.errorText(before)); return end
		require("Classes.LootFilterDiffControl").Open(before,after,true)
	end,432)
	c.externalEdits.enabled = function() return config.target ~= nil and not sync.busy end
	button("copyReport",16+step*3,"Copy diagnostics",function()
		local passed, report = pcall(sync.diagnosticReport, os.time(), profileId)
		if not passed then main:OpenMessagePopup("Sync diagnostics", ui.errorText(report)); return end
		Copy(report)
		main:OpenMessagePopup("Sync diagnostics", "Copied the daily sync report.")
	end,432)
	button("close",width-buttonWidth-16,"Close",function() main:ClosePopup() end,432)
	c.enable.enabled = function() return not sync.busy end
	c.disable.enabled = function() return config.enabled and not sync.busy end
	c.run.enabled = function() return config.enabled and not config.paused and not sync.busy end
	c.pause.enabled = function() return config.enabled and not sync.busy end
	local lastStatus, cached = sync.status, config
	c.rollback.enabled = function()
		if not sync.busy and lastStatus ~= sync.status then
			lastStatus = sync.status
			local passed, saved = pcall(sync.configuration,profileId)
			if passed and saved then cached = saved end
		end
		return not sync.busy and cached.backup ~= nil
	end
	local function backgroundLabel()
		return config.backgroundEnabled and "Disable background sync" or "Enable background sync"
	end
	c.background = new("ButtonControl"):ButtonControl(ui.anchor,{16,470,180,28},backgroundLabel(),function()
		local owner = main.popups[1]
		local passed, err = pcall(background.change, not config.backgroundEnabled, function(ok, why)
			if main.popups[1] ~= owner then return end
			if not ok then main:OpenMessagePopup("Background filter sync", ui.errorText(why)); return end
			main:ClosePopup()
			M.Open(profileId,profileName)
		end,profileId)
		if not passed then main:OpenMessagePopup("Background filter sync", ui.errorText(err)) end
	end)
	c.background.enabled = function() return (config.enabled or config.backgroundEnabled) and not background.busy and not sync.busy end
	local notifyLabel = config.backgroundNotifications and "Disable notifications" or "Enable notifications"
	c.backgroundNotify = new("ButtonControl"):ButtonControl(ui.anchor,{202,470,180,28},notifyLabel,function()
		attempt(function() sync.setBackgroundNotifications(not config.backgroundNotifications,profileId) end)
	end)
	c.backgroundNotify.enabled = function() return config.backgroundEnabled and not background.busy end
	c.pickupPolicy = new("ButtonControl"):ButtonControl(ui.anchor,{388,470,135,28},"Pickup policy",function()
		editPickupPolicy(width,tonumber(c.targetValue.buf) or -1,pickupPolicy,function(value) pickupPolicy=value end)
	end)
	c.pickupPolicy.enabled = function() return not sync.busy end
	c.profiles = new("ButtonControl"):ButtonControl(ui.anchor,{width-126,470,110,28},"Profiles",function()
		local passed, profiles = pcall(sync.profiles)
		if not passed then main:OpenMessagePopup("Sync profiles",ui.errorText(profiles)); return end
		local entries = {}
		for _, entry in ipairs(profiles) do
			entries[#entries+1] = {id=entry.id,label=entry.name,
				details={entry.id == profileId and "Open profile" or "Select this sync profile"}}
		end
		entries[#entries+1] = {id="new",label="Create profile",details={"Use a separate filter destination and schedule."}}
		require("Classes.PlanningBrowserControl").Open("Sync profiles",entries,{action="Open profile",closeOnChoose=false,
			choose=function(entry)
				main:ClosePopup()
				if entry.id ~= "new" then
					main:ClosePopup()
					M.Open(entry.id,entry.label)
					return
				end
				local controls = {}
				ui.label(controls,"nameLabel",16,16,"Profile name",14)
				controls.name = new("EditControl"):EditControl(ui.anchor,{16,38,328,28},"",nil,nil,80)
				controls.create = new("ButtonControl"):ButtonControl(ui.anchor,{16,80,125,28},"Create",function()
					local name = controls.name.buf:match("^%s*(.-)%s*$")
					local ok, id = pcall(sync.createProfile,name)
					if not ok then main:OpenMessagePopup("Sync profiles",ui.errorText(id)); return end
					main:ClosePopup()
					main:ClosePopup()
					M.Open(id,name)
				end)
				controls.cancel = new("ButtonControl"):ButtonControl(ui.anchor,{218,80,126,28},"Cancel",function() main:ClosePopup() end)
				ui.style(controls)
				main:OpenPopup(360,126,"New sync profile",controls,nil,nil,"cancel")
			end})
	end)
	ui.description(c,"backgroundHelp",16,504,width-210,25,{"Background updates run while you are signed in to Windows."},13)
	c.account = new("ButtonControl"):ButtonControl(ui.anchor,{width-184,504,168,26},"Publish to account",function()
		require("Classes.LootFilterSyncAccountControl").Open(profileId)
	end)
	c.account.enabled = function() return not sync.busy end
	ui.style(c)
	main:OpenPopup(width, 545, "Daily filter sync", c, nil, nil, "close")
end

return M
