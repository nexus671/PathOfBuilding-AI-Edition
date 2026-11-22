local market = require("Modules.LootFilterEconomy")
local parser = require("Modules.LootFilterParser")
return function(raw, bodies, baselineOnly)
	assert(market.supports(raw), "Baseline has no economy section")
	local quotes = {}
	for _, body in ipairs(bodies) do market.merge(quotes, market.quotes(body)) end
	assert(baselineOnly or quotes["Orb of Alteration"] and quotes["Orb of Alteration"].volume >= 100, "Currency feed lacks a liquid reference quote")
	local candidate, changes = market.review(raw, quotes)
	local parsed = parser.parse(candidate)
	for _, diagnostic in ipairs(parsed.diagnostics) do
		assert(not diagnostic.error, "Line " .. diagnostic.line .. ": " .. (diagnostic.error or ""))
	end
	local function check(item, marker)
		local result = parser.simulate(parsed, item)
		local icon = result.styles.MinimapIcon
		assert(result.action == "Show" and icon and table.concat(icon, " ") == marker,
			"Protected drop failed: " .. item.Rarity .. " " .. item.BaseType)
	end
	for _, rarity in ipairs({"Normal", "Magic", "Rare", "Unique"}) do
		for _, flag in ipairs({true, false}) do
			check({BaseType="Cord Belt", Class="Belts", Rarity=rarity, Corrupted=flag, Identified=flag}, "0 Purple Star")
			check({BaseType="Royal Plate", Class="Body Armours", Rarity=rarity, LinkedSockets=6, Corrupted=flag, Identified=flag}, "0 Red Diamond")
			if rarity ~= "Unique" then
				check({BaseType="Agate Amulet", Class="Amulets", Rarity=rarity, LinkedSockets=0, FracturedItem=false, Fated=true, Identified=flag, Corrupted=flag}, "0 Purple Star")
			end
			check({BaseType="Iron Ring", Class="Rings", Rarity="Magic", LinkedSockets=0, FracturedItem=true, Identified=flag, Corrupted=flag}, "0 Yellow Diamond")
		end
	end
	return candidate, #changes
end
