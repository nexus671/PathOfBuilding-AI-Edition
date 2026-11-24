-- cspell:ignore rareonly
local marketJSON = require("Modules.LootFilterMarketJSON")
local M = {}

local maxBytes = 4 * 1024 * 1024
local jewellery = {Amulet=true, Ring=true, Belt=true}
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

function M.target(item, publicBase)
	if item.rarity~="RARE" or not jewellery[item.type] or not item.base or item.unidentifiedMarker
		or type(item.itemLevel)~="number" or item.itemLevel<1 or item.itemLevel>100 or item.itemLevel~=math.floor(item.itemLevel)
		or item.variant or item.mirrored or item.twiceCorrupted or item.talismanTier or item.memoryStrands or item.intangibility
		or item.crucible or item.vestigial
		or (item.catalyst or 0)>0 or (item.catalystQuality or 0)>0 or (item.quality or 0)>0
		or (item.base.socketLimit or 0)>0 or hasEntries(item.sockets) or hasEntries(item.scourgeModLines)
		or hasEntries(item.crucibleModLines) then return end
	local target = {base=publicBase or item.baseName,level=item.itemLevel}
	for _, key in ipairs(conditions) do target[key]=item[key]==true end
	for key in pairs(influences) do target[key]=item[key]==true end
	for _, channel in ipairs(channels) do
		local mods=modList(item,channel,true)
		if mods==nil then return end
		target[channel.listing]=mods
	end
	if target.explicitMods=="" then return end
	return target
end

local function sameItem(item, target)
	if item.identified~=true or item.rarity~="Rare" or item.frameType~=nil and item.frameType~=2 or item.ilvl~=target.level or item.realm~=nil
		or item.duplicated or item.doubleCorrupted or item.memoryItem or item.mutated or item.veiled
		or item.lockedToCharacter or item.lockedToAccount or item.enshrouded or item.unmodifiable
		or item.vestigial or item.delve or item.foreseeing or item.scourged~=nil or item.crucible~=nil
		or item.incubatedItem~=nil or item.builtInSupport~=nil or item.monsterLevel~=nil
		or item.unmodifiableExceptChaos or item.stackSize and item.stackSize~=1 or hasEntries(item.sockets)
		or hasEntries(item.socketedItems) or hasEntries(item.scourgeMods) or hasEntries(item.crucibleMods)
		or hasEntries(item.veiledMods) or hasEntries(item.grantedSkills) then return false end
	-- These comparisons only cover jewellery without extra item properties,
	-- including catalyst quality, Intangibility and Memory Strands.
	if item.properties~=nil and (type(item.properties)~="table" or next(item.properties)) then return false end
	for _,field in ipairs({"notableProperties","additionalProperties","utilityMods","ultimatumMods"}) do
		local value=item[field]
		if value~=nil and (type(value)~="table" or next(value)) then return false end
	end
	for _, key in ipairs(conditions) do
		if (item[key]==true)~=target[key] then return false end
	end
	local active = item.influences or {}
	if type(active)~="table" then return false end
	for key, flag in pairs(active) do
		if flag~=true or not knownInfluences[key] then return false end
	end
	for build, listing in pairs(influences) do
		if (item[listing]==true or active[listing]==true)~=target[build] then return false end
	end
	for _, channel in ipairs(channels) do
		if modList(item,channel,false)~=target[channel.listing] then return false end
	end
	return true
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

function M.compare(raw, target, league)
	assert(target,"Choose an identified rare ring, amulet, or belt with comparable rolls")
	assert(type(league)=="string" and #league<=80 and league:match("^[%w _-]+$") and league:find("%S"),"Enter the trade league ID")
	assert(type(raw)=="string" and #raw<=maxBytes,"The public stash file must be at most 4 MiB")
	local page=assert(marketJSON.decode(raw,{"stashes"}),"Expected a public stash API page with a stashes array")
	assert(type(page.next_change_id)=="string" and #page.next_change_id>0,"The public stash page is missing its cursor")
	local stashCounts, listings = {}, {}
	for _, stash in ipairs(page.stashes) do
		if validID(stash.id) then stashCounts[stash.id]=(stashCounts[stash.id] or 0)+1 end
	end
	for _, stash in ipairs(page.stashes) do
		if stash.public==true and stash.league==league and validID(stash.id) and stashCounts[stash.id]==1
			and type(stash.accountName)=="string" and #stash.accountName<=128 and stash.accountName:find("%S")
			and type(stash.items)=="table" then
			local seller = stash.accountName:lower()
			for _, item in ipairs(stash.items) do
				if type(item)=="table" and item.baseType==target.base and (item.league==nil or item.league==league)
					and validID(item.id) then
					if listings[item.id]~=nil then
						listings[item.id]=false
					else
						listings[item.id]={item=item,seller=seller,stashNote=stash.stash}
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
		elseif sameItem(listing.item,target) then
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
	return {inspected=inspected,matched=matched,priced=priced,ambiguous=ambiguous,results=results}
end

function M.compareFile(path, target, league)
	local file=assert(io.open(path,"rb"),"Could not open the selected public stash file")
	local raw=file:read(maxBytes+1)
	file:close()
	return M.compare(raw,target,league)
end

return M
