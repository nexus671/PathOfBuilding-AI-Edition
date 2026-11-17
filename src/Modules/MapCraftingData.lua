-- Pinned area modifier metadata. This does not model currency outcomes.
local json=require("dkjson")
local M={}
local data

-- The 3.30 patch notes restrict these nine ordinary-map suffixes to rare maps.
local rareOnly={
	MapContainsBeyondDemonFactionWorlds=true,MapContainsBeyondFleshFactionWorlds=true,MapContainsBeyondPaleFactionWorlds=true,
	MapContainsDeliriumMirrorWorlds=true,MapContainsMirageWorlds=true,MapContainsWildwoodWorlds=true,
	MapContainsSentinelApexWorlds=true,MapContainsSentinelPandemoniumWorlds=true,MapContainsSentinelStalkerWorlds=true,
}

function M.source()
	if not data then
		local file=assert(io.open("Data/Crafting/Map330.json","rb"))
		local raw=file:read("*a");file:close()
		data=assert(json.decode(raw))
	end
	return data
end

-- Base metadata includes legacy bases. Callers must verify availability for
-- their chosen patch and add dynamic tier tags from the actual map.
function M.baseTags(id)
	local base=assert(M.source().bases[id],"Unknown map base")
	local tags={};for _,tag in ipairs(base.tags or {}) do tags[tag]=true end
	return tags
end

local function page(entries,offset,limit)
	offset=offset or 0;limit=limit or 30
	assert(type(offset)=="number" and offset==math.floor(offset) and offset>=0 and offset<=#entries,"Invalid result offset")
	assert(type(limit)=="number" and limit==math.floor(limit) and limit>=1 and limit<=100,"Use 1 to 100 results per page")
	local last=math.min(#entries,offset+limit);local result={}
	for i=offset+1,last do result[#result+1]=entries[i] end
	return result,#entries,last<#entries and last or nil
end

function M.searchBases(query,offset,limit,checkpoint)
	assert(type(query)=="string" and #query<=160,"Invalid map search")
	local entries={};local needle=query:lower();local slice=os.clock()
	for id,base in pairs(M.source().bases) do
		if (base.name.." "..id):lower():find(needle,1,true) then
			local tags=M.baseTags(id)
			entries[#entries+1]={id=id,name=base.name,release=base.release_state,legacy=tags.old_map or false,special=tags.map_force_6_mods or false}
		end
		if checkpoint and os.clock()-slice>=0.008 then checkpoint();slice=os.clock() end
	end
	table.sort(entries,function(a,b) return a.name==b.name and a.id<b.id or a.name<b.name end)
	local results,total,nextOffset=page(entries,offset,limit)
	return {results=results,total=total,offset=offset or 0,nextOffset=nextOffset,
		note="The source includes legacy and special bases; release metadata does not establish current availability."}
end

-- Spawn weight rules are ordered; the first matching tag wins, even if its
-- weight is zero. Callers must supply the actual item's complete tag set.
function M.spawnWeight(mod,tags)
	for _,entry in ipairs(mod.spawn_weights or {}) do
		if tags[entry.tag] then return entry.weight,entry.tag end
	end
	return 0
end

function M.candidates(tags,itemLevel,selected,checkpoint)
	assert(type(tags)=="table" and tags.default==true,"Supply the complete tag set, including default")
	assert(type(itemLevel)=="number" and itemLevel==math.floor(itemLevel) and itemLevel>=1 and itemLevel<=100,"Invalid item level")
	local effectiveTags=copyTable(tags);local blocked={};local used={}
	for _,id in ipairs(selected or {}) do
		local mod=assert(M.source().mods[id],"Unknown selected area modifier")
		assert(not used[id],"Duplicate selected area modifier");used[id]=true
		for _,group in ipairs(mod.groups or {}) do blocked[group]=true end
		for _,tag in ipairs(mod.adds_tags or {}) do effectiveTags[tag]=true end
	end
	local result={};local slice=os.clock()
	for id,mod in pairs(M.source().mods) do
		local weight,tag=M.spawnWeight(mod,effectiveTags);local conflict=used[id]
		for _,group in ipairs(mod.groups or {}) do if blocked[group] then conflict=true;break end end
		if not conflict and weight>0 and mod.required_level<=itemLevel then
			result[#result+1]={id=id,name=mod.name,side=mod.generation_type,level=mod.required_level,
				groups=copyTable(mod.groups),stats=copyTable(mod.stats),text=type(mod.text)=="string" and mod.text or "",spawnWeight=weight,matchedTag=tag}
		end
		if checkpoint and os.clock()-slice>=0.008 then checkpoint();slice=os.clock() end
	end
	table.sort(result,function(a,b) return a.id<b.id end)
	return result
end

-- White, yellow and red ordinary maps use the established tier bands. This
-- inspection deliberately does not simulate rolling or claim outcome odds.
function M.inspect(baseId,tier,itemLevel,selected,query,offset,limit,checkpoint,rarity)
	assert(type(tier)=="number" and tier==math.floor(tier) and tier>=1 and tier<=16,"Use an ordinary map tier from 1 to 16")
	rarity=rarity or "rare";assert(rarity=="magic" or rarity=="rare","Use magic or rare map rarity")
	assert(type(selected or {})=="table","Selected modifiers must be a list")
	query=query or "";assert(type(query)=="string" and #query<=160,"Invalid modifier search")
	local base=assert(M.source().bases[baseId],"Unknown map base")
	local tags=M.baseTags(baseId)
	assert(not tags.map_force_6_mods,"Special maps need their own crafting rules")
	for _,tag in ipairs({"low_tier_map","mid_tier_map","top_tier_map","uber_tier_map"}) do tags[tag]=nil end
	tags[tier<=5 and "low_tier_map" or tier<=10 and "mid_tier_map" or "top_tier_map"]=true
	local counts={prefix=0,suffix=0};local groups={}
	for _,id in ipairs(selected or {}) do
		local mod=assert(M.source().mods[id],"Unknown selected area modifier")
		assert(rarity=="rare" or not rareOnly[id],"This modifier can only roll on rare maps")
		counts[mod.generation_type]=counts[mod.generation_type]+1
		assert(counts[mod.generation_type]<=(rarity=="magic" and 1 or 3),"Too many modifiers for this map rarity")
		for _,group in ipairs(mod.groups or {}) do assert(not groups[group],"Selected modifiers share a group");groups[group]=true end
	end
	local result={};for _,entry in ipairs(M.candidates(tags,itemLevel,selected,checkpoint)) do
		if counts[entry.side]<(rarity=="magic" and 1 or 3) and (rarity=="rare" or not rareOnly[entry.id]) and (entry.name.." "..entry.text.." "..entry.id):lower():find(query:lower(),1,true) then result[#result+1]=entry end
	end
	local results,total,nextOffset=page(result,offset,limit)
	return {baseId=baseId,baseName=base.name,tier=tier,itemLevel=itemLevel,rarity=rarity,counts=counts,candidates=results,total=total,offset=offset or 0,nextOffset=nextOffset,
		source=M.source().source,patch=M.source().patch,
		note="Spawn weights are not outcome probabilities. Base availability, map-specific restrictions and game behavior require verification."}
end
return M
