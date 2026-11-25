local clipboard = require("Modules.MapClipboard")
local marketJSON = require("Modules.LootFilterMarketJSON")

local M = {}
local frames = {normal=0,magic=1,rare=2}
local rarities = {normal="Normal",magic="Magic",rare="Rare"}
local modFields = {explicit="explicitMods",implicit="implicitMods",enchant="enchantMods"}
local metrics = {["Map Tier"]=true,["Monster Level"]=true,["Item Quantity"]=true,
	["Item Rarity"]=true,["Monster Pack Size"]=true,["Pack Size"]=true}
local unsupported = {"influences","scourged","fractured","synthesised","split","delve","veiled","craftedMods",
	"fracturedMods","mutatedMods","utilityMods","scourgeMods","crucibleMods","ultimatumMods","notableProperties",
	"additionalProperties","sockets","socketedItems","foreseeing","unmodifiableExceptChaos","mirrored","twiceCorrupted","doubleCorrupted","unmodifiable"}

local function normalize(line)
	return (line:gsub("%[[^%]|]+|([^%]]+)%]","%1"):gsub("%[([^%]]+)%]","%1"):gsub("%s+"," "):match("^%s*(.-)%s*$"))
end

local function addProperty(properties, key, value)
	if key=="Pack Size" then key="Monster Pack Size" end
	if not (metrics[key] or key=="Quality" or key:match("^Quality %([%w '%-]+%)$")) or properties[key]~=nil then return false end
	local percent = key~="Monster Level" and key~="Map Tier"
	if not value:match(percent and "^[+-]?%d+%%$" or "^%d+$") then return false end
	properties[key]=tonumber(value:match("[+-]?%d+"))
	return true
end

local function signature(lines)
	table.sort(lines)
	return table.concat(lines,"\0")
end

function M.target(raw)
	assert(type(raw)=="string" and #raw<=24000,"Copy the complete map text.")
	raw=raw:gsub("\r\n","\n"):gsub("\nNote:[^\n]*","")
	local parsed = clipboard.parse(raw)
	local state = parsed.state
	assert(not state.unidentified and not state.mirrored and not state.twiceCorrupted,
		"Use an identified map with visible rolls and a supported corruption state.")
	local rest=raw:match("\nRarity: [^\n]+\n.-\n--------\n(.*)")
	assert(rest and rest:find("\nTravel to this Map",1,true),"Copy the complete map text.")
	local isBlight = require("Modules.MapObservedEffects").isBlighted(state.observedEffects)
	local isRavaged = require("Modules.MapObservedEffects").isBlightRavaged(state.observedEffects)
	local category = isRavaged and "BlightRavagedMap" or isBlight and "BlightedMap" or "Map"
	local base = require("Modules.MapCraftingData").source().bases[state.baseId].name
	local tierEncoded = state.baseId:match("MapKeyTier%d+$")~=nil or state.baseId:match("MapKeyNightmareBoss$")~=nil
	local alternateBase
	if state.baseId:match("MapKeyTier%d+$") then
		base = (isRavaged and "Blight-ravaged Map" or isBlight and "Blighted Map" or "Map") .. " (Tier "..state.tier..")"
		if isBlight or isRavaged then alternateBase="Map (Tier "..state.tier..")" end
	end
	local modLines, properties = {explicit={},implicit={},enchant={}}, {}
	for line in rest:gmatch("[^\n]+") do
		line=normalize(line)
		local key,value=line:match("^([^:]+): (.-)$")
		local mod,channel=line:match("^(.-) %((%a+)%)$")
		if modFields[channel] then
			local lines=modLines[channel]
			lines[#lines+1]=mod
		elseif key and (metrics[key] or key:match("^Quality")) then
			assert(addProperty(properties,key,value:gsub(" %(augmented%)$","")),"The map has an invalid or repeated displayed property.")
		elseif key=="Item Level" or key=="Note" or line=="--------" or line=="Corrupted"
			or line:match("^%b{}$") or line:match("^Travel to this Map") then
			-- Structural lines carry no modifier or price evidence.
		elseif line~="" then
			modLines.explicit[#modLines.explicit+1]=line
		end
	end
	assert(properties["Map Tier"]==nil or properties["Map Tier"]==state.tier,"Conflicting map tiers.")
	properties["Map Tier"]=state.tier
	local target = {base=base,level=state.itemLevel,map=true,category=category,tier=state.tier,rarity=state.rarity,
		corrupted=state.corrupted==true,properties=properties,alternateBase=alternateBase,tierEncoded=tierEncoded}
	for channel, field in pairs(modFields) do target[field]=signature(modLines[channel]) end
	return target
end

local function listingMods(mods)
	if mods==nil then return "" end
	if type(mods)~="table" then return end
	local lines={}
	local count=0
	for _, mod in ipairs(mods) do
		if type(mod)=="table" then
			if mod.flags~=nil and (type(mod.flags)~="table" or next(mod.flags)) then return end
			mod=mod.description
		end
		if type(mod)~="string" or #mod>1200 or not mod:find("%S") then return end
		for line in mod:gmatch("[^\r\n]+") do lines[#lines+1]=normalize(line) end
		count=count+1
	end
	for key in pairs(mods) do if type(key)~="number" or key%1~=0 or key<1 or key>count then return end end
	return signature(lines)
end

function M.matches(item, target)
	if item.baseType~=target.base and (not target.alternateBase or item.baseType~=target.alternateBase) then return false end
	if item.identified~=true or item.ilvl~=target.level or item.corrupted~=nil and type(item.corrupted)~="boolean"
		or (item.corrupted==true)~=target.corrupted or item.stackSize and item.stackSize~=1 then return false end
	if item.rarity~=nil and item.rarity~=rarities[target.rarity]
		or item.frameTypeId~=nil and (type(item.frameTypeId)~="string" or item.frameTypeId:lower()~=target.rarity)
		or item.frameType~=nil and item.frameType~=frames[target.rarity]
		or item.rarity==nil and item.frameTypeId==nil and item.frameType==nil then return false end
	for _, key in ipairs(unsupported) do if item[key]~=nil and item[key]~=false then return false end end
	if not marketJSON.objectRows(item.properties) then return false end
	local properties={}
	for _, property in ipairs(item.properties) do
		local key, values = property.name, property.values
		if type(key)~="string" or property.displayMode~=nil and property.displayMode~=0
			or type(values)~="table" or #values~=1 or type(values[1])~="table"
			or #values[1]~=2 or type(values[1][1])~="string" or type(values[1][2])~="number"
			or not addProperty(properties, key, values[1][1]) then return false end
	end
	if properties["Map Tier"]==nil and target.tierEncoded then properties["Map Tier"]=target.tier end
	for key, value in pairs(target.properties) do if properties[key]~=value then return false end end
	for key in pairs(properties) do if target.properties[key]==nil then return false end end
	for _, field in pairs(modFields) do if listingMods(item[field])~=target[field] then return false end end
	return true
end

return M
