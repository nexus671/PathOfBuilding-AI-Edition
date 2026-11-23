local market = require("Modules.LootFilterEconomy")
local parser = require("Modules.LootFilterParser")
return function(raw, bodies, baselineOnly, target, protections, history, day, now)
	assert(market.supports(raw), "Baseline has no economy section")
	local quotes = {}
	for index, body in ipairs(bodies) do market.merge(quotes, market.quotes(body, market.categories[index])) end
	assert(baselineOnly or quotes["Orb of Alteration"] and quotes["Orb of Alteration"].volume >= 100, "Currency feed lacks a liquid reference quote")
	local snapshots
	if day then quotes, snapshots = market.remember(quotes, history, day, now) end
	local candidate, changes, skipped = market.review(raw, quotes, target)
	local parsed = parser.parse(candidate)
	for _, diagnostic in ipairs(parsed.diagnostics) do
		assert(not diagnostic.error, "Line " .. diagnostic.line .. ": " .. (diagnostic.error or ""))
	end
	for index, change in ipairs(changes) do
		if index > 250 then break end
		local sample = {
			BaseType=change.name, Class=change.classes[1], Rarity="Normal",
			StackSize=change.cutoff+1, AreaLevel=83, ItemLevel=83, DropLevel=1,
			Width=1, Height=1, HasExplicitMod={}, HasEnchantment={}, HasInfluence={"None"}, SocketGroup="",
			EnchantmentPassiveNode="",
		}
		for name in pairs(parser.numeric) do if sample[name] == nil then sample[name] = 0 end end
		for name in pairs(parser.booleans) do sample[name] = false end
		local result = parser.simulate(parsed, sample)
		change.sample = {action=result.action, line=result.line, class=sample.Class, count=sample.StackSize}
	end
	local function check(item, marker)
		local result = parser.simulate(parsed, item)
		local icon = result.styles.MinimapIcon
		assert(result.action == "Show" and #result.matches > 0 and (not marker or icon and table.concat(icon, " ") == marker),
			"Protected drop failed: " .. item.Rarity .. " " .. item.BaseType)
	end
	if protections then
		assert(type(protections) == "table" and #protections >= 1 and #protections <= 500, "Provide 1 to 500 protected sample items")
		for _, item in ipairs(protections) do
			assert(type(item) == "table" and type(item.BaseType) == "string" and type(item.Rarity) == "string", "Each protected sample needs BaseType and Rarity")
			check(item)
		end
		return candidate, #changes, changes, skipped, snapshots
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
	return candidate, #changes, changes, skipped, snapshots
end
