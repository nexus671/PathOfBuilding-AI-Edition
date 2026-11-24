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
	{ id="Currency", label="Currencies", feed="exchange" },
	{ id="Fragment", label="Fragments", feed="exchange" },
	{ id="Runegraft", label="Runegrafts", feed="exchange" },
	{ id="AllflameEmber", label="Allflame embers", feed="exchange" },
	{ id="Tattoo", label="Tattoos", feed="exchange" },
	{ id="Omen", label="Omens", feed="exchange" },
	{ id="DjinnCoin", label="Djinn coins", feed="exchange" },
	{ id="Ducat", label="Ducats", feed="exchange" },
	{ id="EnshroudingCrystal", label="Enshrouding crystals", feed="exchange" },
	{ id="Artifact", label="Artifacts", feed="exchange" },
	{ id="Oil", label="Oils", feed="exchange" },
	{ id="DeliriumOrb", label="Delirium orbs", feed="exchange" },
	{ id="Scarab", label="Scarabs", feed="exchange" },
	{ id="Astrolabe", label="Astrolabes", feed="exchange" },
	{ id="Thread", label="Threads", feed="exchange" },
	{ id="Fossil", label="Fossils", feed="exchange" },
	{ id="Resonator", label="Resonators", feed="exchange" },
	{ id="Essence", label="Essences", feed="exchange" },
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
				local name = source and (source.itemBaseName or source.name)
				local level, quality = tonumber(gem.level), tonumber(gem.quality)
				if gem.enabled~=false and marketName(name) and positive(level) and quality and quality>=0 and quality<math.huge then
					local imbued = marketName(group.imbuedSupport) and source.grantedEffect
						and not source.grantedEffect.support and group.imbuedSupport
					add({category=imbued and "ImbuedGem" or "SkillGem",name=name,
						label=string.format("%s | Level %g, %g%% quality",name,level,quality),
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
	local spec = build.spec
	for _, slot in ipairs(gear and gear.orderedSlots or {}) do
		local itemId
		if slot.nodeId then
			if spec and spec.allocNodes and spec.allocNodes[slot.nodeId] and spec.jewels then
				itemId = spec.jewels[slot.nodeId]
			end
		else
			local selected = gear.activeItemSet and gear.activeItemSet[slot.slotName]
			itemId = selected and selected.selItemId
		end
		local item = itemId and gear.items and gear.items[itemId]
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
				for _, field in ipairs({"name","baseType","gemLevel","gemQuality","corrupted","variant","links","chaosValue"}) do
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
local function uniqueBaseEvidence(lines, variants, catalogue)
	local groups = {}
	for _, item in ipairs(lines) do
		if type(item)=="table" and marketName(item.name) and marketName(item.baseType) then
			local base = groups[item.baseType]
			if not base then
				base = {names={}, quotes={}, supportedNames={}}
				groups[item.baseType] = base
			end
			local name = item.name:lower()
			base.names[name] = true
			local id = marketName(item.detailsId) and item.detailsId
			local unverified = (marketName(item.variant) and item.variant or "") .. "\0" .. (positive(item.links) and item.links or "")
			local identity = id and ("id\0"..id) or ("unidentified\0"..name.."\0"..unverified)
			local quote = id and variants[id]
			local price = quote and not quote.conflicting and quote.supported and positive(item.chaosValue) and item.chaosValue or false
			base.quotes[identity] = price
			if price then base.supportedNames[name] = true end
		end
	end
	local missing = {}
	local function recordMissing(baseName,title,key)
		local group = groups[baseName]
		if group and not group.supportedNames[key] then
			local names = missing[baseName] or {}
			names[key] = title
			missing[baseName] = names
		end
	end
	for _, item in pairs(catalogue or {}) do
		if marketName(item.title) then
			local key = item.title:lower()
			recordMissing(item.baseName,item.title,key)
			for baseName in pairs(item.baseLines or {}) do
				recordMissing(baseName,item.title,key)
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
		local unquoted = {}
		for _, title in pairs(missing[name] or {}) do unquoted[#unquoted+1] = title end
		table.sort(unquoted)
		evidence[name] = {names=names,variants=total,priced=priced,minimum=minimum,maximum=maximum,unquoted=unquoted}
	end
	return evidence
end

function M.rows(body, category, query, target, catalogue)
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
		local economy = require("Modules.LootFilterEconomy")
		for name, quote in pairs(economy.quotes(body, category.id)) do
			local identity = quote and quote.id
			if matches(name,nil,nil,identity) then
				out[#out+1] = {name=name,price=quote and quote.price,volume=quote and quote.volume,ambiguous=quote==false,identity=identity,
					supported=quote and economy.liquid(quote) or false}
			end
		end
	else
		local data = json.decode(body)
		assert(type(data)=="table" and type(data.lines)=="table", "Invalid stash overview")
		local unique = category.id:match("^Unique")
		local advisory = M.advisory(category)
		local variants = (unique or advisory) and variantEvidence(data.lines)
		local uniqueEvidence = unique and uniqueBaseEvidence(data.lines,variants,catalogue)
		local handled = {}
		for _, item in ipairs(data.lines) do
			assert(type(item)=="table", "Invalid stash overview entry")
			local identity = marketName(item.detailsId) and item.detailsId or nil
			local advisoryId = advisory and identity
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
				local evidence = variants and identity and variants[identity]
				local conflicting = evidence and evidence.conflicting
				local supported = variants and supportedVolume(item) and (not evidence or evidence.supported)
				if advisoryId then handled[advisoryId] = true end
				out[#out+1] = {
					name=item.name, price=not conflicting and item.chaosValue or nil, identity=identity,
					conflicting=conflicting, supported=supported or nil,
					incomplete=advisory and (not identity or gems[category.id]
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
