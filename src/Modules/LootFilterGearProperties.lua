-- Match displayed equipment properties before using a listing as a comparable ask.
local M = {}

local defences = {Armour="Armour",Evasion="Evasion Rating",EnergyShield="Energy Shield",Ward="Ward"}
local rawNames = {Sockets=true,Quality=true,Armour=true,Evasion=true,["Evasion Rating"]=true,["Energy Shield"]=true,Ward=true}
local elemental = {"Fire","Cold","Lightning"}
local ordinarySockets = {R=true,G=true,B=true,W=true}

local function socketKey(sockets, colorKey)
	if type(sockets)~="table" or #sockets>6 then return end
	local parts, groups, previous = {}, {}, nil
	for _, socket in ipairs(sockets) do
		local color, group
		if type(socket)=="table" then color,group=socket[colorKey],socket.group end
		if not ordinarySockets[color] or type(group)~="number" or group~=math.floor(group) or group<0 or group>6 then return end
		if previous~=nil then parts[#parts+1]=group==previous and "-" or " " end
		if group~=previous and groups[group] then return end
		parts[#parts+1], groups[group], previous = color, true, group
	end
	for index in pairs(sockets) do
		if type(index)~="number" or index~=math.floor(index) or index<1 or index>#sockets then return end
	end
	return table.concat(parts)
end

function M.socketCounts(key)
	local total, largest = 0, 0
	for group in key:gmatch("%S+") do
		local _, separators = group:gsub("-","")
		local links = separators+1
		total,largest=total+links,math.max(largest,links)
	end
	return total,largest
end

local function numberValue(value, name)
	if type(value)~="string" or #value>64 then return end
	value=value:gsub(" %(augmented%)$","")
	if name=="Quality" or name=="Critical Strike Chance" or name=="Chance to Block" then
		value=value:gsub("%%$",""):gsub("^%+","")
	elseif name=="Weapon Range" then
		value=value:gsub(" metres$",""):gsub(" metre$","")
	end
	local number = tonumber(value:match("^(%d+%.?%d*)$"))
	if number and number<math.huge then return number end
end

local function rawFields(raw)
	if type(raw)~="string" then return end
	local fields = {}
	for line in raw:gmatch("[^\r\n]+") do
		local name, value = line:match("^([%a ]+): *(.*)$")
		if rawNames[name] then
			if name=="Evasion" then name="Evasion Rating" end
			if fields[name]~=nil then return end
			fields[name]=value
		end
	end
	return fields
end

local function damageRange(weapon, name)
	local low, high = weapon[name.."Min"], weapon[name.."Max"]
	if type(low)=="number" and type(high)=="number" and low>=0 and high>=low and high<math.huge then
		return string.format("%g-%g",low,high)
	end
end

function M.target(item)
	local sockets = socketKey(item.sockets,"color")
	local raw = rawFields(item.raw)
	local quiver = item.type=="Quiver"
	if not raw or sockets==nil then return end
	local printedSockets = quiver and (raw.Sockets or "") or raw.Sockets
	if printedSockets~=sockets then return end
	local quality = 0
	if raw.Quality then quality=numberValue(raw.Quality,"Quality") end
	if not quality or quality~=math.floor(quality) or quality~=(item.quality or 0) then return end
	if quiver then
		if quality~=0 then return end
		for _, name in pairs(defences) do if raw[name] then return end end
		return {sockets=sockets,quality=0,properties={},class="Quiver"}
	end
	local properties = {}
	if item.base.armour then
		for key, name in pairs(defences) do
			if raw[name] then
				properties[name]=numberValue(raw[name])
				if not properties[name] then return end
			elseif (item.base.armour[key.."BaseMin"] or 0)>0 then return end
		end
		if not next(properties) then return end
		if item.base.armour.BlockChance then
			properties["Chance to Block"]=item.armourData and item.armourData.BlockChance
			if type(properties["Chance to Block"])~="number" then return end
		end
	else
		local weapon = item.weaponData and (item.weaponData[1] or item.weaponData[2])
		if not weapon or not weapon.AttackRate or not weapon.CritChance then return end
		properties["Attacks per Second"],properties["Critical Strike Chance"]=weapon.AttackRate,weapon.CritChance
		properties["Physical Damage"],properties["Chaos Damage"]=damageRange(weapon,"Physical"),damageRange(weapon,"Chaos")
		local ranges = {}
		for _, name in ipairs(elemental) do
			local range = damageRange(weapon,name)
			if range then ranges[#ranges+1]=range end
		end
		if #ranges>0 then
			table.sort(ranges)
			properties["Elemental Damage"]=table.concat(ranges,",")
		end
	end
	local weapon = item.weaponData and (item.weaponData[1] or item.weaponData[2])
	local range = weapon and weapon.range
	local weaponType = item.base.weapon and data.weaponTypeInfo[item.base.type]
	-- Thrusting is an internal subtype of One Handed Sword.
	local subtype = item.base.weapon and item.base.subType
	local class = weaponType and weaponType.label or subtype~="Thrusting" and subtype or item.base.type
	return {sockets=sockets,quality=quality,properties=properties,class=class,range=range and range/10}
end

local function propertyValue(values, expected, name)
	if type(values)~="table" or #values==0 or #values>3 then return end
	if type(expected)=="number" and #values~=1 then return end
	for index in pairs(values) do
		if type(index)~="number" or index<1 or index>#values or index~=math.floor(index) then return end
	end
	local ranges = {}
	for _, row in ipairs(values) do
		local text = type(row)=="table" and row[1]
		if type(text)~="string" or #text>64 then return end
		if type(expected)=="number" then
			return numberValue(text,name)
		else
			local low, high = text:match("^(%d+)%s*%-%s*(%d+)$")
			if not low then return end
			ranges[#ranges+1]=low.."-"..high
		end
	end
	table.sort(ranges)
	return table.concat(ranges,",")
end

function M.matches(item, target, links)
	local sockets, properties = item.sockets, item.properties
	if target.class=="Quiver" then
		if sockets==nil then sockets={} end
		if properties==nil then properties={} end
	end
	local key=socketKey(sockets,"sColour")
	if key==nil or type(properties)~="table" then return false end
	if links then
		local count, largest=M.socketCounts(key)
		if count~=M.socketCounts(target.sockets) or links.min and largest<links.min or links.max and largest>links.max then return false end
	elseif key~=target.sockets then return false end
	local seen = {}
	for _, property in ipairs(properties) do
		if type(property)~="table" or type(property.name)~="string" then return false end
		local name=property.name=="Evasion" and "Evasion Rating" or property.name
		if seen[name] then return false end
		seen[name]=true
		local expected=target.properties[name]
		if name=="Quality" then expected=target.quality end
		if name=="Weapon Range" then expected=target.range end
		if expected~=nil then
			if propertyValue(property.values,expected,name)~=expected then return false end
		elseif name~=target.class or type(property.values)~="table" or next(property.values) then return false end
	end
	for index in pairs(properties) do
		if type(index)~="number" or index<1 or index>#properties or index~=math.floor(index) then return false end
	end
	if target.quality>0 and not seen.Quality then return false end
	for name in pairs(target.properties) do if not seen[name] then return false end end
	return true
end

return M
