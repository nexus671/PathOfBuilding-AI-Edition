local parser = require("Modules.LootFilterParser")
local M = {}

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
