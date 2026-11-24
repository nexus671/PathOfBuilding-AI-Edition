local sync = require("Modules.LootFilterDailySync")
local background = require("Modules.LootFilterBackgroundTask")
local ui = require("Modules.PlanningUI")
local market = require("Modules.LootFilterEconomy")
local appearance = require("Modules.LootFilterPriceAppearance")
local M = {}

local feedFailureDescriptions = {
	access_denied = "The price provider denied access.",
	rate_limited = "The price provider limited requests.",
	provider_unavailable = "The price provider was unavailable.",
	http_error = "The price provider returned an HTTP error.",
	redirect = "The price feed redirected the request.",
	transport_error = "PoB could not reach the price feed.",
	stale = "The price feed was too old to use.",
	invalid_response = "The response was invalid for this feed.",
	empty_response = "The feed returned no usable prices.",
	coverage_drop = "Too few liquid quotes. PoB kept the verified filter.",
	cooldown = "The provider cooldown exceeded this refresh window.",
	timeout = "The price refresh ran out of time.",
	league_unavailable = "The configured league is unavailable at the price provider.",
	source_changed = "The configured price source changed.",
}

local function attemptTime(timestamp)
	if type(timestamp)=="number" and timestamp>=0 and timestamp<=4102444800 then
		return os.date("%Y-%m-%d %H:%M",timestamp)
	end
end

