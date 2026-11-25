-- cspell:ignore jsontype RGBW
local json = require("dkjson")
local marketJSON = require("Modules.LootFilterMarketJSON")
local maps = require("Modules.LootFilterMapMarket")
local gemMarket = require("Modules.LootFilterGemMarket")
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
	{ id="Wombgift", label="Wombgifts", advisory=true },
	{ id="Corpse", label="Corpses", advisory=true },
	{ id="Viscera", label="Viscera", advisory=true },
	{ id="Incubator", label="Incubators", advisory=true },
	{ id="ForbiddenJewel", label="Forbidden jewels", advisory=true },
	{ id="ShrineBelt", label="Shrine belts", advisory=true },
	{ id="UniqueTincture", label="Unique tinctures", advisory=true },
	{ id="UniqueRelic", label="Unique relics", advisory=true },
	{ id="ClusterJewel", label="Cluster jewels", advisory=true },
	{ id="ValdoMap", label="Valdo maps", advisory=true },
	{ id="Invitation", label="Invitations", advisory=true },
	{ id="Memory", label="Memories", advisory=true },
	{ id="IncursionTemple", label="Incursion temples", advisory=true },
	{ id="ScryingOrb", label="Scrying orbs", advisory=true },
	{ id="Flask", label="Flasks", advisory=true },
	{ id="Beast", label="Beasts", advisory=true },
	{ id="Vial", label="Vials", advisory=true },
}

local gems = {SkillGem=true,ImbuedGem=true}
local advisoryCategories = {}
for _, category in ipairs(M.categories) do if category.advisory then advisoryCategories[category.id] = true end end

function M.advisory(category)
	return advisoryCategories[category.id] or gems[category.id] or category.id=="BaseType"
end

local function positive(value)
	return type(value) == "number" and value > 0 and value < math.huge
end

local function marketName(value)
	return type(value)=="string" and #value>0 and #value<=200 and not value:find("[%c]")
end


function M.managedTarget(rule)
	local market = require("Modules.LootFilterEconomy")
	local entry = market.validateManagedRules({rule})[1]
	local category = entry.exchangeCategory
	local target = {managed=true,name=entry.name,details={}}
	if entry.class=="Maps" then
		category = entry.mapType
		target.mapTier = entry.tier
	elseif gemMarket.classes[entry.class] then
		category = gemMarket.feed
		target.key = gemMarket.key(entry.name,entry.gemLevel,entry.gemQuality,entry.corrupted)
		target.level, target.quality, target.corrupted = entry.gemLevel,entry.gemQuality,entry.corrupted
		target.details[1] = string.format("Level %d, %d%% quality, %s",entry.gemLevel,entry.gemQuality,entry.corrupted and "corrupted" or "uncorrupted")
	elseif entry.class=="Divination Cards" then
		category = "DivinationCard"
	end
	if not category then return nil end
	target.category = category
	return target
end

