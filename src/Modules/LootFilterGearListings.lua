-- cspell:ignore rareonly
local marketJSON = require("Modules.LootFilterMarketJSON")
local gearProperties = require("Modules.LootFilterGearProperties")
local M = {}

local maxPageBytes = 4 * 1024 * 1024
local maxBytes = 16 * 1024 * 1024
local captureFormat = "pob-public-stash-capture-v1"
local jewellery = {Amulet=true, Ring=true, Belt=true}
-- The pinned quiver catalogue contains both discontinued and current bases
-- with these display names. Two pairs share the same natural implicit.
local sharedQuiverNames = {["Serrated Arrow Quiver"]=true,["Sharktooth Arrow Quiver"]=true,
	["Blunt Arrow Quiver"]=true,["Fire Arrow Quiver"]=true,["Broadhead Arrow Quiver"]=true,["Spike-Point Arrow Quiver"]=true}
local indistinguishableQuivers = {["Two-Point Arrow Quiver"]=true,["Penetrating Arrow Quiver"]=true}
local channels = {
	{build="enchantModLines", listing="enchantMods"},
	{build="implicitModLines", listing="implicitMods"},
	{build="explicitModLines", listing="explicitMods"},
}
local conditions = {"corrupted", "fractured", "synthesised", "split"}
local influences = {shaper="shaper",elder="elder",adjudicator="warlord",basilisk="hunter",
	crusader="crusader",eyrie="redeemer",cleansing="searing",tangle="tangled"}
local currencies = {chaos=true,divine=true}
local listingFlags = {fractured=true,crafted=true,mutated=true,desecrated=true,vestigial=true,rareonly=true}
local seedExplicit = "--Grows four random Passive Skills when Anointed\0--Passive Skills grown are influenced by Oils used when Anointing"
local knownInfluences = {}
for _, key in pairs(influences) do knownInfluences[key]=true end

local function hasEntries(value)
	return type(value)=="table" and next(value)~=nil
end

local function modKey(text, flags, enchant, legacy)
	if type(text)~="string" or #text>1200 or not text:find("%S") then return end
	text = text:gsub("%s+"," "):match("^%s*(.-)%s*$")
	if text:find("[%c{}]") or text:find("%([%-]?[%d.]+%-%-?[%d.]+%)") then return end
	if flags.vestigial or flags.rareonly or flags.mutated or flags.desecrated then return end
	return ((flags.fractured or legacy=="fractured") and "f" or "-")
		.. ((not enchant and (flags.crafted or legacy=="crafted")) and "c" or "-") .. text
end

