local economy = require("Modules.LootFilterEconomy")
local maps = require("Modules.LootFilterMapMarket")
local gems = require("Modules.LootFilterGemMarket")
local ui = require("Modules.PlanningUI")
local M = {}

local function edit(rules, index, save)
	local existing = rules[index] or {class="Stackable Currency",scope="all",cutoff=1}
	local width = math.min(550,main.screenW-40)
	local c = {}
	local classes = {}
	for _, name in ipairs(economy.managedClasses) do classes[#classes+1] = {label=name} end
	ui.label(c,"nameLabel",16,16,"Exact item name",14)
	c.name = new("EditControl"):EditControl(ui.anchor,{16,38,width-32,26},existing.tier and tostring(existing.tier) or existing.name or "",nil,nil,200)
	ui.label(c,"classLabel",16,80,"Item class",14)
	ui.label(c,"scopeLabel",width-176,80,"Area",14)
	c.class = new("DropDownControl"):DropDownControl(ui.anchor,{16,102,width-202,26},classes)
	c.class:SelByValue(existing.class,"label")
	local mapTypes = {}
	for _, category in ipairs(maps.feeds) do mapTypes[#mapTypes+1] = {label=maps.variants[category].label,val=category} end
	local function isMap() return c.class:GetSelValueByKey("label") == "Maps" end
	local function isGem() return gems.classes[c.class:GetSelValueByKey("label")] end
	c.nameLabel.label = function() return isMap() and "Map tier (1–16)" or "Exact item name" end
	c.scopeLabel.label = function() return isMap() and "Map variant" or "Area" end
	c.scope = new("DropDownControl"):DropDownControl(ui.anchor,{width-176,102,160,26},copyTable(isMap() and mapTypes or economy.managedAreas))
	c.scope:SelByValue(existing.mapType or existing.scope,"val")
	ui.label(c,"cutoffLabel",16,144,"Maximum stack hidden at baseline",14)
	c.cutoff = new("EditControl"):EditControl(ui.anchor,{16,166,160,26},existing.cutoff and tostring(existing.cutoff) or "",nil,nil,10)
	c.cutoff.shown = function() return not isMap() and not isGem() end
	c.cutoffLabel.shown = c.cutoff.shown
	ui.label(c,"gemLevelLabel",16,144,"Gem level",14)
	ui.label(c,"gemQualityLabel",120,144,"Quality (%)",14)
	ui.label(c,"corruptLabel",224,144,"Corruption",14)
	c.gemLevel = new("EditControl"):EditControl(ui.anchor,{16,166,88,26},tostring(existing.gemLevel or 1),nil,nil,2)
	c.gemQuality = new("EditControl"):EditControl(ui.anchor,{120,166,88,26},tostring(existing.gemQuality or 0),nil,nil,3)
	c.corruption = new("DropDownControl"):DropDownControl(ui.anchor,{224,166,width-240,26},{"Uncorrupted","Corrupted"})
	c.corruption:SetSel(existing.corrupted and 2 or 1)
	for _, key in ipairs({"gemLevelLabel","gemQualityLabel","corruptLabel","gemLevel","gemQuality","corruption"}) do c[key].shown = isGem end
	ui.description(c,"help",16,205,width-32,42,{},13)
	local function updateHelp()
		c.help.list = ui.rows({isMap() and "Uses the price for this tier and variant."
			or isGem() and "Applies to this exact gem, level, quality, and corruption."
			or "Leave the cutoff empty to manage a single-card hide."},width-32,13)
	end
	updateHelp()
	c.class.selFunc = function()
		c.scope:SetList(copyTable(isMap() and mapTypes or economy.managedAreas))
		c.scope:SetSel(1)
		updateHelp()
	end
	c.save = new("ButtonControl"):ButtonControl(ui.anchor,{16,252,140,28},"Save rule",function()
		local nextRules = copyTable(rules)
		local kind = c.class:GetSelValueByKey("label")
		if isMap() then
			nextRules[index] = {class=kind,tier=tonumber(c.name.buf),mapType=c.scope:GetSelValueByKey("val")}
		elseif isGem() then
			nextRules[index] = {class=kind,name=c.name.buf:match("^%s*(.-)%s*$"),scope=c.scope:GetSelValueByKey("val"),
				gemLevel=tonumber(c.gemLevel.buf),gemQuality=tonumber(c.gemQuality.buf),corrupted=c.corruption.selIndex==2}
		else
			nextRules[index] = {name=c.name.buf:match("^%s*(.-)%s*$"),class=kind,scope=c.scope:GetSelValueByKey("val"),
				cutoff=c.cutoff.buf ~= "" and (tonumber(c.cutoff.buf) or -1) or nil}
		end
		local ok, result = pcall(economy.validateManagedRules,nextRules)
		if not ok then main:OpenMessagePopup("Managed price rules",ui.errorText(result)); return end
		main:ClosePopup()
		save(result)
	end)
	c.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,252,120,28},"Cancel",function() main:ClosePopup() end)
	ui.style(c)
	main:OpenPopup(width,296,"Edit managed price rule",c,nil,nil,"close")
end

function M.Open(rules, save)
	rules = rules or {}
	local entries = {{id="add",label="Add a managed price rule",details={"Choose an exact item and establish its baseline hide cutoff."}}}
	for index, rule in ipairs(rules) do
		local area = rule.scope == "maps" and "Maps" or rule.scope == "campaign" and "Campaign" or "All areas"
		entries[#entries+1] = {id=tostring(index),index=index,label=rule.name,category=area,
			details={rule.class,area,rule.mapType and "Hide the tier and variant by default"
				or rule.gemLevel and string.format("Level %d, %d%% quality, %s",rule.gemLevel,rule.gemQuality,
					rule.corrupted and "corrupted" or "uncorrupted")
				or rule.cutoff and "Hide stacks up to " .. rule.cutoff or "Hide the card by exact name"}}
	end
	local function keep(value)
		save(value)
		M.Open(value,save)
	end
	require("Classes.PlanningBrowserControl").Open("Managed price rules",entries,{
		action="Open rule",closeOnChoose=false,
		choose=function(entry)
			main:ClosePopup()
			edit(rules,entry.index or (#rules+1),keep)
		end,
		secondary={label="Remove rule",canRun=function(entry) return entry.index~=nil end,run=function(entry)
			local nextRules = copyTable(rules)
			table.remove(nextRules,entry.index)
			main:ClosePopup()
			keep(nextRules)
		end},
	})
end

return M
