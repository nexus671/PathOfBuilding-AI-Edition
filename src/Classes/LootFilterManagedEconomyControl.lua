local economy = require("Modules.LootFilterEconomy")
local ui = require("Modules.PlanningUI")
local M = {}

local function edit(rules, index, save)
	local existing = rules[index] or {class="Stackable Currency",scope="all",cutoff=1}
	local width = math.min(550,main.screenW-40)
	local c = {}
	local classes = {}
	for _, name in ipairs(economy.managedClasses) do classes[#classes+1] = {label=name} end
	ui.label(c,"nameLabel",16,16,"Exact item name",14)
	c.name = new("EditControl"):EditControl(ui.anchor,{16,38,width-32,26},existing.name or "",nil,nil,200)
	ui.label(c,"classLabel",16,80,"Item class",14)
	ui.label(c,"scopeLabel",width-176,80,"Area",14)
	c.class = new("DropDownControl"):DropDownControl(ui.anchor,{16,102,width-202,26},classes)
	c.class:SelByValue(existing.class,"label")
	c.scope = new("DropDownControl"):DropDownControl(ui.anchor,{width-176,102,160,26},economy.managedAreas)
	c.scope:SelByValue(existing.scope,"val")
	ui.label(c,"cutoffLabel",16,144,"Maximum stack hidden at baseline",14)
	c.cutoff = new("EditControl"):EditControl(ui.anchor,{16,166,160,26},existing.cutoff and tostring(existing.cutoff) or "",nil,nil,10)
	ui.description(c,"help",190,161,width-208,45,{"Leave the cutoff empty to manage a single-card hide."},13)
	c.save = new("ButtonControl"):ButtonControl(ui.anchor,{16,218,140,28},"Save rule",function()
		local nextRules = copyTable(rules)
		nextRules[index] = {name=c.name.buf:match("^%s*(.-)%s*$"),class=c.class:GetSelValueByKey("label"),scope=c.scope:GetSelValueByKey("val"),
			cutoff=c.cutoff.buf ~= "" and (tonumber(c.cutoff.buf) or -1) or nil}
		local ok, result = pcall(economy.validateManagedRules,nextRules)
		if not ok then main:OpenMessagePopup("Managed price rules",ui.errorText(result)); return end
		main:ClosePopup()
		save(result)
	end)
	c.close = new("ButtonControl"):ButtonControl(ui.anchor,{width-136,218,120,28},"Cancel",function() main:ClosePopup() end)
	ui.style(c)
	main:OpenPopup(width,262,"Edit managed price rule",c,nil,nil,"close")
end

function M.Open(rules, save)
	rules = rules or {}
	local entries = {{id="add",label="Add a managed price rule",details={"Choose an exact item and establish its baseline hide cutoff."}}}
	for index, rule in ipairs(rules) do
		local area = rule.scope == "maps" and "Maps" or rule.scope == "campaign" and "Campaign" or "All areas"
		entries[#entries+1] = {id=tostring(index),index=index,label=rule.name,category=area,
			details={rule.class,area,rule.cutoff and "Hide stacks up to " .. rule.cutoff or "Hide the card by exact name"}}
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
