local market = require("Modules.LootFilterEconomy")
local parser = require("Modules.LootFilterParser")
local protected = require("Modules.LootFilterProtectedDrops")
return function(raw, bodies, baselineOnly, target, protections, history, day, now, policy)
	assert(market.supports(raw), "Baseline has no economy section")
	local quotes = {}
	local categories = market.feedCategories(raw)
	assert(baselineOnly or #bodies == #categories, "Required market category responses are missing")
	for index, body in ipairs(bodies) do market.merge(quotes, market.quotes(body, categories[index]), categories[index]) end
	assert(baselineOnly or quotes["Orb of Alteration"] and quotes["Orb of Alteration"].volume >= 100, "Currency feed lacks a liquid reference quote")
	local snapshots
	if day then quotes, snapshots = market.remember(quotes, history, day, now) end
	local candidate, changes, skipped = market.review(raw, quotes, target, policy)
	local parsed = parser.parse(candidate)
	for _, diagnostic in ipairs(parsed.diagnostics) do
		assert(not diagnostic.error, "Line " .. diagnostic.line .. ": " .. (diagnostic.error or ""))
	end
	if #changes > 0 then
		local earlier = parser.parse(raw)
		local remaining = 500
		for _, change in ipairs(changes) do
			if remaining == 0 then break end
			local areas = change.scope == "campaign" and {60} or change.scope == "maps" and {83} or {83, 60}
			change.samples = {}
			local stack = change.old==change.cutoff and change.highlights and change.highlights[1].firstStack
				or math.min(change.cutoff,change.old)+1
			for _, itemClass in ipairs(change.classes) do
				for _, area in ipairs(areas) do
					if remaining == 0 then break end
					local base = require("Modules.LootFilterLibrary").baseProperties(change.name,"Normal")
					local sample = {
						BaseType=change.name, Class=itemClass, Rarity="Normal",
						StackSize=stack, AreaLevel=area, DropLevel=base.DropLevel,
						Width=base.Width, Height=base.Height, HasExplicitMod={}, HasEnchantment={}, HasInfluence={"None"},
						SocketGroup="", EnchantmentPassiveNode="",
					}
					for name in pairs(parser.numeric) do if sample[name] == nil and name ~= "ItemLevel" and name ~= "DropLevel" and name ~= "Width" and name ~= "Height" then sample[name] = 0 end end
					for name in pairs(parser.booleans) do sample[name] = false end
					if change.tier then
						sample.MapTier = change.tier
						sample.BlightedMap = change.blighted or change.ravaged
						sample.UberBlightedMap = change.ravaged
					end
					local before, after = parser.simulate(earlier, sample), parser.simulate(parsed, sample)
					change.samples[#change.samples+1] = {
						action=after.action, line=after.line, before=before.action, beforeLine=before.line,
						beforeMissing=parser.safeMissingProperties(before.missingProperties), afterMissing=parser.safeMissingProperties(after.missingProperties),
						class=sample.Class, count=sample.StackSize, area=area,
						marker=after.action=="Show" and after.styles.MinimapIcon and table.concat(after.styles.MinimapIcon," ") or nil,
					}
					remaining = remaining-1
				end
			end
			change.sample = change.samples[1]
		end
	end
	local function check(item, marker)
		local result = parser.simulate(parsed, item)
		local icon = result.styles.MinimapIcon
		assert(result.action == "Show" and #result.matches > 0 and (not marker or icon and table.concat(icon, " ") == marker),
			"Protected drop failed: " .. item.Rarity .. " " .. item.BaseType .. (result.action == "Unknown" and (" ("..(result.reasons[1] or "result is unknown")..")") or ""))
	end
	if protections then
		assert(type(protections) == "table" and #protections >= 1 and #protections <= 500, "Provide 1 to 500 protected sample items")
		for _, item in ipairs(protections) do
			assert(type(item) == "table" and type(item.BaseType) == "string" and type(item.Rarity) == "string", "Each protected sample needs BaseType and Rarity")
			check(item)
		end
		return candidate, #changes, changes, skipped, snapshots
	end
	for _, entry in ipairs(protected.samples()) do check(entry.item,entry.marker) end
	return candidate, #changes, changes, skipped, snapshots
end