local function addMods(values, mods, build, enchant, legacy)
	if mods==nil then return true end
	if type(mods)~="table" then return false end
	local count = 0
	for _, mod in ipairs(mods) do
		if not build and type(mod)=="string" then mod={description=mod} end
		if type(mod)~="table" or mod.disabled or mod.custom or mod.variant then return false end
		local flags = build and mod or mod.flags or {}
		local text = build and mod.line or mod.description
		if type(flags)~="table" or type(text)~="string" or #text>1200 or not text:find("%S") then return false end
		if not build then for flag,value in pairs(flags) do if not listingFlags[flag] or value~=true then return false end end end
		for line in text:gmatch("[^\r\n]+") do
			local key = modKey(line,flags,enchant,legacy)
			if not key then return false end
			values[#values+1]=key
		end
		count=count+1
	end
	for key in pairs(mods) do
		if type(key)~="number" or key<1 or key>count or key~=math.floor(key) then return false end
	end
	return true
end

local function modList(item, channel, build)
	local values = {}
	local field = build and channel.build or channel.listing
	if not addMods(values,item[field],build,channel.listing=="enchantMods") then return end
	if not build and channel.listing=="explicitMods" then
		if hasEntries(item.mutatedMods) or not addMods(values,item.craftedMods,false,false,"crafted")
			or not addMods(values,item.fracturedMods,false,false,"fractured") then return end
	end
	table.sort(values)
	return table.concat(values,"\0")
end

local function quiverBase(item)
	if indistinguishableQuivers[item.baseName] then return false end
	if not sharedQuiverNames[item.baseName] then return true end
	-- Require the current natural implicit when the public base name is shared.
	if item.base.hidden or item.corrupted or item.synthesised or #item.implicitModLines~=1 then return false end
	local line = item.implicitModLines[1].line
	local expected = item.base.implicit
	if type(line)~="string" or type(expected)~="string" then return false end
	local template = require("Classes.TradeHelpers").modLineTemplate
	return template(line)==template(expected:gsub("%(%d+%-%d+%)","#"))
end

local function clusterLayout(item)
	local cluster, jewelData = item.clusterJewel, item.jewelData
	local skill = cluster and jewelData and cluster.skills[jewelData.clusterJewelSkill]
	if not skill or item.clusterJewelSkill~=jewelData.clusterJewelSkill
		or jewelData.clusterJewelSocketCountOverride or jewelData.clusterJewelKeystone then return end
	local bonuses = {}
	for _, line in ipairs(skill.enchant) do bonuses[line]=true end
	local passives, sockets
	for _, enchant in ipairs(item.enchantModLines or {}) do
		local line = enchant.line
		local count = tonumber(line:match("^Adds (%d+) Passive Skills$"))
		local socketCount = line=="1 Added Passive Skill is a Jewel Socket" and 1
			or tonumber(line:match("^(%d+) Added Passive Skills are Jewel Sockets$"))
		if count and not passives then passives=count
		elseif socketCount and not sockets then sockets=socketCount
		elseif bonuses[line] then bonuses[line]=nil
		else return end
	end
	local expectedSockets = ({Small=0,Medium=1,Large=2})[cluster.size]
	if not passives or passives<cluster.minNodes or passives>cluster.maxNodes or next(bonuses)
		or passives~=jewelData.clusterJewelNodeCount or passives~=item.clusterJewelNodeCount
		or (sockets or 0)~=expectedSockets or (jewelData.clusterJewelSocketCount or 0)~=expectedSockets then return end
	return {passives=passives,sockets=expectedSockets}
end

local function seedLayout(item)
	local notables = item.jewelData and item.jewelData.blightcoreNotables
	local enchants = item.enchantModLines
	if item.limit~=1 or item.foilType or not notables or not enchants or #enchants<1 or #enchants>4
		or #notables~=#enchants then return end
	local names = {}
	for index, mod in ipairs(enchants) do
		local name = mod.line:match("^1 Added Passive Skill is (.+)$")
		if not name or name:lower()~=notables[index] then return end
		names[index] = name
	end
	return names
end

function M.target(item, publicBase)
	local seed = item.rarity=="UNIQUE" and item.title=="Putrid Seed" and item.baseName=="Mycelium Core"
		and item.base and item.base.subType=="Blightcore"
	if (item.rarity~="RARE" and not seed) or not item.base or item.unidentifiedMarker
		or type(item.itemLevel)~="number" or item.itemLevel<1 or item.itemLevel>100 or item.itemLevel~=math.floor(item.itemLevel)
		or item.variant or item.mirrored or item.twiceCorrupted or item.talismanTier or item.memoryStrands or item.intangibility
		or item.crucible or item.vestigial
		or (item.catalyst or 0)>0 or (item.catalystQuality or 0)>0
		or hasEntries(item.scourgeModLines) or hasEntries(item.crucibleModLines) then return end
	local equipment
	local cluster = item.type=="Jewel" and item.base.subType=="Cluster" and clusterLayout(item)
	local blightcore = seed and seedLayout(item)
	local jewel = item.type=="Jewel" and (not item.base.subType or item.base.subType=="Abyss" or cluster or blightcore)
	local quiver = item.type=="Quiver"
	if quiver and not quiverBase(item) then
		return nil,"The visible implicit cannot distinguish this quiver from its legacy base."
	end
	if item.base.armour or item.base.weapon or quiver then
		equipment=gearProperties.target(item)
		if not equipment then return end
	elseif not (jewellery[item.type] or jewel) or (item.quality or 0)>0 or (item.base.socketLimit or 0)>0 or hasEntries(item.sockets) then
		return
	end
	local target = {base=publicBase or item.baseName,level=item.itemLevel,equipment=equipment,cluster=cluster or nil,
		blightcore=blightcore or nil,
		abyssJewel=item.type=="Jewel" and item.base.subType=="Abyss",
		keepImplicit=quiver and sharedQuiverNames[item.baseName] or type(publicBase)=="string" and publicBase~=item.baseName}
	for _, key in ipairs(conditions) do target[key]=item[key]==true end
	for key in pairs(influences) do target[key]=item[key]==true end
	for _, channel in ipairs(channels) do
		local mods=modList(item,channel,true)
		if mods==nil then return end
		target[channel.listing]=mods
	end
	if target.explicitMods=="" then return end
	if blightcore and target.explicitMods~=seedExplicit then return end
	return target
end

local function seedProperties(item, names)
	local properties = item.properties
	if not marketJSON.objectRows(properties) or #properties~=1 then return false end
	local property = properties[1]
	local values = property.values
	if property.name~="Limited to" or property.displayMode~=0 or type(values)~="table" or #values~=1
		or type(values[1])~="table" or #values[1]~=2 or values[1][1]~="1" or values[1][2]~=0 then return false end
	local enchants = item.enchantMods
	if type(enchants)~="table" or #enchants~=#names then return false end
	for index, name in ipairs(names) do
		if enchants[index]~="1 Added Passive Skill is "..name then return false end
	end
	return true
end

local function sameItem(item, target, matchesRolls)
	local seed = target.blightcore
	local rarity, frame = seed and "Unique" or "Rare", seed and 3 or 2
	if item.identified~=true or item.rarity~=rarity or item.frameType~=nil and item.frameType~=frame or item.ilvl~=target.level or item.realm~=nil
		or item.duplicated or item.doubleCorrupted or item.memoryItem or item.mutated or item.veiled
		or item.lockedToCharacter or item.lockedToAccount or item.enshrouded or item.unmodifiable
		or item.vestigial or item.delve or item.foreseeing or item.scourged~=nil or item.crucible~=nil
		or item.incubatedItem~=nil or item.builtInSupport~=nil or item.monsterLevel~=nil
		or item.unmodifiableExceptChaos or item.stackSize and item.stackSize~=1
		or hasEntries(item.socketedItems) or hasEntries(item.scourgeMods) or hasEntries(item.crucibleMods)
		or hasEntries(item.veiledMods) or hasEntries(item.grantedSkills) then return false end
	if target.equipment then
		if not gearProperties.matches(item,target.equipment) then return false end
	else
		if item.sockets~=nil and (type(item.sockets)~="table" or next(item.sockets)) then return false end
		if seed then
			if item.name~="Putrid Seed" or item.typeLine~=nil and item.typeLine~="Mycelium Core"
				or item.replica or item.isRelic or item.foilVariation~=nil or not seedProperties(item,seed) then return false end
		elseif item.properties~=nil and (type(item.properties)~="table" or next(item.properties)) then return false end
	end
	for _,field in ipairs({"notableProperties","additionalProperties","utilityMods","ultimatumMods"}) do
		local value=item[field]
		if value~=nil and (type(value)~="table" or next(value)) then return false end
	end
	for _, key in ipairs(conditions) do
		local value = item[key]
		if value~=nil and type(value)~="boolean" or (value==true)~=target[key] then return false end
	end
	if item.abyssJewel~=nil and item.abyssJewel~=target.abyssJewel then return false end
	local active = item.influences or {}
	if type(active)~="table" then return false end
	for key, flag in pairs(active) do
		if flag~=true or not knownInfluences[key] then return false end
	end
	for build, listing in pairs(influences) do
		local value = item[listing]
		if value~=nil and type(value)~="boolean" or (value==true or active[listing]==true)~=target[build] then return false end
	end
	local rolled = matchesRolls and {}
	for _, channel in ipairs(channels) do
		local field = channel.listing
		local mods = modList(item,channel,false)
		if mods==nil then return false end
		if not rolled or field=="enchantMods" and target.cluster or field=="implicitMods" and target.keepImplicit then
			if mods~=target[field] then return false end
		end
		if rolled then rolled[field]=mods end
	end
	return not rolled or matchesRolls(rolled)
end

local function validID(value)
	return type(value)=="string" and #value==64 and value:match("^%x+$")~=nil
end

local function askingPrice(note)
	if type(note)~="string" or #note>80 then return end
	local amount, unit = note:match("^%s*~price%s+(%d+%.?%d*)%s+(%a+)%s*$")
	if not amount then amount,unit=note:match("^%s*~b/o%s+(%d+%.?%d*)%s+(%a+)%s*$") end
	local price = tonumber(amount)
	if price and price>0 and price<math.huge and currencies[unit] then return unit,price end
end

local function validCursor(value)
	return type(value)=="string" and #value<=512 and #value>0 and not value:find("[%s%c]")
end

local function applyPage(stashes, latest, evidence, league)
	local entries = {}
	for _, stash in ipairs(stashes) do
		local id = validID(stash.id) and stash.id:lower()
		if evidence then
			assert(id and type(stash.public)=="boolean","A capture page contains an invalid stash change")
			if stash.public and stash.league==league then
				assert(marketJSON.objectRows(stash.items),"A public stash change is missing its item array")
			end
		end
		if id then
			if entries[id]~=nil then entries[id]=false
			else entries[id]=stash end
		end
	end
	for id, stash in pairs(entries) do
		if evidence then
			if not stash then
				evidence.conflicts=evidence.conflicts+1
			elseif latest[id] and (not stash.public or stash.league~=league) then
				evidence.withdrawn=evidence.withdrawn+1
			elseif latest[id] then
				evidence.updated=evidence.updated+1
			end
		end
		latest[id] = stash and stash.public==true and stash.league==league and stash or nil
	end
end

local function readStashes(raw, league, requireCapture)
	assert(type(raw)=="string" and #raw<=maxBytes,"The listing file must be at most 16 MiB")
	local document=assert(marketJSON.decode(raw),"Expected a public stash page or PoB listing capture")
	local latest = {}
	if document.format==nil then
		assert(not requireCapture,"Choose a PoB capture with a PC league and UTC capture time")
		assert(#raw<=maxPageBytes,"A single public stash page must be at most 4 MiB")
		assert(marketJSON.objectRows(document.stashes) and validCursor(document.next_change_id),
			"Expected a public stash API page with a stash array and cursor")
		applyPage(document.stashes,latest,nil,league)
		return latest
	end
	assert(document.format==captureFormat,"Unsupported listing capture format")
	assert(document.realm=="pc","This listing comparison requires a PC capture")
	assert(document.league==league,"The capture league does not match the selected league")
	local capturedAt = document.capturedAt
	assert(type(capturedAt)=="number" and capturedAt==math.floor(capturedAt)
		and capturedAt>=1577836800 and capturedAt<=os.time(),"The capture requires a valid UTC capture timestamp")
	local pages = document.pages
	assert(marketJSON.objectRows(pages) and #pages>=1 and #pages<=32,"A capture requires 1 to 32 stash pages")
	local evidence = {realm=document.realm,capturedAt=capturedAt,pages=#pages,withdrawn=0,updated=0,conflicts=0}
	local visited, expected = {}, nil
	for index, entry in ipairs(pages) do
		local request, page = entry.requestCursor, entry.response
		assert(validCursor(request) and (not expected or request==expected) and not visited[request],
			"The capture pages do not follow consecutive request cursors")
		visited[request]=true
		assert(type(page)=="table" and validCursor(page.next_change_id) and marketJSON.objectRows(page.stashes),
			"A capture page is missing its stash array or next cursor")
		local terminal = #page.stashes==0 and index==#pages
		assert(not visited[page.next_change_id] or terminal and page.next_change_id==request,
			"The capture contains a cursor cycle")
		assert(#page.stashes>0 or terminal,"An empty stash page must be the last page")
		applyPage(page.stashes,latest,evidence,league)
		expected=page.next_change_id
	end
	return latest,evidence
end

function M.compare(raw, target, league, matchesRolls, requireCapture)
	assert(target,"Choose supported identified gear with complete rolls and equipment properties")
	assert(not (target.blightcore and matchesRolls),"Putrid Seed requires an exact ordered comparison")
	assert(type(league)=="string" and #league<=80 and league:match("^[%w _-]+$") and league:find("%S"),"Enter the trade league ID")
	local stashes, capture = readStashes(raw,league,requireCapture)
	local listings = {}
	for _, stash in pairs(stashes) do
		if type(stash.accountName)=="string" and #stash.accountName<=128 and stash.accountName:find("%S")
			and type(stash.items)=="table" then
			local seller = stash.accountName:lower()
			for _, item in ipairs(stash.items) do
				if type(item)=="table" and item.baseType==target.base and (item.league==nil or item.league==league)
					and validID(item.id) then
					local id = item.id:lower()
					if listings[id]~=nil then
						listings[id]=false
					else
						listings[id]={item=item,seller=seller,stashNote=stash.stash}
					end
				end
			end
		end
	end
	local matched, inspected, priced, ambiguous = 0,0,0,0
	local sellers = {chaos={}, divine={}}
	for _, listing in pairs(listings) do
		inspected=inspected+1
		if not listing then
			ambiguous=ambiguous+1
		elseif sameItem(listing.item,target,matchesRolls) then
			matched=matched+1
			local note = listing.item.note
			if note==nil or note=="" then note=listing.stashNote end
			local unit, amount = askingPrice(note)
			if unit then
				priced=priced+1
				local prices = sellers[unit]
				prices[listing.seller]=math.min(prices[listing.seller] or amount,amount)
			end
		end
	end
	local results = {}
	for _, unit in ipairs({"chaos","divine"}) do
		local asks = {}
		for _, amount in pairs(sellers[unit]) do asks[#asks+1]=amount end
		table.sort(asks)
		local count = #asks
		local midpoint = math.floor(count/2)
		local summary = {currency=unit,sellers=count,low=asks[1],high=asks[count]}
		if count>=3 then
			summary.median = count%2==1 and asks[midpoint+1] or asks[midpoint]+(asks[midpoint+1]-asks[midpoint])/2
		end
		results[#results+1]=summary
	end
	return {inspected=inspected,matched=matched,priced=priced,ambiguous=ambiguous,results=results,capture=capture}
end

function M.compareFile(path, target, league, matchesRolls, requireCapture)
	local file=assert(io.open(path,"rb"),"Could not open the selected public stash file")
	local raw=file:read(maxBytes+1)
	file:close()
	return M.compare(raw,target,league,matchesRolls,requireCapture)
end

return M
