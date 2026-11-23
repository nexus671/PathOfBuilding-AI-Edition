local json = require("dkjson")
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
		for _, item in ipairs(data.lines) do
			assert(type(item)=="table", "Invalid stash overview entry")
			if type(item.name)=="string" and #item.name>0 and #item.name<=200 and positive(item.chaosValue) and matches(item.name,item.baseType,item.variant) then
				out[#out+1] = {
					name=item.name, price=item.chaosValue,
					base=type(item.baseType)=="string" and item.baseType or nil,
					variant=type(item.variant)=="string" and item.variant or nil,
					corrupted=type(item.corrupted)=="boolean" and item.corrupted,
					links=positive(item.links) and item.links or nil,
					gemLevel=positive(item.gemLevel) and item.gemLevel or nil,
					gemQuality=positive(item.gemQuality) and item.gemQuality or nil,
					mapTier=positive(item.mapTier) and item.mapTier or nil,
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
