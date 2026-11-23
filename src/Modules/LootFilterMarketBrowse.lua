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
	{ id="ImbuedGem", label="Imbued gems" },
}

local gems = {SkillGem=true,ImbuedGem=true}

function M.advisory(category)
	return gems[category.id] or category.id=="BaseType"
end

local function positive(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

local function marketName(value)
	return type(value)=="string" and #value>0 and #value<=200 and not value:find("[%c]")
end

local uniqueCategories = {
	["Body Armour"]="UniqueArmour", Boots="UniqueArmour", Gloves="UniqueArmour", Helmet="UniqueArmour",
	Shield="UniqueArmour", Quiver="UniqueArmour", Amulet="UniqueAccessory", Ring="UniqueAccessory",
	Belt="UniqueAccessory", Jewel="UniqueJewel", Flask="UniqueFlask",
}

function M.buildTargets(build)
	local targets, seen = {}, {}
	local function add(target)
		if not marketName(target.name) then return end
		local key = table.concat({target.category,target.name,target.level or "",target.quality or "",target.imbuedSupport or ""},"\0")
		if not seen[key] then
			seen[key] = true
			target.id = tostring(#targets+1)
			targets[#targets+1] = target
		end
	end
	local skills = build.skillsTab
	for _, group in ipairs(skills and skills.socketGroupList or {}) do
		if group.enabled~=false and not group.source then
			for _, gem in ipairs(group.gemList or {}) do
				local source = gem.gemData
				local level, quality = tonumber(gem.level), tonumber(gem.quality)
				if gem.enabled~=false and source and marketName(source.name) and positive(level) and quality and quality>=0 and quality<math.huge then
					local imbued = marketName(group.imbuedSupport) and source.grantedEffect
						and not source.grantedEffect.support and group.imbuedSupport
					add({category=imbued and "ImbuedGem" or "SkillGem",name=source.name,
						label=string.format("%s | Level %g, %g%% quality",source.name,level,quality),
						level=level,quality=quality,imbuedSupport=imbued or nil,details={
							string.format("Level %g, %g%% quality",level,quality),
							imbued and ("Build support: "..imbued..". Compare supports and corruption states.") or
								"Compare the available corruption states and variants.",
						}})
				end
			end
		end
	end
	local gear = build.itemsTab
	for _, slot in ipairs(gear and gear.orderedSlots or {}) do
		local selected = gear.activeItemSet and gear.activeItemSet[slot.slotName]
		local item = selected and gear.items and gear.items[selected.selItemId]
		if item and marketName(item.baseName) then
			local category = item.rarity=="UNIQUE" and (uniqueCategories[item.type]
				or data and data.weaponTypeInfo and data.weaponTypeInfo[item.type] and "UniqueWeapon")
			local label = slot.label or slot.slotName
			if category and marketName(item.title) then
				add({name=item.title,category=category,label=label.." | "..item.title,
					details={"Compare the listed unique variants and rolls."}})
			elseif item.rarity~="UNIQUE" then
				add({name=item.baseName,category="BaseType",label=label.." | "..item.baseName,
					details={"Compare this crafting base. The equipped modifiers have their own value."}})
			end
		end
	end
	return targets
end

local function supportedVolume(item)
	return positive(item.count) and positive(item.listingCount) and math.min(item.count,item.listingCount)>=20
end

local function variantEvidence(lines)
	local evidence = {}
	for _, item in ipairs(lines) do
		local id = type(item)=="table" and item.detailsId
		if marketName(id) then
			local current = evidence[id]
			if current then
				current.supported = current.supported and supportedVolume(item)
				for _, field in ipairs({"name","baseType","gemLevel","gemQuality","corrupted","variant","chaosValue"}) do
					if current.item[field]~=item[field] then
						current.conflicting = true
						break
					end
				end
			else
				evidence[id] = {item=item,supported=supportedVolume(item)}
			end
		end
	end
	return evidence
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
			local price = positive(item.chaosValue) and supportedVolume(item) and item.chaosValue or false
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

function M.rows(body, category, query, target)
	assert(type(body)=="string" and #body<=M.maxBytes, "Market response exceeds the size limit")
	local out = {}
	query = (query or ""):lower()
	local exact = query:sub(1,1)=="="
	if exact then query = query:sub(2):match("^%s*(.-)%s*$") end
	local function matches(name, base, variant, identity)
		if exact then return name:lower()==query or type(base)=="string" and base:lower()==query
			or type(identity)=="string" and identity:lower()==query end
		return query == "" or name:lower():find(query,1,true)
			or type(base)=="string" and base:lower():find(query,1,true)
			or type(variant)=="string" and variant:lower():find(query,1,true)
			or type(identity)=="string" and identity:lower():find(query,1,true)
	end
	if category.feed == "exchange" then
		for name, quote in pairs(require("Modules.LootFilterEconomy").quotes(body, category.id)) do
			local identity = quote and quote.id
			if matches(name,nil,nil,identity) then
				out[#out+1] = {name=name,price=quote and quote.price,volume=quote and quote.volume,ambiguous=quote==false,identity=identity}
			end
		end
	else
		local data = json.decode(body)
		assert(type(data)=="table" and type(data.lines)=="table", "Invalid stash overview")
		local uniqueEvidence = category.id:match("^Unique") and uniqueBaseEvidence(data.lines)
		local variants = M.advisory(category) and variantEvidence(data.lines)
		local handled = {}
		for _, item in ipairs(data.lines) do
			assert(type(item)=="table", "Invalid stash overview entry")
			local identity = marketName(item.detailsId) and item.detailsId or nil
			local advisoryId = variants and identity
			local comparable = not target or (target.level and item.name==target.name and item.gemLevel==target.level
				and item.gemQuality==target.quality or not target.level and (item.name==target.name
					or target.category=="BaseType" and item.baseType==target.name))
			if marketName(item.name) and positive(item.chaosValue) and matches(item.name,item.baseType,item.variant,identity)
				and comparable and not (advisoryId and handled[advisoryId]) then
				local corrupted
				if type(item.corrupted)=="boolean" then corrupted=item.corrupted end
				local gemLevel = positive(item.gemLevel) and item.gemLevel==math.floor(item.gemLevel) and item.gemLevel or nil
				local gemQuality = (positive(item.gemQuality) or item.gemQuality==0)
					and item.gemQuality==math.floor(item.gemQuality) and item.gemQuality or nil
				local evidence = advisoryId and variants[advisoryId]
				local conflicting = evidence and evidence.conflicting
				local supported = variants and supportedVolume(item) and (not evidence or evidence.supported)
				if advisoryId then handled[advisoryId] = true end
				out[#out+1] = {
					name=item.name, price=not conflicting and item.chaosValue or nil, identity=identity,
					conflicting=conflicting, supported=supported or nil,
					incomplete=variants and (not identity or gems[category.id]
						and (not gemLevel or gemQuality==nil or corrupted==nil)) or nil,
					base=type(item.baseType)=="string" and item.baseType or nil,
					variant=type(item.variant)=="string" and item.variant or nil,
					corrupted=corrupted,
					baseEvidence=uniqueEvidence and uniqueEvidence[item.baseType] or nil,
					links=positive(item.links) and item.links or nil,
					gemLevel=gemLevel,
					gemQuality=gemQuality,
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
		if a.variant ~= b.variant then return (a.variant or "") < (b.variant or "") end
		return (a.identity or "") < (b.identity or "")
	end)
	assert(#out > 0, "No priced entries match this category and search")
	return out
end

return M