function M.managedQuote(body, target)
	assert(target and target.managed, "Choose an exact managed rule")
	local market = require("Modules.LootFilterEconomy")
	assert(type(body)=="string" and #body<=market.maxFeedBytes(target.category), "Market response exceeds the size limit")
	local payload = marketJSON.decode(body, {"lines"})
	assert(payload, "Invalid market overview")
	local requested = target.key and {[target.key]=true} or nil
	local valid, quotes = pcall(market.quotes,body,target.category,requested)
	if not valid then
		local problem = tostring(quotes)
		if maps.variants[target.category] and problem:match("Map feed has no identifiable tier%-wide prices$") then
			return {state=#payload.lines==0 and "empty" or "missing"}
		end
		if problem:match("No priced exchange items$") or target.category=="SkillGem" and #payload.lines==0 then
			return {state="empty"}
		end
		error(quotes,0)
	end
	local quote = quotes[target.key or target.name]
	if quote==false then return {state="ambiguous"} end
	if not quote then return {state="missing"} end
	local supported = market.liquid(quote)
	return {state=supported and "quoted" or "thin",row={name=target.name,price=quote.price,
		identity=market.evidencePriceId(quote.providerId or quote.id),source=quote.source,volume=quote.volume,
		supported=supported,liquidityUnit=quote.liquidityUnit,variant=quote.variant,mapTier=target.mapTier,
		gemLevel=target.level,gemQuality=target.quality,corrupted=target.corrupted}}
end

local uniqueCategories = {
	["Body Armour"]="UniqueArmour", Boots="UniqueArmour", Gloves="UniqueArmour", Helmet="UniqueArmour",
	Shield="UniqueArmour", Quiver="UniqueArmour", Amulet="UniqueAccessory", Ring="UniqueAccessory",
	Belt="UniqueAccessory", Jewel="UniqueJewel", Flask="UniqueFlask", Tincture="UniqueTincture",
}

local variantBases = {
	["Two-Toned Boots"]=true, ["Two-Stone Ring"]=true,
	["Avian Twins Talisman"]=true, ["Monkey Paw Talisman"]=true,
}

local function baseTradeIdentity(baseName)
	local displayName = baseName:match("^(.-) %([^()]+%)$")
	if not variantBases[displayName] then return baseName end
	local base = data and data.itemBases and data.itemBases[baseName]
	if not base or type(base.implicit)~="string" then return displayName,false end
	local trade = require("Classes.TradeHelpers")
	local template = trade.modLineTemplate(base.implicit:gsub("%(%d+%-%d+%)","#"))
	local match
	for _, group in ipairs(trade.getTradeStats()) do
		if group.id=="implicit" then
			for _, stat in ipairs(group.entries) do
				if stat.text==template and stat.id:match("^implicit%.stat_%d+$") then
					if match and match~=stat.id then return displayName,false end
					match=stat.id
				end
			end
		end
	end
	return displayName,match or false
end

function M.listingTargetForItem(item)
	if not item or type(item.baseName)~="string" then return end
	local baseName,implicit=baseTradeIdentity(item.baseName)
	if implicit==false then return end
	return require("Modules.LootFilterGearListings").target(item,baseName)
end

local tradeRollIndex
local tradeChannels = {{"implicitMods","implicit"},{"explicitMods","explicit"},{"enchantMods","enchant"}}
local tradeKinds = {implicit=true,explicit=true,enchant=true,crafted=true,fractured=true}

function M.tradeRolls(target)
	local trade = require("Classes.TradeHelpers")
	if not tradeRollIndex then
		tradeRollIndex = {}
		for _, group in ipairs(trade.getTradeStats()) do
			if tradeKinds[group.id] then
				for _, stat in ipairs(group.entries) do
					if stat.id:match("^"..group.id.."%.stat_%d+$") and not stat.option then
						local key = group.id.."\0"..stat.text
						local prior = tradeRollIndex[key]
						tradeRollIndex[key] = (prior==nil or prior==stat.id) and stat.id or false
					end
				end
			end
		end
	end
	local rows, prior = {}, {}
	for _, channel in ipairs(tradeChannels) do
		for encoded in target[channel[1]]:gmatch("[^%z]+") do
			local line = encoded:sub(3)
			local kind = encoded:sub(1,1)=="f" and "fractured" or encoded:sub(2,2)=="c" and "crafted" or channel[2]
			local template, placeholders = trade.modLineTemplate(line)
			local exact = tradeRollIndex[kind.."\0"..line]
			local id
			if exact~=nil then id=exact else id=tradeRollIndex[kind.."\0"..template] end
			local value = id and exact==nil and placeholders==1 and trade.modLineValue(line) or nil
			local invalidRoll = value and math.abs(value)>1000000
			if invalidRoll then id,value=nil,nil end
			local entry = {line=line,kind=kind,id=id or nil,enabled=id and true or false,
				numeric=value~=nil,minimum=value,maximum=value,
				reason=invalidRoll and "This roll exceeds the supported numeric range."
					or id==false and "Multiple Trade filters match." or not id and "No supported Trade filter." or nil}
			if id and prior[id] then
				for _, row in ipairs({prior[id],entry}) do
					row.id,row.enabled,row.reason = nil,false,"More than one item modifier uses this Trade filter."
				end
			elseif id then prior[id]=entry end
			rows[#rows+1]=entry
		end
	end
	return rows
end

function M.rolledTradeQuery(target, rolls)
	local filters = setmetatable({},{__jsontype="array"})
	for _, row in ipairs(rolls) do
		if row.id and row.enabled then
			local minimum, maximum = row.minimum,row.maximum
			for _, value in pairs({minimum,maximum}) do
				assert(row.numeric and type(value)=="number" and value==value and math.abs(value)<=1000000,
					"Enter roll bounds from -1,000,000 to 1,000,000")
			end
			assert(not (minimum and maximum) or minimum<=maximum,"The minimum cannot exceed the maximum")
			filters[#filters+1]={id=row.id,value=(minimum or maximum) and {min=minimum,max=maximum} or nil}
		end
	end
	local query = {type=target.base,status={option="available"},stats={{type="and",filters=filters}},
		filters={type_filters={filters={rarity={option="rare"}}},misc_filters={filters={
			ilvl={min=target.level,max=target.level},identified={option="true"},corrupted={option=tostring(target.corrupted)}}}}}
	local equipment = target.equipment
	if equipment and equipment.sockets~="" then
		local count, largest = 0, 0
		for group in equipment.sockets:gmatch("%S+") do
			local _, links = group:gsub("[RGBW]","")
			count,largest=count+links,math.max(largest,links)
		end
		query.filters.socket_filters={filters={sockets={min=count,max=count},links={min=largest,max=largest}}}
	end
	return query
end

function M.buildTargets(build)
	local targets, seen = {}, {}
	local function add(target)
		if not marketName(target.name) then return end
		local key = table.concat({target.category,target.name,target.level or "",target.quality or "",
			target.imbuedSupport or "",target.itemLevel or "",target.baseVariant or "",target.listingSlot or ""},"\0")
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
			local selected = not slot.inactive and gear.activeItemSet and gear.activeItemSet[slot.slotName]
			itemId = selected and selected.selItemId
		end
		local item = itemId and gear.items and gear.items[itemId]
		if item and marketName(item.baseName) then
			local category = item.rarity=="UNIQUE" and (uniqueCategories[item.type]
				or data and data.weaponTypeInfo and data.weaponTypeInfo[item.type] and "UniqueWeapon")
			if item.rarity=="UNIQUE" and item.type=="Jewel" and (item.title=="Forbidden Flame" or item.title=="Forbidden Flesh") then
				category = "ForbiddenJewel"
			end
			local label = item.type=="Jewel" and slot.slotName or slot.label or slot.slotName
			if category and marketName(item.title) then
				add({name=item.title,category=category,label=label.." | "..item.title,
					details={"Compare the listed unique variants and rolls."}})
			elseif item.rarity~="UNIQUE" then
				local cluster = item.type=="Jewel" and (item.baseName=="Large Cluster Jewel" or item.baseName=="Medium Cluster Jewel" or item.baseName=="Small Cluster Jewel")
				local baseCategory = ({Viscera="Viscera",Flask="Flask"})[item.type]
				local category = baseCategory or cluster and "ClusterJewel" or "BaseType"
				local baseName, implicit = item.baseName
				if category=="BaseType" then baseName,implicit=baseTradeIdentity(item.baseName) end
				local itemLevel = item.itemLevel
				if category~="BaseType" or implicit==false or not positive(itemLevel) or itemLevel>100 or itemLevel~=math.floor(itemLevel) then itemLevel=nil end
				local listingItem = (itemLevel or cluster) and require("Modules.LootFilterGearListings").target(item,baseName)
				local labelLevel = itemLevel or listingItem and listingItem.level
				add({name=baseName,category=category,baseTarget=true,itemLevel=itemLevel,baseImplicit=implicit or nil,
					listingItem=listingItem,listingSlot=listingItem and slot.slotName or nil,
					listingSocket=listingItem and slot.nodeId or nil,
					baseVariant=baseName~=item.baseName and item.baseName or nil,
					label=label.." | "..item.baseName..(labelLevel and (" | Item level "..labelLevel) or ""),
					details={cluster and "Compare this Cluster Jewel base. A listing file checks the complete passive layout and rolls."
						or "Compare this crafting base. The equipped modifiers have their own value."}})
			end
		end
	end
	return targets
end

local function supportedVolume(item)
	return positive(item.count) and positive(item.listingCount) and math.min(item.count,item.listingCount)>=20
end


local function providerText(value, limit)
	if type(value)~="string" or #value==0 or #value>limit or value:find("[%c]")
		or value:find("://",1,true) or value:lower():find("www.",1,true) then return nil end
	local text = value:gsub("%^%d",""):gsub("%^x%x%x%x%x%x%x","")
	return text:match("%S") and text or nil
end

local function providerEvidence(item,category)
	local details, complete = {}, true
	local function text(field,label,limit)
		if item[field]==nil or item[field]=="" then return end
		local value = providerText(item[field],limit)
		if value then details[#details+1]=label..value else complete=false end
	end
	local function number(field,label,maximum)
		if item[field]==nil then return end
		local value = item[field]
		if type(value)=="number" and value>=0 and value<=maximum and value==math.floor(value) then
			details[#details+1]=label..value
		else complete=false end
	end
	text("itemType","Item type: ",100)
	number("itemClass","Provider rarity class: ",20)
	number("levelRequired",category=="BaseType" and "Unverified provider level: " or "Required character level: ",100)
	number("stackSize","Maximum stack size: ",1000000000)
	text("mapRegion","Map region: ",100)
	for _, field in ipairs({"implicitModifiers","explicitModifiers","mutatedModifiers"}) do
		local label = ({implicitModifiers="Listed implicit: ",explicitModifiers="Listed explicit: ",mutatedModifiers="Listed mutated: "})[field]
		local values = item[field]
		if values~=nil then
			if type(values)~="table" then complete=false
			else
				local count = 0
				for _, entry in ipairs(values) do
					count=count+1
					if count>12 then complete=false;break end
					local value = providerText(type(entry)=="table" and entry.text or entry,400)
					if value then details[#details+1]=label..value else complete=false end
				end
				local keys = 0
				for key in pairs(values) do
					keys=keys+1
					if keys>12 then complete=false;break end
					if type(key)~="number" or key<1 or key>#values or key~=math.floor(key) then complete=false end
				end
			end
		end
	end
	if item.metadata~=nil then
		if type(item.metadata)~="table" then complete=false
		else
			local metadata, count = {}, 0
			for key,value in pairs(item.metadata) do
				count=count+1
				if count>32 then complete=false;break end
				local label = providerText(key,80)
				local content = providerText(value,200)
				if type(value)=="number" and value==value and math.abs(value)<=1e12 or type(value)=="boolean" then content=tostring(value) end
				if label and content then metadata[#metadata+1]="Provider "..label..": "..content else complete=false end
			end
			table.sort(metadata)
			for index,value in ipairs(metadata) do
				if index>12 then complete=false;break end
				details[#details+1]=value
			end
		end
	end
	return details,complete
end

local function variantEvidence(lines, extended)
	local evidence, variants = {}, {}
	for _, item in ipairs(lines) do
		local id = type(item)=="table" and item.detailsId
		if extended then id=require("Modules.LootFilterEconomy").evidencePriceId(id) end
		if marketName(id) then
			local details,complete = {},true
			if extended then
				details,complete = providerEvidence(item)
				if not providerText(item.name,200) or item.baseType~=nil and item.baseType~="" and not providerText(item.baseType,200)
					or item.variant~=nil and item.variant~="" and not providerText(item.variant,200) then complete=false end
			end
			local signature = extended and assert(json.encode(details)) or nil
			local current = evidence[id]
			if current then
				current.supported = current.supported and supportedVolume(item) and (not extended or complete)
				if extended and current.signature~=signature then current.conflicting=true end
				for _, field in ipairs({"name","baseType","gemLevel","gemQuality","corrupted","variant","links","chaosValue","mapTier"}) do
					if current.item[field]~=item[field] then
						current.conflicting = true
						break
					end
				end
			else
				evidence[id] = {item=item,supported=supportedVolume(item) and (not extended or complete),signature=signature}
			end
			if extended then
				local key=assert(json.encode({item.name,item.baseType or false,item.variant or false,item.corrupted or false,
					item.links or false,item.gemLevel or false,item.gemQuality or false,item.mapTier or false,details}))
				local previous=variants[key]
				if previous and previous~=id then evidence[previous].conflicting,evidence[id].conflicting=true,true end
				variants[key]=id
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

local function partialImbuedMatch(item, target)
	if not target or target.category~="ImbuedGem" or item.name~=target.name
		or item.gemLevel~=nil and item.gemQuality~=nil then return false end
	local function support(value)
		if not marketName(value) then return nil end
		return value:lower():gsub(" support$","")
	end
	local wanted, listed = support(target.imbuedSupport), support(item.variant)
	if not wanted or wanted=="" or wanted~=listed then return false end
	local function agrees(value, expected, minimum, maximum)
		return value==nil or type(value)=="number" and value==math.floor(value)
			and value>=minimum and value<=maximum and value==expected
	end
	return agrees(item.gemLevel,target.level,1,40) and agrees(item.gemQuality,target.quality,0,100)
		and (item.corrupted==nil or type(item.corrupted)=="boolean")
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
		local data = marketJSON.decode(body, {"lines"})
		assert(data, "Invalid stash overview")
		local unique = category.id:match("^Unique")
		local advisory = M.advisory(category)
		local variants = (unique or advisory) and variantEvidence(data.lines,advisoryCategories[category.id])
		local uniqueEvidence = unique and uniqueBaseEvidence(data.lines,variants,catalogue)
		local handled = {}
		local partialRows = {}
		for _, item in ipairs(data.lines) do
			local extended = advisoryCategories[category.id]
			local regularFeed = category.id=="SkillGem"
			local identity = marketName(item.detailsId) and item.detailsId or nil
			if extended or regularFeed then identity=require("Modules.LootFilterEconomy").evidencePriceId(item.detailsId) end
			local name = extended and providerText(item.name,200) or not extended and item.name
			local base = extended and providerText(item.baseType,200) or not extended and item.baseType
			local variant = extended and providerText(item.variant,200) or not extended and item.variant
			local normalizedQuality, normalizedCorrupted, validGemTuple
			if regularFeed then
				local _
				_, normalizedQuality, normalizedCorrupted, _, validGemTuple = gemMarket.variant(item)
			end
			local advisoryId = advisory and identity
			local partialGemMatch = category.id=="ImbuedGem" and partialImbuedMatch(item,target)
			local comparable = not target or (target.level and item.name==target.name and item.gemLevel==target.level
				and (regularFeed and validGemTuple and normalizedQuality==target.quality
					or not regularFeed and item.gemQuality==target.quality) or not target.level and (item.name==target.name
					or (target.category=="BaseType" or target.baseTarget) and item.baseType==target.name)) or partialGemMatch
			if target and target.category=="ImbuedGem" and category.id=="ImbuedGem"
				and item.corrupted~=nil and type(item.corrupted)~="boolean" then comparable=false end
			if marketName(name) and positive(item.chaosValue) and matches(name,base,variant,identity)
				and comparable and not (advisoryId and handled[advisoryId]) then
				local corrupted
				if type(item.corrupted)=="boolean" then corrupted=item.corrupted end
				local gemLevel = positive(item.gemLevel) and item.gemLevel==math.floor(item.gemLevel) and item.gemLevel or nil
				local gemQuality = (positive(item.gemQuality) or item.gemQuality==0)
					and item.gemQuality==math.floor(item.gemQuality) and item.gemQuality or nil
				if validGemTuple then
					gemQuality, corrupted = normalizedQuality, normalizedCorrupted
				end
				local evidence = variants and identity and variants[identity]
				local conflicting = evidence and evidence.conflicting
				local supported = variants and identity and supportedVolume(item) and evidence and evidence.supported and not conflicting
				if regularFeed and not validGemTuple then supported=false end
				local details,complete = providerEvidence(item,category.id)
				if extended and (item.baseType~=nil and item.baseType~="" and not base or item.variant~=nil and item.variant~="" and not variant) then complete,supported=false,false end
				if advisoryId then handled[advisoryId] = true end
				out[#out+1] = {
					name=name, price=not conflicting and item.chaosValue or nil, identity=identity,
					conflicting=conflicting, supported=supported or nil,
					incomplete=advisory and (not identity or advisoryCategories[category.id] and not complete or gems[category.id] and not partialGemMatch
						and (not gemLevel or gemQuality==nil or corrupted==nil or regularFeed and not validGemTuple)) or nil,
					base=type(base)=="string" and base or nil,
					variant=type(variant)=="string" and variant or nil,
					corrupted=corrupted,
					baseEvidence=uniqueEvidence and uniqueEvidence[item.baseType] or nil,
					providerEvidence=details,advisoryCategory=advisoryCategories[category.id] or nil,
					links=positive(item.links) and item.links or nil,
					gemLevel=gemLevel,
					gemQuality=gemQuality,
					partialGemMatch=partialGemMatch or nil,
					mapTier=maps.tier(item,category.id) or (positive(item.mapTier) and item.mapTier or nil),
					count=positive(item.count) and item.count or nil,
					listings=positive(item.listingCount) and item.listingCount or nil,
				}
				if partialGemMatch then
					-- Omitted dimensions remain distinct from explicit values, in
					-- particular unknown corruption versus either boolean state.
					local dimensions=assert(json.encode({item.gemLevel or "absent",item.gemQuality or "absent",
						item.corrupted==nil and "absent" or item.corrupted}))
					local group=partialRows[dimensions] or {}
					group[#group+1]=out[#out]
					partialRows[dimensions]=group
				end
			end
		end
		for _, group in pairs(partialRows) do
			if #group>1 then
				for _, row in ipairs(group) do row.conflicting,row.price,row.supported=true,nil,nil end
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