local function showLastAttempt(profileId)
	local ok, config = pcall(sync.configuration,profileId)
	if not ok or not config then
		main:OpenMessagePopup("Last sync attempt","Could not read this sync profile.")
		return
	end
	local failure = type(config.lastFailure)=="table" and config.lastFailure
	local lastSuccess = attemptTime(config.lastSuccess)
	local details = {}
	if failure then
		local failedAt = attemptTime(failure.checkedAt)
		details[1] = failedAt and "Refresh failed on "..failedAt or "The latest refresh failed."
		local feed = sync.failedFeedEvidence(failure.failedFeed)
		if feed then
			local category = feed.category=="leagues" and "League list" or feed.category
			details[#details+1] = category.." price feed"..(feed.httpStatus and " (HTTP "..feed.httpStatus..")" or "")
			details[#details+1] = feedFailureDescriptions[feed.reason] or "The price feed check failed."
			if feed.reason=="coverage_drop" then
				details[#details+1] = string.format("Liquid quotes: %d available, %d recent median",feed.availableQuotes,feed.usualQuotes)
			end
			if feed.currentLeague then
				details[#details+1] = ui.fit("Current challenge league: "..feed.currentLeague.id, math.min(488, main.screenW-72), 14)
				local checked = attemptTime(feed.verifiedAt)
				if checked then details[#details+1] = "League list verified on "..checked end
			end
		elseif type(failure.message)=="string" then
			details[#details+1] = ui.fit(ui.errorText(failure.message),460,16)
		end
	elseif not lastSuccess then
		details[1] = "This profile has no completed sync attempt."
	end
	if lastSuccess then details[#details+1] = "Last verified refresh on "..lastSuccess end
	local width = math.min(520,main.screenW-40)
	local contentHeight = #details*22
	local controls = {}
	ui.description(controls,"message",16,18,width-32,contentHeight,details,14)
	controls.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,contentHeight+24,120,28},"Close",function()
		main:ClosePopup()
	end)
	ui.style(controls,{close=true})
	main:OpenPopup(width,contentHeight+68,"Last sync attempt",controls,nil,nil,"close")
end

local observedStyles = {
	{"MinimapIcon","Minimap marker"}, {"PlayEffect","Beam"},
	{"SetTextColor","Text color (RGBA)"}, {"SetBorderColor","Border color (RGBA)"},
	{"SetBackgroundColor","Background color (RGBA)"}, {"SetFontSize","Font size"},
	{"PlayAlertSound","Alert sound"}, {"PlayAlertSoundPositional","Positional alert sound"},
	{"CustomAlertSound","Custom alert sound"}, {"CustomAlertSoundOptional","Optional custom alert sound"},
	{"DisableDropSound","Drop sound disabled"}, {"EnableDropSound","Drop sound enabled"},
	{"DisableDropSoundIfAlertSound","Drop sound disabled with alert"}, {"EnableDropSoundIfAlertSound","Drop sound enabled with alert"},
}

local function describeObservedOutcome(details, label, result)
	details[#details+1] = label.." | "..result.action..(result.line and (" at line "..result.line) or "")
	if #(result.matches or {})>1 then
		local lines={}
		for index=1,math.min(#result.matches,20) do lines[#lines+1]=tostring(result.matches[index]) end
		details[#details+1] = "Matched lines in order: "..table.concat(lines,", ")..(#result.matches>20 and ", ..." or "")
	end
	if result.action=="Unknown" then
		local missing = require("Modules.LootFilterParser").safeMissingProperties(result.missingProperties)
		details[#details+1] = missing and ("Needs "..table.concat(missing,", ")..".") or "A filter rule or included file could not be verified."
	elseif result.action=="Show" or result.action=="Minimal" then
		for _,style in ipairs(observedStyles) do
			local values=(result.styles or {})[style[1]]
			if values then
				local value=table.concat(values," "):gsub("[%c%^]"," ")
				details[#details+1] = style[2]..(value~="" and (": "..value) or "")
			end
		end
	end
	for index,reason in ipairs(result.reasons or {}) do
		if index>3 then details[#details+1]="Additional filter warnings omitted.";break end
		details[#details+1] = tostring(reason):gsub("[%c%^]"," ")
	end
end

local function showObservedComparison(item,before,after,beforeLabel,afterLabel)
	local width=math.min(540,main.screenW-40)
	local details={string.format("%s, stack of %d, area level %d",item.BaseType,item.StackSize,item.AreaLevel)}
	if item.ItemLevel then details[#details+1]="Item level: "..item.ItemLevel end
	describeObservedOutcome(details,beforeLabel,before)
	describeObservedOutcome(details,afterLabel,after)
	local resultControls={}
	local visual=require("Modules.LootFilterVisuals")
	resultControls.preview=new("Control"):Control(ui.anchor,{16,16,width-32,78})
	function resultControls.preview:Draw()
		local x,y=self:GetPos();local w,h=self:GetSize();local half=w/2
		visual.floor(x,y,w,h,"Dark")
		local function side(offset,heading,result)
			local uncertain=result.action=="Unknown" or #(result.reasons or {})>0
			visual.text(x+offset+6,y+4,12,heading.." | "..result.action..(uncertain and " (review)" or ""),"^xA6B3C6",half-12)
			visual.chip(x+offset,y+20,half,h-20,item,result,false)
		end
		side(0,beforeLabel,before);side(half,afterLabel,after)
	end
	local rows=ui.rows(details,width-48,14)
	local height=0
	for _,row in ipairs(rows) do height=height+row.height end
	local detailsHeight=math.min(height+8,math.max(80,main.screenH-208))
	resultControls.details=new("TextListControl"):TextListControl(ui.anchor,{16,104,width-32,detailsHeight},nil,rows)
	resultControls.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-136,detailsHeight+116,120,28},"Close",function() main:ClosePopup() end)
	ui.style(resultControls)
	main:OpenPopup(width,detailsHeight+160,"Observed stack result",resultControls,nil,nil,"close")
end

local function compareStackFile(compare, beforeLabel, afterLabel)
	require("Classes.LootFilterFileBrowser").Open(main.userPath,function(path)
		local ok,summary,rows = pcall(compare,path)
		if not ok then main:OpenMessagePopup("Compare observation file",ui.errorText(summary)); return end
		local outcomes = {shown="Became visible",hidden="Became hidden",unchanged="Same visibility",unknown="Unresolved"}
		local entries = {{id="summary",label="Recorded stacks",category="Summary",details={
			string.format("%d recorded %s, %d %s in total",summary.count,summary.count==1 and "stack" or "stacks",
				summary.units,summary.units==1 and "item" or "items"),
			"Became visible: "..summary.shown, "Became hidden: "..summary.hidden,
			"Same visibility: "..summary.unchanged, "Unresolved: "..summary.unknown,
			"Counts describe only this file; they do not estimate drop rates.",
		}}}
		local function addGroups(groups,category,prefix)
			for _,group in ipairs(groups or {}) do
				local label=prefix..tostring(group.key)
				entries[#entries+1]={id=category..":"..group.key,label=label,category=category,details={
					label, string.format("%d stacks, %d items",group.count,group.units),
					"Became visible: "..group.shown, "Became hidden: "..group.hidden,
					"Same visibility: "..group.unchanged, "Unresolved: "..group.unknown,
				}}
			end
		end
		addGroups(summary.byClass,"By item class","")
		addGroups(summary.byArea,"By area level","Area level ")
		for index, row in ipairs(rows) do
			local item = row.item
			local label = string.format("%s | Stack %d | Area %d",item.BaseType,item.StackSize,item.AreaLevel)
			local details = {label,item.Class}
			if item.ItemLevel then details[#details+1] = "Item level: "..item.ItemLevel end
			describeObservedOutcome(details,beforeLabel,row.before)
			describeObservedOutcome(details,afterLabel,row.after)
			entries[#entries+1] = {id=tostring(index),label=label,category=outcomes[row.group],details=details,observation=row}
		end
		require("Classes.PlanningBrowserControl").Open("Recorded stack comparison",entries,{
			action="Preview labels",closeOnChoose=false,
			canChoose=function(entry) return entry.observation~=nil end,
			choose=function(entry) local row=entry.observation;showObservedComparison(row.item,row.before,row.after,beforeLabel,afterLabel) end,
		})
	end,{title="Choose stack observation file",itemLabel="JSON",accept=function(name) return name:lower():match("%.json$") end})
end

local function compareObservedStack(compare, compareBatch, beforeLabel, afterLabel)
	local width = math.min(540,main.screenW-40)
	local controls = {}
	local function input(key,label,x,y,w,limit)
		ui.label(controls,key.."Label",x,y,label,14)
		controls[key] = new("EditControl"):EditControl(ui.anchor,{x,y+20,w,26},"",nil,nil,limit)
	end
	input("name","Exact item name",16,16,width-32,200)
	local column = math.floor((width-48)/3)
	input("size","Stack size",16,76,column,5)
	input("area","Area level",24+column,76,column,3)
	input("level","Item level (optional)",32+2*column,76,column,3)
	ui.label(controls,"classLabel",16,136,"Item class",14)
	local choices = {{label="Automatic from item name"}}
	for _, class in ipairs(market.managedClasses) do
		if market.stackClass(class) then choices[#choices+1]={label=class,class=class} end
	end
	controls.class = new("DropDownControl"):DropDownControl(ui.anchor,{16,156,width-32,26},choices)
	local function run()
		local name = controls.name.buf:match("^%s*(.-)%s*$")
		local level
		if controls.level.buf~="" then level=tonumber(controls.level.buf) or false end
		local ok,before,after = pcall(compare,name,
			tonumber(controls.size.buf),tonumber(controls.area.buf),level,controls.class:GetSelValueByKey("class"))
		if not ok then main:OpenMessagePopup("Test observed stack",ui.errorText(before)); return end
		local itemClass = controls.class:GetSelValueByKey("class") or require("Modules.LootFilterLibrary").baseClass(name)
		showObservedComparison({BaseType=name,Class=itemClass,Rarity="Normal",StackSize=tonumber(controls.size.buf),AreaLevel=tonumber(controls.area.buf),ItemLevel=level},before,after,beforeLabel,afterLabel)
	end
	controls.test = new("ButtonControl"):ButtonControl(ui.anchor,{16,206,column,28},"Compare filters",run)
	controls.importStacks = new("ButtonControl"):ButtonControl(ui.anchor,{24+column,206,column,28},"Compare file",function()
		compareStackFile(compareBatch,beforeLabel,afterLabel)
	end)
	controls.close = new("ButtonControl"):ButtonControl(ui.anchor,{32+2*column,206,column,28},"Close",function() main:ClosePopup() end)
	ui.style(controls,{test=true})
	main:OpenPopup(width,252,"Test observed stack",controls,nil,"name","close")
end

local function comparePreviewStack(before, after)
	compareObservedStack(function(...) return sync.compareObservedStackPreview(before,after,...) end,
		function(path) return sync.compareObservedStackBatch(before,after,path) end,
		"Current filter","Proposed filter")
end

local function editItemCap(width, target, caps, selected, save)
	local controls = {}
	ui.label(controls,"itemLabel",16,20,"Exact managed item name",14)
	controls.item = new("EditControl"):EditControl(ui.anchor,{16,42,width-32,28},selected or "",nil,nil,200)
	ui.label(controls,"limitLabel",16,84,"Cap for new hides (1 to 10,000)",14)
	controls.limit = new("EditControl"):EditControl(ui.anchor,{16,106,140,28},selected and tostring(caps[selected]) or "",nil,nil,5)
	local function apply()
		local name = controls.item.buf==selected and selected or controls.item.buf:match("^%s*(.-)%s*$")
		local limit = tonumber(controls.limit.buf)
		local changes = copyTable(caps)
		local ok, result = pcall(function()
			assert(name~="" and limit, "Enter an exact item name and a whole stack size.")
			assert(name==selected or not changes[name], "Select the existing cap to edit this item.")
			if selected then changes[selected]=nil end
			changes[name]=limit
			return market.pickupPolicy(target,{caps=changes})
		end)
		if not ok then main:OpenMessagePopup("Item cap",ui.errorText(result)); return end
		main:ClosePopup()
		save(result.caps,name)
	end
	controls.apply = new("ButtonControl"):ButtonControl(ui.anchor,{16,158,148,28},"Use item cap",apply)
	controls.cancel = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,158,120,28},"Cancel",function() main:ClosePopup() end)
	controls.limit.enterFunc = apply
	ui.style(controls,{apply=true})
	main:OpenPopup(width,204,selected and "Edit item cap" or "Add item cap",controls,nil,selected and "limit" or "item","cancel")
end

local function editPickupPolicy(width, target, policy, save)
	local controls = {}
	ui.label(controls,"campaignLabel",16,16,"Campaign chaos per stack",14)
	ui.label(controls,"mapsLabel",width/2+4,16,"Maps chaos per stack",14)
	local function targetField(key,x)
		controls[key] = new("EditControl"):EditControl(ui.anchor,{x,38,width/2-32,26},
			policy[key] and tostring(policy[key]) or "", nil, nil, 10)
	end
	targetField("campaign",16)
	targetField("maps",width/2+4)
	ui.label(controls,"stackTargetHelp",16,65,"Blank uses the default stack target.",13)
	ui.label(controls,"capsLabel",16,88,"Per-item stack caps",14)
	ui.description(controls,"capsHelp",16,108,width-32,36,{
		"An item cap limits new hides after three earlier liquid daily quotes. It applies to rules managed by prices.",
	},14)
	local caps = copyTable(policy.caps or {})
	local selectionWidth = width-310
	controls.caps = new("DropDownControl"):DropDownControl(ui.anchor,{16,150,selectionWidth,28},{})
	local function refreshCaps(selected)
		local names, entries = {}, {}
		for name in pairs(caps) do names[#names+1]=name end
		table.sort(names)
		local index = 1
		for _, name in ipairs(names) do
			local value = "  |  "..caps[name]
			local title = ui.fit(StripEscapes(name),selectionWidth-70,20)
			entries[#entries+1] = {label=title..value,name=name,searchFilter=StripEscapes(name)}
			if name==selected then index=#entries end
		end
		if #entries==0 then entries[1]={label="No item caps set"} end
		controls.caps:SetList(entries)
		controls.caps:SetSel(index)
	end
	local function saveCaps(updated, selected)
		caps = updated
		refreshCaps(selected)
	end
	local function capButton(key,x,label,action)
		controls[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,150,82,28},label,action)
	end
	capButton("addCap",width-280,"Add",function()
		editItemCap(math.min(490,width),target,caps,nil,saveCaps)
	end)
	capButton("editCap",width-192,"Edit",function()
		editItemCap(math.min(490,width),target,caps,controls.caps:GetSelValueByKey("name"),saveCaps)
	end)
	capButton("removeCap",width-104,"Remove",function()
		caps[controls.caps:GetSelValueByKey("name")]=nil
		refreshCaps()
	end)
	controls.caps.enabled = function() return next(caps)~=nil end
	controls.editCap.enabled,controls.removeCap.enabled = controls.caps.enabled,controls.caps.enabled
	refreshCaps()
	ui.label(controls,"highlightLabel",16,206,"Highlight from (chaos, optional)",14)
	ui.label(controls,"strongLabel",width/2+4,206,"Strong highlight from (chaos, optional)",14)
	local function highlightField(key,x)
		controls[key] = new("EditControl"):EditControl(ui.anchor,{x,228,width/2-32,26},
			policy[key] and tostring(policy[key]) or "", nil, nil, 10)
	end
	highlightField("highlightChaos",16)
	highlightField("strongHighlightChaos",width/2+4)
	local function paletteField(key,x,defaultLabel)
		local choices = {{label=defaultLabel}}
		for _, preset in ipairs(appearance.presets) do choices[#choices+1] = preset end
		controls[key] = new("DropDownControl"):DropDownControl(ui.anchor,{x,266,width/2-32,28},choices)
		for index, preset in ipairs(choices) do
			if preset.val==policy[key] then controls[key]:SetSel(index); break end
		end
	end
	paletteField("highlightStyle",16,"Default (yellow circle)")
	paletteField("strongHighlightStyle",width/2+4,"Default (orange star)")
	local confirm = policy.confirmTightening==true
	controls.confirmTightening = new("ButtonControl"):ButtonControl(ui.anchor,{16,310,width-32,28},"",function() confirm=not confirm end)
	controls.confirmTightening.label = function() return "Require GGG trade confirmation for new hides: "..(confirm and "On" or "Off") end
	controls.apply = new("ButtonControl"):ButtonControl(ui.anchor,{16,356,180,28},"Use with next update",function()
		local passed, checked = pcall(function()
			return market.pickupPolicy(target, {
				campaign=controls.campaign.buf ~= "" and (tonumber(controls.campaign.buf) or -1) or nil,
				maps=controls.maps.buf ~= "" and (tonumber(controls.maps.buf) or -1) or nil,
				highlightChaos=controls.highlightChaos.buf ~= "" and (tonumber(controls.highlightChaos.buf) or -1) or nil,
				strongHighlightChaos=controls.strongHighlightChaos.buf ~= "" and (tonumber(controls.strongHighlightChaos.buf) or -1) or nil,
				highlightStyle=controls.highlightStyle:GetSelValueByKey("val"),
				strongHighlightStyle=controls.strongHighlightStyle:GetSelValueByKey("val"),
				confirmTightening=confirm,
				caps=caps,
			})
		end)
		if not passed then main:OpenMessagePopup("Pickup policy",ui.errorText(checked)); return end
		main:ClosePopup()
		save(checked)
	end)
	controls.cancel = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,356,120,28},"Cancel",function() main:ClosePopup() end)
	ui.style(controls)
	main:OpenPopup(width,402,"Pickup policy",controls,nil,nil,"cancel")
end

function M.Open(profileId, profileName, restored)
	profileId, profileName = profileId or "default", profileName or "Default"
	local ok, config = pcall(sync.configuration,profileId)
	if not ok then main:OpenMessagePopup("Daily filter sync", ui.errorText(config)); return end
	config = config or {}
	local pickupPolicy = restored and restored.pickupPolicy or config.pickupPolicy or {}
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
			targetValue=tonumber(c.targetValue.buf) or -1,protectionFile=c.protectionFile.buf,pickupPolicy=pickupPolicy,
			expectedSavedLeague=config.league or false}
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
	field("league", 140, "PoE 1 PC trade league", config.league or "", 16, width-166)
	local loadingLeagues = false
	c.chooseLeague = new("ButtonControl"):ButtonControl(ui.anchor,{width-142,160,126,26},"Choose league",function()
		if not market.endpoint then main:OpenMessagePopup("Choose league",market.endpointError); return end
		if launch.noSSL then main:OpenMessagePopup("Choose league", "Enable HTTPS certificate verification in PoB."); return end
		if sync.providerWait(os.time())>0 then
			main:OpenMessagePopup("Choose league","The market provider asked PoB to wait before requesting prices again.")
			return
		end
		local owner, endpoint = main.popups[1], market.endpoint
		loadingLeagues = true
		launch:DownloadPage(endpoint.."leagues",function(response, err)
			loadingLeagues = false
			if endpoint ~= market.endpoint then
				if main.popups[1] == owner then main:OpenMessagePopup("Choose league","The price source changed. Reopen the league list.") end
				return
			end
			local code = err and tonumber(err:match("^Response code: (%d+)$"))
			local wait = sync.noteProviderLimit(response,code,os.time())
			if main.popups[1] ~= owner then return end
			if wait then
				main:OpenMessagePopup("Choose league","The market provider asked PoB to wait before requesting prices again.")
				return
			end
			local valid, leagues = pcall(function()
				assert(not err, "The price provider could not be reached")
				return market.tradeLeagues(sync.fresh(response,os.time()))
			end)
			if not valid then
				main:OpenMessagePopup("Choose league","Could not verify the PC trade league list. Try again or enter the league ID.")
				return
			end
			local entries = {}
			for index, league in ipairs(leagues) do
				local details = {league.id, index == 1 and "Current PC challenge league" or "PC trade economy"}
				if league.id==config.league then details[#details+1] = "Saved for this profile" end
				entries[#entries+1] = {id=league.id,label=StripEscapes(league.name),details=details}
			end
			require("Classes.PlanningBrowserControl").Open("Choose PC trade league",entries,{
				action="Use league",
				choose=function(entry) c.league:SetText(entry.id) end,
			})
		end,{followRedirects=false,timeout=15,maxBytes=65536,header="Accept: application/json"})
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
	local function selectedLeague()
		return c.league.buf:match("^%s*(.-)%s*$")
	end
	local function leagueChanged()
		return config.league and config.league~=selectedLeague()
	end
	local function previewChanges(rollover)
		local owner = main.popups[1]
		local target, baseline, league, draft = c.target.buf,c.baseline.buf,selectedLeague(),options()
		draft.reviewLeague = rollover and true or nil
		local passed, err = pcall(sync.preview,target,baseline,league,draft,function(before, after, receipt)
			if main.popups[1] ~= owner then return end
			local reviewOptions = {inspectStack=comparePreviewStack}
			if rollover then
				if not receipt then
					main:OpenMessagePopup("Review league change","The saved profile changed. Reopen Daily price sync and review again.")
					return
				end
				reviewOptions.title="Review league change"
				reviewOptions.note="Preview for "..league..". Saving updates the profile. The live filter updates after a successful fresh sync."
				reviewOptions.label="Save reviewed league"
				reviewOptions.run=function()
					draft.expectedLeagueReview = receipt
					local saved, why = pcall(sync.configure,target,baseline,league,draft)
					if not saved then main:OpenMessagePopup("Review league change",ui.errorText(why)); return end
					main:ClosePopup()
					main:ClosePopup()
					M.Open(profileId,profileName)
				end
			end
			require("Classes.LootFilterDiffControl").Open(before,after,true,reviewOptions)
		end,function(message)
			if main.popups[1] == owner then main:OpenMessagePopup("Filter preview failed",ui.errorText(message)) end
		end)
		if not passed then main:OpenMessagePopup("Daily filter sync", ui.errorText(err)) end
	end
	button("enable",16,"Enable / update",function()
		if leagueChanged() then previewChanges(true)
		else attempt(function() sync.configure(c.target.buf,c.baseline.buf,selectedLeague(),options()) end) end
	end)
	c.enable.label = function() return leagueChanged() and "Review league" or "Enable / update" end
	button("run",16+step*1,"Sync now",function() sync.tick(os.time(),true,false,profileId) end)
	button("disable",16+step*2,"Disable",function() attempt(function() sync.disable(profileId) end) end)
	button("pause",16+step*3,config.paused and "Resume" or "Pause",function() attempt(function() sync.pause(not config.paused,profileId) end) end)
	button("rollback",16+step*4,"Review backups",function()
		local passed, backups = pcall(sync.backups,profileId)
		if not passed then main:OpenMessagePopup("Filter backups",ui.errorText(backups)); return end
		local entries, reviewed = {}, nil
		for _, backup in ipairs(backups) do
			entries[#entries+1] = {id=backup.digest,label=backup.checkedAt and os.date("%Y-%m-%d %H:%M",backup.checkedAt) or "Most recent backup",
				details={backup.digest, "Review the file changes before restoring this backup."}}
		end
		if #entries == 0 then main:OpenMessagePopup("Filter backups","No recorded backup is available for this profile."); return end
		require("Classes.PlanningBrowserControl").Open("Filter backups",entries,{
			action="Review changes",closeOnChoose=false,enterChooses=false,
			choose=function(entry)
				local verified, result = pcall(sync.previewBackup,profileId,entry.id)
				reviewed = verified and result or nil
				if not verified then main:OpenMessagePopup("Filter backups",ui.errorText(result)); return end
				require("Classes.LootFilterDiffControl").Open(result.before,result.after,true)
			end,
			secondary={label="Restore reviewed",canRun=function(entry) return reviewed ~= nil and reviewed.digest == entry.id and not sync.busy end,
				run=function()
					local selected = reviewed
					main:OpenConfirmPopup("Restore filter backup","Restore the reviewed filter and pause daily sync?","Restore",function()
						local restored, why = pcall(sync.rollback,profileId,selected)
						if not restored then main:OpenMessagePopup("Filter backups",ui.errorText(why)); return end
						main:ClosePopup()
						main:ClosePopup()
						M.Open(profileId,profileName)
					end)
				end},
		})
	end)
	button("review",16,"Last review",function()
		local saved = sync.configuration(profileId)
		if not saved or not saved.review and not (saved.history and #saved.history>0) then
			main:OpenMessagePopup("Daily filter sync", "Sync once to get a review.")
			return
		end
		local archived = sync.archivedReviews(profileId)
		local function openReview(review, historical)
			local league = review.league or saved.league
			local protection = type(review.protectedChecks)=="number"
				and string.format("%d protected filter checks passed.",review.protectedChecks) or nil
			local entries = {{
				id="summary", label="Sync status", category="Run",
				details=historical and {os.date("%Y-%m-%d %H:%M",historical.checkedAt),
					historical.adjustments.." price decisions from the baseline.", protection or "Protected drop checks passed."}
					or {saved.summary or "Daily price sync", "Next eligible run: " .. (sync.nextEligible(saved,os.time()) or "Paused or disabled"),
						review.backup and ("Backup: " .. saved.target .. ".before-pob-sync-" .. review.backup .. ".bak") or "No replacement backup yet.",
						protection},
			}}
			for i, feed in ipairs(review.feeds or {}) do
				entries[#entries+1] = {id="feed-"..i,label=feed.category,category="Price feeds",details={
					string.format("poe.ninja response age at sync: %d seconds",feed.age),
					feed.revalidated and "Server confirmed the saved response was unchanged." or "Downloaded response and verified its freshness.",
				}}
			end
			for i, change in ipairs(review.changes or {}) do
				local scope = change.scope == "campaign" and " in campaign areas" or change.maps and " in maps" or ""
				local details = {string.format("Hide cutoff from %d to %d%s", change.old, change.cutoff, scope)}
				if change.retainedReason then
					details[#details+1] = "Kept the last verified lower cutoff. "..change.retainedReason.."."
				else
					details[#details+1] = string.format("%.4g chaos used | %.0f %s",change.price,change.volume,change.liquidityUnit or "chaos quoted volume")
					details[#details+1] = string.format("Latest %.4g chaos | %d earlier daily quotes",change.currentPrice or change.price,change.observations or 0)
				end
				local priceId = market.evidencePriceId(change.priceId)
				if priceId then
					details[#details+1] = string.format("Price ID (%s) · %s",change.source or "market",priceId)
				end
				if change.gemLevel then
					details[#details+1] = string.format("Level %d, %d%% quality, %s",change.gemLevel,change.gemQuality,
						change.corrupted and "corrupted" or "uncorrupted")
				end
				if change.confirmedPrice then
					details[#details+1] = string.format("GGG completed-hour trade average: %.4g chaos",change.confirmedPrice)
				end
				for _, highlight in ipairs(change.highlights or {}) do
					details[#details+1] = string.format("Proposed highlight at %d items: %s",highlight.firstStack,highlight.icon)
				end
				local samples = change.samples or (change.sample and {change.sample}) or {}
				for _, sample in ipairs(samples) do
					local area = (sample.area or 83) >= 68 and "Maps" or "Campaign"
					local itemClass = sample.rarity and (sample.rarity.." "..sample.class) or sample.class
					local after = sample.action..(sample.line and (" at result line "..sample.line) or "")
					local before = sample.before and (sample.before..(sample.beforeLine and (" at baseline line "..sample.beforeLine) or "").." to ") or ""
					details[#details+1] = string.format("%s, %d as %s: %s%s", area, sample.count, itemClass, before, after)
					if sample.action=="Hide" and change.cutoff<change.old and sample.count>change.cutoff and sample.count<=change.old then
						details[#details+1] = "This drop is still hidden after the cutoff was lowered."
					end
					if sample.marker then details[#details+1] = "Sample marker: "..sample.marker end
					for _,phase in ipairs({{"Before",sample.before,sample.beforeMissing},{"After",sample.action,sample.afterMissing}}) do if phase[2]=="Unknown" then
						local missing=require("Modules.LootFilterParser").safeMissingProperties(phase[3])
						details[#details+1]=phase[1]..(missing and (": needs "..table.concat(missing,", ").." for this example.") or ": the preview cannot resolve a filter rule or included file.")
					end end
				end
				if change.samplesLimited then
					details[#details+1] = #samples==0 and "No samples for this decision. The review reached its sample limit."
						or "Some cases were omitted because the review reached its sample limit."
				elseif #samples == 0 then
					details[#details+1] = "Sample result unavailable."
				end
				entries[#entries+1] = {id="change-"..i,label=change.name,
					category=change.retainedReason and "Retained" or "Changed",details=details,decision=change}
			end
			for i, item in ipairs(review.skipped or {}) do
				local details = {item.reason}
				if item.source then details[#details+1] = "Price feed · "..item.source end
				if item.policyCap then
					details[#details+1] = "Configured cap: "..item.policyCap
					if item.old then details[#details+1] = "Lowest baseline cutoff: "..item.old end
				elseif item.gemLevel then
					details[#details+1] = string.format("Level %d, %d%% quality, %s",item.gemLevel,item.gemQuality,
						item.corrupted and "corrupted" or "uncorrupted")
				elseif not item.styleOnly then details[#details+1] = "Hide up to "..item.old end
				entries[#entries+1] = {id="skip-"..i,label=item.name,category=item.policyCap and "Pickup policy" or "Unchanged",details=details}
			end
			if not historical then
				for i, run in ipairs(saved.history or {}) do
					local detail = archived[run.reviewKey]
					entries[#entries+1] = {id="run-"..i,label=os.date("%Y-%m-%d %H:%M",run.checkedAt),category="History",
						historical=detail and run or nil, details={
						run.adjustments.." price decisions from the baseline.", "Protected drop checks passed.",
						run.oldest and string.format("Oldest response was %.0f minutes old",run.oldest/60) or "Response age was not recorded.",
					}}
				end
			end
			local exchange = require("Modules.LootFilterExchangeCrossCheck")
			local waiting, owner
			require("Classes.PlanningBrowserControl").Open(historical and "Archived filter sync review" or "Daily filter sync review", entries, {
				action=not historical and "Open run" or nil, enterChooses=false, closeOnChoose=false,
				canChoose=function(entry) return entry.historical ~= nil end,
				choose=function(entry) openReview(archived[entry.historical.reviewKey],entry.historical) end,
				secondary = {
					label="Compare GGG trades",
					canRun=function(entry)
						local change = entry.decision
						return not waiting and change and not change.retainedReason and not change.tier and exchange.itemId(change.name)
							and league and type(review.checkedAt)=="number"
					end,
					run=function(entry)
						if launch.noSSL then main:OpenMessagePopup("GGG trade comparison","Enable HTTPS certificate verification in PoB."); return end
						local change = entry.decision
						local hour = exchange.hour(review.checkedAt)
						waiting = true
						exchange.fetch(hour,function(markets, err)
							waiting = false
							if main.popups[1] ~= owner then return end
							local quote
							if markets then quote, err = exchange.compare(markets,league,change.name) end
							local period = os.date("!%Y-%m-%d %H:%M UTC",hour)
							local text = change.name .. " | " .. league .. "\nGGG completed hour beginning " .. period .. "\n"
							if quote then
								text = text .. string.format("GGG traded average %.4g chaos (%d items, %.0f chaos)\npoe.ninja quote at sync %.4g chaos",
									quote.price,quote.count,quote.chaosVolume,change.currentPrice or change.price)
							else
								text = text .. ui.errorText(err)
							end
							main:OpenMessagePopup("GGG trade comparison",text)
						end)
					end,
				},
			})
			owner = main.popups[1]
		end
		openReview(saved.review or {})
	end,432)
	button("preview",16+step,"Preview changes",function() previewChanges(leagueChanged()) end,432)
	c.preview.enabled = function() return not sync.busy end
	button("externalEdits",16+step*2,"External edits",function()
		local passed,before,after = pcall(sync.externalDiff,profileId)
		if not passed then main:OpenMessagePopup("External filter edits", ui.errorText(before)); return end
		local canAdopt, reviewed = pcall(sync.previewExternalAdoption,profileId)
		if canAdopt then before, after = reviewed.before, reviewed.after end
		require("Classes.LootFilterDiffControl").Open(before,after,true,{
			label="Adopt reviewed edits",
			run=function()
				if not canAdopt then main:OpenMessagePopup("External filter edits",ui.errorText(reviewed)); return end
				main:OpenConfirmPopup("Adopt filter edits",
					"Keep these edits in the fixed baseline?\nThe next refresh will price the original managed rules.",
					"Adopt edits",function()
						local adopted, why = pcall(sync.adoptExternalEdits,profileId,reviewed)
						if not adopted then main:OpenMessagePopup("External filter edits",ui.errorText(why)); return end
						main:ClosePopup()
						main:ClosePopup()
						M.Open(profileId,profileName)
					end)
			end,
		})
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
	local function latestActionConfig()
		if not sync.busy and lastStatus ~= sync.status then
			lastStatus = sync.status
			local passed, saved = pcall(sync.configuration,profileId)
			if passed and saved then cached = saved end
		end
		return cached
	end
	c.rollback.enabled = function()
		local latest = latestActionConfig()
		return not sync.busy and (latest.backup ~= nil or type(latest.history) == "table" and #latest.history > 0
			or type(latest.backupRecords) == "table" and next(latest.backupRecords) ~= nil)
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
	c.backgroundStatus = new("ButtonControl"):ButtonControl(ui.anchor,{16,504,180,26},"Check Windows task",function()
		local owner = main.popups[1]
		local passed, err = pcall(background.inspect,function(ok,state)
			if main.popups[1]~=owner then return end
			local descriptions = {
				ready="Windows has the expected background task.",
				running="Windows is running the expected background task.",
				missing="The Windows task is missing.",
				foreign="A different Windows task uses the expected name.",
				disabled="The Windows task is disabled.",
				action_changed="The task runs a different action or PoB installation.",
				account_changed="The task uses a different account or run mode.",
				trigger_changed="The task uses a different trigger or execution policy.",
				executable_missing="The task's PoB executable is missing.",
				unavailable="The Windows task is currently unavailable.",
			}
			local message = ok and descriptions[state] or ui.errorText(state)
			local preference = not config.enabled and "Price sync is disabled for this profile."
				or config.backgroundEnabled and "Background sync is enabled for this profile."
				or "This profile uses in-app sync."
			message = preference.."\n"..(message or descriptions.unavailable)
			local repairable = state=="missing" or state=="disabled" or state=="action_changed"
				or state=="account_changed" or state=="trigger_changed"
			if ok and config.enabled and config.backgroundEnabled and repairable then
				main:OpenConfirmPopup("Windows background task",message,"Repair task",function()
					local saved, problem = pcall(function()
						local latest = assert(sync.configuration(profileId), "The sync profile is unavailable.")
						assert(latest.enabled and latest.backgroundEnabled and latest.revision==config.revision,
							"Sync settings changed. Check the task again.")
						background.change(true,function(repaired,reason)
							if main.popups[1]~=owner then return end
							main:OpenMessagePopup("Windows background task",
								repaired and "Windows accepted the repaired task registration." or ui.errorText(reason))
						end,profileId)
					end)
					if not saved then main:OpenMessagePopup("Windows background task",ui.errorText(problem)) end
				end)
			else
				main:OpenMessagePopup("Windows background task",message)
			end
		end)
		if not passed then main:OpenMessagePopup("Windows background task",ui.errorText(err)) end
	end)
	c.backgroundStatus.enabled = function() return not background.busy end
	ui.description(c,"backgroundHelp",206,503,width-402,27,{"Runs while you are signed in to Windows."},13)
	c.account = new("ButtonControl"):ButtonControl(ui.anchor,{width-184,504,168,26},"Publish to account",function()
		require("Classes.LootFilterSyncAccountControl").Open(profileId)
	end)
	c.account.enabled = function() return not sync.busy end
	local fourth = math.floor((width-50)/4)
	c.backupRetention = new("ButtonControl"):ButtonControl(ui.anchor,{16,534,fourth,26},"Backup retention",function()
		local saved, latest = pcall(sync.configuration,profileId)
		if not saved or not latest then main:OpenMessagePopup("Backup retention","Could not read this sync profile."); return end
		local controls = {}
		local popupWidth = math.min(510,width)
		local help = {"Keep a set number of recorded backups after a successful sync.", "Enter 0 to keep all backups. The live filter and fixed baseline are preserved."}
		if latest.retentionSkipped then help[#help+1] = tostring(latest.retentionSkipped).." older files could not be verified or removed." end
		ui.description(controls,"help",16,18,popupWidth-32,72,help,14)
		controls.count = new("EditControl"):EditControl(ui.anchor,{16,96,140,26},tostring(latest.backupLimit or 0),nil,nil,2)
		local function save(limit)
			local done, why = pcall(sync.setBackupLimit,profileId,limit,latest.revision)
			if not done then main:OpenMessagePopup("Backup retention",ui.errorText(why)); return end
			main:ClosePopup()
		end
		controls.keep = new("ButtonControl"):ButtonControl(ui.anchor,{16,142,135,28},"Save retention",function()
			local limit = tonumber(controls.count.buf)
			if not limit or limit<0 or limit>30 or limit~=math.floor(limit) then
				main:OpenMessagePopup("Backup retention","Enter a whole number from 0 to 30.")
				return
			end
			if limit==0 then save(limit); return end
			main:OpenConfirmPopup("Limit recorded backups","Remove older verified backups after the next successful refresh?","Use limit",function() save(limit) end)
		end)
		controls.cancel = new("ButtonControl"):ButtonControl(ui.anchor,{popupWidth-136,142,120,28},"Cancel",function() main:ClosePopup() end)
		ui.style(controls)
		main:OpenPopup(popupWidth,188,"Backup retention",controls,nil,"count","cancel")
	end)
	c.backupRetention.enabled = function() return config.target ~= nil and not sync.busy end
	c.offlinePrices = new("ButtonControl"):ButtonControl(ui.anchor,{22+fourth,534,fourth,26},"Offline prices",function()
		local saved, latest = pcall(sync.configuration,profileId)
		if not saved or not latest then main:OpenMessagePopup("Offline prices","Could not read this sync profile."); return end
		local controls = {}
		local popupWidth = math.min(560,width)
		local days = {0,1,3,7}
		ui.description(controls,"help",16,18,popupWidth-32,54,{
			"Keep prices from the latest verified refresh for offline review.",
			"Preview your pending pickup settings in a read-only diff.",
		},14)
		ui.label(controls,"maxAge",16,78,"Maximum age for offline prices",14)
		controls.days = new("DropDownControl"):DropDownControl(ui.anchor,{16,100,popupWidth-32,28},
			{"Off","1 day","3 days","7 days"})
		for index, day in ipairs(days) do
			if day==(latest.offlinePriceDays or 0) then controls.days:SetSel(index); break end
		end
		controls.save = new("ButtonControl"):ButtonControl(ui.anchor,{16,146,150,28},"Save setting",function()
			local ok, why = pcall(sync.setOfflinePriceDays,profileId,days[controls.days.selIndex],latest.revision)
			if not ok then main:OpenMessagePopup("Offline prices",ui.errorText(why)); return end
			main:ClosePopup()
		end)
		controls.preview = new("ButtonControl"):ButtonControl(ui.anchor,{174,146,160,28},"Preview last prices",function()
			local ok, review = pcall(sync.previewOffline,os.time(),profileId,{
				targetValue=tonumber(c.targetValue.buf) or false,pickupPolicy=pickupPolicy,
			})
			if not ok then main:OpenMessagePopup("Offline prices",ui.errorText(review)); return end
			local note = string.format("Offline review. Oldest quote is %d minutes old. Verified refresh started on %s.",
				math.ceil(review.age/60),os.date("%Y-%m-%d %H:%M",review.checkedAt))
			require("Classes.LootFilterDiffControl").Open(review.before,review.after,true,{
				title="Offline price preview",note=note,reviewOnly=true,inspectStack=comparePreviewStack,
			})
		end)
		controls.preview.enabled = function() return latest.offlinePriceDays~=nil and not sync.busy end
		controls.cancel = new("ButtonControl"):ButtonControl(ui.anchor,{popupWidth-120,146,104,28},"Close",function() main:ClosePopup() end)
		ui.style(controls)
		main:OpenPopup(popupWidth,204,"Offline prices",controls,nil,nil,"cancel")
	end)
	c.offlinePrices.enabled = function() return config.target~=nil and not sync.busy end
	c.lastAttempt = new("ButtonControl"):ButtonControl(ui.anchor,{28+2*fourth,534,fourth,26},"Last attempt",function()
		showLastAttempt(profileId)
	end)
	c.lastAttempt.enabled = function() return config.target~=nil end
	c.observedStack = new("ButtonControl"):ButtonControl(ui.anchor,{34+3*fourth,534,fourth,26},"Test observed stack",function()
		compareObservedStack(function(...) return sync.compareObservedStack(profileId,...) end,
			function(path) return sync.compareVerifiedObservedStackBatch(profileId,path) end,"Fixed baseline","Verified filter")
	end)
	c.observedStack.enabled = function() return not sync.busy and latestActionConfig().lastSuccess~=nil end
	local popupHeight=578
	local page=restored and restored.page or "Setup"
	if main.screenH<600 then
		popupHeight=math.max(400,main.screenH-40)
		for key,control in pairs(c) do
			if key~="close" then
				local group=control.y>=350 and "Actions" or "Setup"
				if group=="Actions" then control.y=control.y-330 end
				control.shown=function() return page==group end
			end
		end
		local half=math.floor((width-40)/2)
		local function place(key,x,y,w) c[key].x,c[key].y,c[key].width=x,y,w end
		place("background",16,140,half)
		place("backgroundNotify",24+half,140,half)
		place("pickupPolicy",16,174,half)
		place("profiles",24+half,174,half)
		place("backgroundStatus",16,208,half)
		place("account",24+half,208,half)
		local quarter=math.floor((width-56)/4)
		for index,key in ipairs({"backupRetention","offlinePrices","lastAttempt","observedStack"}) do
			place(key,16+(index-1)*(quarter+8),242,quarter)
		end
		place("backgroundHelp",16,280,width-32)
		c.backgroundHelp.list=ui.rows({"Runs while you are signed in to Windows."},width-32,13)
		place("close",width-132,popupHeight-48,116)
		c.setupPage=new("ButtonControl"):ButtonControl(ui.anchor,{16,popupHeight-48,140,28},"Setup",function() page="Setup" end)
		c.actionsPage=new("ButtonControl"):ButtonControl(ui.anchor,{164,popupHeight-48,140,28},"Actions",function() page="Actions" end)
		c.setupPage.enabled=function() return page~="Setup" end
		c.actionsPage.enabled=function() return page~="Actions" end
	end
	local draftFields={"target","baseline","league","time","targetValue","intervalDays","protectionFile"}
	if restored then
		for _,key in ipairs(draftFields) do
			local saved=restored.fields[key]
			if saved then
				local field=c[key];field:SetText(saved.text)
				field.caret,field.sel,field.undo,field.redo,field.lastUndoState=saved.caret,saved.sel,saved.undo,saved.redo,saved.lastUndoState
			end
		end
	end
	ui.style(c)
	local popup
	popup=main:OpenPopup(width,popupHeight,"Daily filter sync",c,nil,nil,"close",nil,function()
		local nextWidth=math.min(720,main.screenW-40)
		local nextHeight=main.screenH<600 and math.max(400,main.screenH-40) or 578
		if main.popups[1]~=popup or sync.busy or loadingLeagues or background.busy
			or nextWidth==width and nextHeight==popupHeight then return end
		local fields,focus={}
		for _,key in ipairs(draftFields) do
			local field=c[key]
			fields[key]={text=field.buf,caret=field.caret,sel=field.sel,undo=field.undo,redo=field.redo,lastUndoState=field.lastUndoState}
			if popup.selControl==field then focus=key end
		end
		local replacement=M.Open(profileId,profileName,{fields=fields,pickupPolicy=pickupPolicy,page=page,focus=focus})
		if replacement then
			for index,entry in ipairs(main.popups) do if entry==popup then table.remove(main.popups,index);break end end
		end
	end)
	if restored and restored.focus and c[restored.focus]:IsShown() then
		local field=c[restored.focus];local saved=restored.fields[restored.focus]
		popup:SelectControl(field)
		field.caret,field.sel=saved.caret,saved.sel
		field:ScrollCaretIntoView()
	end
	return popup
end

return M
