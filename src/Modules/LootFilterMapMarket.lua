local json = require("dkjson")
local M = {}
M.feeds = {"Map", "BlightedMap", "BlightRavagedMap"}
M.excludedFlags = {"Corrupted", "HasImplicitMod", "AnyEnchantment", "MirageMap", "ZanaMemory", "ShapedMap", "ElderMap"}
M.variants = {
	Map={label="Ordinary", name="Map", blighted=false, ravaged=false},
	BlightedMap={label="Blighted", name="Blighted Map", blighted=true, ravaged=false},
	BlightRavagedMap={label="Blight-ravaged", name="Blight-ravaged Map", ravaged=true},
}

function M.quoteName(category, tier)
	return M.variants[category].name .. " (Tier " .. tier .. ")"
end

local function positive(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

function M.tier(row, category)
	local variant = M.variants[category]
	if not variant or type(row.name) ~= "string" then return nil end
	for tier=1,16 do
		if row.name == M.quoteName(category,tier) and (row.mapTier == nil or row.mapTier == 0 or row.mapTier == tier)
			and (row.baseType == nil or row.baseType == "") then
			return tier
		end
	end
end

function M.quotes(body, category)
	assert(type(body) == "string" and #body <= 2*1024*1024, "Invalid map response size")
	local data = json.decode(body)
	assert(type(data) == "table" and type(data.lines) == "table", "Invalid stash map response")
	local quotes = {}
	for _, row in ipairs(data.lines) do
		assert(type(row) == "table", "Invalid stash map entry")
		local tier = M.tier(row,category)
		if tier and type(row.detailsId) == "string" and #row.detailsId > 0 and #row.detailsId <= 200
			and positive(row.chaosValue) and positive(row.count) and positive(row.listingCount) then
			local existing = quotes[row.name]
			if existing == false or existing and (existing.id ~= row.detailsId or existing.price ~= row.chaosValue or existing.variant ~= row.variant) then
				quotes[row.name] = false
			else
				local volume = math.min(row.count,row.listingCount)
				if not existing or volume > existing.volume then
					quotes[row.name] = {id=row.detailsId,price=row.chaosValue,volume=volume,source=category,
						variant=row.variant,liquidityUnit="listing samples"}
				end
			end
		end
	end
	assert(next(quotes), "Map feed has no identifiable tier-wide prices")
	return quotes
end

local function flag(condition, value)
	return condition and condition.operator == "=" and #condition.values == 1
		and condition.values[1] == (value and "True" or "False")
end

function M.rule(conditions)
	local class, tier, rarity = conditions.Class, conditions.MapTier, conditions.Rarity
	if not (class and class.operator == "==" and #class.values == 1 and class.values[1] == "Maps"
		and tier and (tier.operator == "=" or tier.operator == "==") and #tier.values == 1
		and rarity and rarity.operator == "<=" and #rarity.values == 1 and rarity.values[1] == "Rare"
		and not conditions.BaseType and not conditions.StackSize and not conditions.AreaLevel) then return end
	for _, key in ipairs(M.excludedFlags) do if not flag(conditions[key],false) then return end end
	local number = tonumber(tier.values[1])
	if not number or number < 1 or number > 16 or number ~= math.floor(number) then return end
	for _, category in ipairs(M.feeds) do
		local variant = M.variants[category]
		local blightMatches = variant.blighted == nil and not conditions.BlightedMap
			or variant.blighted ~= nil and flag(conditions.BlightedMap,variant.blighted)
		if blightMatches and flag(conditions.UberBlightedMap,variant.ravaged) then
			return category, number, variant
		end
	end
end

return M
