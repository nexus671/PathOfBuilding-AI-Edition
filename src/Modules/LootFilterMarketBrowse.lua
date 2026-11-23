local json = require("dkjson")
local maps = require("Modules.LootFilterMapMarket")
local M = {maxBytes=12*1024*1024}
M.categories = {
	{ id="DivinationCard", label="Divination cards", feed="exchange" },
	{ id="UniqueWeapon", label="Unique weapons" },
	{ id="UniqueArmour", label="Unique armour" },
	{ id="UniqueAccessory", label="Unique accessories" },
	{ id="UniqueJewel", label="Unique jewels" },
	{ id="UniqueFlask", label="Unique flasks" },
	{ id="Map", label="Maps" },
	{ id="BlightedMap", label="Blighted maps" },
	{ id="BlightRavagedMap", label="Blight-ravaged maps" },
	{ id="UniqueMap", label="Unique maps" },
	{ id="SkillGem", label="Skill and support gems" },
	{ id="BaseType", label="Crafting bases" },
}
local function positive(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

local function marketName(value)
	return type(value)=="string" and #value>0 and #value<=200 and not value:find("[%c]")
end

-- A loot filter sees the base of an unidentified unique. Group the whole
-- category first so searching for one unique cannot hide competing outcomes.
local function uniqueBaseEvidence(lines)
	local groups = {}
	for _, item in ipairs(lines) do
		if type(item)=="table" and marketName(item.name) and marketName(item.baseType) then
			local base = groups[item.baseType]
			if not base then
				base = {names={}, quotes={}}
				groups[item.baseType] = base
			end
			base.names[item.name] = true
			local identity = item.name .. "\0" .. (marketName(item.detailsId) and item.detailsId
				or (marketName(item.variant) and item.variant or "") .. "\0" .. (positive(item.links) and item.links or ""))
			local price = positive(item.chaosValue) and positive(item.count) and positive(item.listingCount)
				and math.min(item.count,item.listingCount)>=20 and item.chaosValue or false
			if base.quotes[identity] == nil then
				base.quotes[identity] = price
			elseif base.quotes[identity] ~= price then
				base.quotes[identity] = false
			end
		end
	end
	local evidence = {}
	for name, group in pairs(groups) do
		local names, total, priced, minimum, maximum = 0, 0, 0
		for _ in pairs(group.names) do names = names+1 end
		for _, price in pairs(group.quotes) do
			total = total+1
			if price then
				priced = priced+1
				minimum, maximum = math.min(price,minimum or price), math.max(price,maximum or price)
			end
		end
		evidence[name] = {names=names,variants=total,priced=priced,minimum=minimum,maximum=maximum}
	end
	return evidence
end

function M.rows(body, category, query)
	assert(type(body)=="string" and #body<=M.maxBytes, "Market response exceeds the size limit")
	local out = {}
	query = (query or ""):lower()
	local function matches(name, base, variant)
		return query == "" or name:lower():find(query,1,true)
			or type(base)=="string" and base:lower():find(query,1,true)
			or type(variant)=="string" and variant:lower():find(query,1,true)
	end
	if category.feed == "exchange" then
		for name, quote in pairs(require("Modules.LootFilterEconomy").quotes(body, category.id)) do
			if matches(name) then out[#out+1] = {name=name,price=quote and quote.price, volume=quote and quote.volume, ambiguous=quote==false} end
		end
	else
		local data = json.decode(body)
		assert(type(data)=="table" and type(data.lines)=="table", "Invalid stash overview")
		local uniqueEvidence = category.id:match("^Unique") and uniqueBaseEvidence(data.lines)
		for _, item in ipairs(data.lines) do
			assert(type(item)=="table", "Invalid stash overview entry")
			if marketName(item.name) and positive(item.chaosValue) and matches(item.name,item.baseType,item.variant) then
				local corrupted
				if type(item.corrupted)=="boolean" then corrupted=item.corrupted end
				out[#out+1] = {
					name=item.name, price=item.chaosValue,
					base=type(item.baseType)=="string" and item.baseType or nil,
					variant=type(item.variant)=="string" and item.variant or nil,
					corrupted=corrupted,
					baseEvidence=uniqueEvidence and uniqueEvidence[item.baseType] or nil,
					links=positive(item.links) and item.links or nil,
					gemLevel=positive(item.gemLevel) and item.gemLevel or nil,
					gemQuality=(positive(item.gemQuality) or item.gemQuality==0) and item.gemQuality or nil,
					mapTier=maps.tier(item,category.id) or (positive(item.mapTier) and item.mapTier or nil),
					count=positive(item.count) and item.count or nil,
					listings=positive(item.listingCount) and item.listingCount or nil,
				}
			end
		end
	end
	table.sort(out,function(a,b)
		if (a.price or -1) ~= (b.price or -1) then return (a.price or -1) > (b.price or -1) end
		if a.name ~= b.name then return a.name < b.name end
		return (a.variant or "") < (b.variant or "")
	end)
	assert(#out > 0, "No priced entries match this category and search")
	return out
end

return M
