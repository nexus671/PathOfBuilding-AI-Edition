local market = require("Modules.LootFilterEconomy")
local parser = require("Modules.LootFilterParser")
local protected = require("Modules.LootFilterProtectedDrops")
local pickupAreas = require("Modules.LootFilterPickupAreas")
local appearance = require("Modules.LootFilterPriceAppearance")
return function(raw, bodies, baselineOnly, target, protections, history, day, now, policy, confirmation, priorContinuity, onCoverageFailure, recovered, pinned)
	assert(market.supports(raw), "Baseline has no economy section")
	local quotes = {}
	local categories, gemRequests = market.feedCategories(raw)
	local floors = market.liquidityFloors(policy and policy.liquidity)
	assert(baselineOnly or #bodies == #categories, "Required market category responses are missing")
	for index, body in ipairs(bodies) do market.merge(quotes, market.quotes(body, categories[index], gemRequests, floors), categories[index]) end
	assert(baselineOnly or quotes["Orb of Alteration"] and quotes["Orb of Alteration"].volume >= 100, "Currency feed lacks a liquid reference quote")
	local snapshots
	if day then
		quotes, snapshots = market.remember(quotes, history, day, now, onCoverageFailure, floors, recovered)
	end
	local candidate, changes, skipped, continuity = market.review(raw, quotes, target, policy, confirmation, priorContinuity, pinned)
	assert(#candidate <= 2*1024*1024, "Generated filter exceeds the sync file size limit")
	local parsed = parser.parse(candidate)
	for _, diagnostic in ipairs(parsed.diagnostics) do
		assert(not diagnostic.error, "Line " .. diagnostic.line .. ": " .. (diagnostic.error or ""))
	end
	if #changes > 0 then
		local earlier = parser.parse(raw)
		local remaining = 500
		for _, change in ipairs(changes) do
			local areas = pickupAreas.samples(change.scope,change.tier)
			change.samples = {}
			local stack = change.old==change.cutoff and change.highlights and change.highlights[1].firstStack
				or math.min(change.cutoff,change.old)+1
			local stacks, seenStacks = {stack}, {[stack]=true}
			for _, highlight in ipairs(change.highlights or {}) do
				local threshold = highlight.firstStack
				if not seenStacks[threshold] then
					stacks[#stacks+1], seenStacks[threshold] = threshold, true
				end
			end
			local rarities = change.uniqueBase and {"Unique"} or change.tier and {"Normal", "Magic", "Rare"} or {"Normal"}
			local expectedSamples = #change.classes * #areas * #stacks * #rarities
			for _, itemClass in ipairs(change.classes) do
				for _, area in ipairs(areas) do
					if remaining == 0 then break end
					local base = require("Modules.LootFilterLibrary").baseProperties(change.name,"Normal")
					local sample = {
						BaseType=change.name, Class=itemClass, Rarity="Normal",
						AreaLevel=area, DropLevel=base.DropLevel,
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
					if change.gemLevel then
						sample.GemLevel, sample.Quality, sample.Corrupted = change.gemLevel, change.gemQuality, change.corrupted
					end
					for _, rarity in ipairs(rarities) do
						sample.Rarity = rarity
						for _, size in ipairs(stacks) do
							if remaining == 0 then break end
							sample.StackSize = size
							local before, after = parser.simulate(earlier, sample), parser.simulate(parsed, sample)
							change.samples[#change.samples+1] = {
								action=after.action, line=after.line, before=before.action, beforeLine=before.line,
								beforeMissing=parser.safeMissingProperties(before.missingProperties), afterMissing=parser.safeMissingProperties(after.missingProperties),
								class=sample.Class, count=sample.StackSize, area=area, rarity=change.tier and rarity or nil,
								actions=appearance.resultActions(after),marker=after.action=="Show" and after.styles.MinimapIcon and table.concat(after.styles.MinimapIcon," ") or nil,
							}
							remaining = remaining-1
						end
					end
				end
			end
			change.samplesLimited = #change.samples < expectedSamples or nil
			change.sample = change.samples[1]
		end
	end
	local protectedChecks = 0
	local function check(item, marker, action)
		local result = parser.simulate(parsed, item)
		local icon = result.styles.MinimapIcon
		assert(result.action == (action or "Show") and #result.matches > 0 and (not marker or icon and table.concat(icon, " ") == marker),
			"Protected drop failed: " .. item.Rarity .. " " .. item.BaseType .. (result.action == "Unknown" and (" ("..(result.reasons[1] or "result is unknown")..")") or ""))
		protectedChecks = protectedChecks+1
	end
	if protections then
		for _, item in ipairs(protected.validateSamples(protections)) do
			check(item,item.ExpectedMarker,item.ExpectedAction)
		end
	end
	if not protections or protected.hasPersonalMarkerSet(raw) then
		for _, entry in ipairs(protected.samples()) do check(entry.item,entry.marker) end
		protected.checkPersonalSamples(raw,check)
	end
	return candidate, #changes, changes, skipped, snapshots, protectedChecks, continuity
end
