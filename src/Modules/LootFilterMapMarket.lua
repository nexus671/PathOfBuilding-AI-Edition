local marketJSON = require("Modules.LootFilterMarketJSON")
local M = {}
M.feeds = {"Map", "BlightedMap", "BlightRavagedMap"}
M.ruleTypes = {"Map", "BlightedMap", "BlightRavagedMap", "NightmareMap"}
M.excludedFlags = {"Corrupted", "HasImplicitMod", "AnyEnchantment", "MirageMap", "ZanaMemory", "ShapedMap", "ElderMap"}
M.variants = {
	Map={label="Ordinary", name="Map", blighted=false, ravaged=false},
	BlightedMap={label="Blighted", name="Blighted Map", blighted=true, ravaged=false},
	BlightRavagedMap={label="Blight-ravaged", name="Blight-ravaged Map", ravaged=true},
	NightmareMap={label="Nightmare", name="Nightmare Map", blighted=false, ravaged=false, exactBase="Nightmare Map", feed="Map"},
}

function M.quoteName(category, tier)
	local variant = M.variants[category]
	return variant.exactBase or variant.name .. " (Tier " .. tier .. ")"
end

function M.validTier(kind, tier)
	local variant = M.variants[kind]
	return variant and type(tier)=="number" and tier==math.floor(tier)
		and (variant.exactBase and tier==17 or not variant.exactBase and tier>=1 and tier<=16)
end

local function positive(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

function M.tier(row, category)
	local variant = M.variants[category]
	if not variant or variant.exactBase or type(row.name) ~= "string" then return nil end
	if category=="Map" and row.name==M.variants.NightmareMap.exactBase
		and (row.mapTier==nil or row.mapTier==0 or row.mapTier==17)
		and (row.baseType==nil or row.baseType=="" or row.baseType==row.name) then return 17 end
	for tier=1,16 do
		if row.name == M.quoteName(category,tier) and (row.mapTier == nil or row.mapTier == 0 or row.mapTier == tier)
			and (row.baseType == nil or row.baseType == "") then
			return tier
		end
	end
end

local function comparable(row)
	if row.corrupted~=nil and row.corrupted~=false then return false end
	if row.itemClass~=nil and (type(row.itemClass)~="number" or row.itemClass<0 or row.itemClass>2 or row.itemClass~=math.floor(row.itemClass)) then return false end
	if row.variant~=nil and row.variant~="" and (type(row.variant)~="string" or not row.variant:match("^Gen%-%d+$")) then return false end
	for _, name in ipairs({"implicitModifiers","explicitModifiers","mutatedModifiers"}) do
		local mods = row[name]
		if mods~=nil and (type(mods)~="table" or next(mods)) then return false end
	end
	return true
end

function M.quotes(body, category)
	assert(type(body) == "string" and #body <= 2*1024*1024, "Invalid map response size")
	local data = marketJSON.decode(body, {"lines"})
	assert(data, "Invalid stash map response")
	local quotes, seen = {}, {}
	for _, row in ipairs(data.lines) do
		local tier = M.tier(row,category)
		local id = type(row.detailsId) == "string" and #row.detailsId <= 200
			and row.detailsId:match("^[A-Za-z0-9_.%-]+$") and row.detailsId
		local matching = tier and comparable(row)
		local priced = matching and id and positive(row.chaosValue) and positive(row.count) and positive(row.listingCount)
		-- A named map or malformed row can also claim a tier-wide price ID.
		if id then
			local name = priced and row.name or false
			local owner = seen[id]
			if owner ~= nil and owner ~= name then
				if owner then quotes[owner] = false end
				name = false
			end
			seen[id] = name
			priced = name
		end
		if matching then
			local existing = quotes[row.name]
			if not priced or existing == false or existing and (existing.id ~= id or existing.price ~= row.chaosValue or existing.variant ~= row.variant) then
				quotes[row.name] = false
			else
				local volume = math.min(row.count,row.listingCount)
				if not existing or volume < existing.volume then
					quotes[row.name] = {id=id,price=row.chaosValue,volume=volume,source=category,
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
		and not conditions.StackSize and conditions.AreaLevel~=false) then return end
	for _, key in ipairs(M.excludedFlags) do if not flag(conditions[key],false) then return end end
	local number = tonumber(tier.values[1])
	local base = conditions.BaseType
	for _, kind in ipairs(M.ruleTypes) do
		local variant = M.variants[kind]
		local exact = variant.exactBase
		local baseMatches = exact and base and base.operator=="==" and #base.values==1 and base.values[1]==exact
			or not exact and not base
		local blightMatches = variant.blighted == nil and not conditions.BlightedMap
			or variant.blighted ~= nil and flag(conditions.BlightedMap,variant.blighted)
		if M.validTier(kind,number) and baseMatches and blightMatches and flag(conditions.UberBlightedMap,variant.ravaged) then
			return variant.feed or kind, number, variant, kind
		end
	end
end

return M
