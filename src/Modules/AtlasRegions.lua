-- cspell:ignore jsontype
-- Manually maintained 3.30 Shaped Region observations, not account state.
local M={types={"Abyss","Bestiary","Betrayal","Blight","Breach","Expedition","Incursion","Legion","Ritual","Ultimatum"}}
local known={};for _,name in ipairs(M.types) do known[name]=true end
local function array(value,limit,label)
	assert(type(value)=="table" and value~=require("dkjson").null and #value<=limit,"Invalid "..label)
	local meta=getmetatable(value);assert(not meta or meta.__jsontype~="object","Expected an array for "..label)
	for key in pairs(value) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#value,"Invalid "..label) end
	return value
end
local function mapName(value)
	assert(type(value)=="string" and #value<=160 and not value:find("[%c%^]"),"Invalid map name")
	local name=value:match("^%s*(.-)%s*$");assert(name~="","Enter a map name")
	return name
end
function M.validate(regions)
	local result,seen={},{}
	for _,region in ipairs(array(regions,10,"Shaped Regions")) do
		assert(type(region)=="table" and known[region.mechanic] and not seen[region.mechanic],"Choose a different Thread type for each region")
		seen[region.mechanic]=true;local entry={mechanic=region.mechanic,maps={}};local names={}
		for _,map in ipairs(array(region.maps,256,"region maps")) do
			assert(type(map)=="table","Invalid region map");local name=mapName(map.name);local key=name:lower()
			assert(not names[key],"A map appears twice in one region");names[key]=true
			local threads=map.freeThreads;assert(type(threads)=="number" and threads==math.floor(threads) and threads>=0 and threads<=1000,"Enter a non-negative whole free Thread count up to 1000")
			entry.maps[#entry.maps+1]={name=name,freeThreads=threads}
		end
		result[#result+1]=entry
	end
	return result
end
-- Group manually observed maps without assuming that all regions are known.
function M.overview(regions)
	local byName,entries={},{}
	for _,region in ipairs(M.validate(regions)) do for _,map in ipairs(region.maps) do
		local key=map.name:lower();local entry=byName[key]
		if not entry then entry={name=map.name,regions={}};byName[key]=entry;entries[#entries+1]=entry end
		entry.regions[#entry.regions+1]={mechanic=region.mechanic,freeThreads=map.freeThreads}
	end end
	for _,entry in ipairs(entries) do table.sort(entry.regions,function(a,b) return a.mechanic<b.mechanic end) end
	table.sort(entries,function(a,b) return a.name:lower()<b.name:lower() end)
	return entries
end
-- A run removes that map from every tracked overlapping region. Only regions
-- whose objective was completed add one free Thread to their other maps.
function M.complete(regions,name,completed)
	local result=M.validate(regions);name=mapName(name);local key=name:lower();local selected={}
	for _,mechanic in ipairs(array(completed,10,"completed objectives")) do assert(known[mechanic] and not selected[mechanic],"Invalid completed region objective");selected[mechanic]=true end
	local affected={};for _,region in ipairs(result) do for _,map in ipairs(region.maps) do if map.name:lower()==key then affected[region.mechanic]=true end end end
	assert(next(affected),"This map is not in a tracked region")
	for mechanic in pairs(selected) do assert(affected[mechanic],"A completed objective must belong to this map") end
	for _,region in ipairs(result) do if affected[region.mechanic] then
		local remaining={};for _,map in ipairs(region.maps) do if map.name:lower()~=key then
			if selected[region.mechanic] then assert(map.freeThreads<1000,"Free Thread count would exceed the supported limit");map.freeThreads=map.freeThreads+1 end
			remaining[#remaining+1]=map
		end end;region.maps=remaining
	end end
	return result
end
return M
