local parser = require("Modules.LootFilterParser")
local M = {}
local scrollMarker = "# CUSTOM: Hide Wisdom and Portal Scrolls"
local ruleStarts = {Show=true,Hide=true,Minimal=true,Import=true}

local function personalRulePrefix(raw, stop)
	local rules = {}
	for line in raw:sub(1,stop-1):gmatch("[^\r\n]+") do
		local text = line:match("^%s*(.-)%s*$")
		if text ~= "" and (text:sub(1,1) ~= "#" or text:find("# CUSTOM:",1,true)==1) then
			rules[#rules+1] = line
		end
	end
	return table.concat(rules,"\n")
end

local function afterScrollRule(raw)
	local marked, inRule = false, false
	for offset, line in raw:gmatch("()([^\n]*)\n?") do
		local text = line:match("^%s*(.-)%s*$")
		local keyword = text:match("^[^%s#]+")
		if text==scrollMarker then
			marked = true
		elseif marked and ruleStarts[keyword] then
			if inRule then return offset end
			if keyword~="Hide" then return nil end
			inRule = true
		end
	end
	return inRule and #raw+1 or nil
end

function M.personalRulesPreserved(previous, candidate)
	if not previous:find(scrollMarker,1,true) then return true end
	local oldStop, newStop = afterScrollRule(previous), afterScrollRule(candidate)
	if not oldStop or not newStop then return false end
	local market = require("Modules.LootFilterEconomy")
	local oldStart, oldEnd = market.sectionBounds(previous)
	if oldStart and oldEnd then
		local newStart, newEnd = market.sectionBounds(candidate)
		if not newStart or not newEnd then return false end
		oldStop, newStop = math.max(oldStart,oldStop), math.max(newStart,newStop)
	end
	return personalRulePrefix(previous,oldStop)==personalRulePrefix(candidate,newStop)
end

function M.samples()
	local output = {}
	local function add(item, marker)
		local base = require("Modules.LootFilterLibrary").baseProperties(item.BaseType,item.Rarity)
		assert(base.Width and base.Height, "Protected sample is missing base dimensions: "..item.BaseType)
		-- A level 85 item can drop from a rare monster in an area-level 83 map.
		-- Unique drop levels are not established by the base alone.
		item.AreaLevel, item.ItemLevel, item.StackSize = 83, 85, 1
		item.Width, item.Height, item.DropLevel, item.HasInfluence = base.Width, base.Height, base.DropLevel, {"None"}
		-- Non-unique jewellery has no random base defence. For the ordinary
		-- plate, exercise the lowest roll; unique defence remains unknown.
		if item.Rarity ~= "Unique" then item.BaseDefencePercentile = item.BaseType == "Royal Plate" and 0 or 100 end
		item.HasExplicitMod, item.HasEnchantment = {}, {}
		item.SocketGroup = item.SocketGroup or ""
		item.EnchantmentPassiveNode = ""
		for key in pairs(parser.numeric) do if item[key] == nil and key ~= "DropLevel" and key ~= "BaseDefencePercentile" then item[key] = 0 end end
		for key in pairs(parser.booleans) do if item[key] == nil then item[key] = false end end
		output[#output+1] = {item=item, marker=marker}
	end
	for _, corrupted in ipairs({true,false}) do
		for _, identified in ipairs({true,false}) do
			for _, rarity in ipairs({"Normal","Magic","Rare","Unique"}) do
				add({BaseType="Cord Belt",Class="Belts",Rarity=rarity,Corrupted=corrupted,Identified=identified},"0 Purple Star")
				add({BaseType="Royal Plate",Class="Body Armours",Rarity=rarity,LinkedSockets=6,Sockets=6,SocketGroup="WWWWWW",
					Corrupted=corrupted,Identified=identified},"0 Red Diamond")
				if rarity ~= "Unique" then
					add({BaseType="Agate Amulet",Class="Amulets",Rarity=rarity,Fated=true,Corrupted=corrupted,Identified=identified},"0 Purple Star")
				end
			end
			add({BaseType="Iron Ring",Class="Rings",Rarity="Magic",FracturedItem=true,Corrupted=corrupted,Identified=identified},"0 Yellow Diamond")
		end
	end
	return output
end

function M.explicitlyShown(result)
	return result.action == "Show" and #result.matches > 0
end

function M.marker(result)
	local icon = result.styles.MinimapIcon
	return icon and table.concat(icon," ")
end

return M
