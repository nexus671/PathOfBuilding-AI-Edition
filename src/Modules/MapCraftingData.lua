-- Pinned area modifier metadata. This does not model currency outcomes.
local json=require("dkjson")
local M={}
local data
local nightmareBases={
	["Metadata/Items/Maps/MapWorldsAbomination"]=true,["Metadata/Items/Maps/MapWorldsCitadel"]=true,
	["Metadata/Items/Maps/MapWorldsFortress"]=true,["Metadata/Items/Maps/MapWorldsSanctuary"]=true,
	["Metadata/Items/Maps/MapWorldsZiggurat"]=true,
}
function M.isNightmare(id) return nightmareBases[id] == true end

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
		if checkpoint and os.clock()-slice>=0.002 then checkpoint();slice=os.clock() end
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

function M.candidates(tags,itemLevel,selected,checkpoint,lightweight)
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
			local entry={id=id,name=mod.name,side=mod.generation_type,text=type(mod.text)=="string" and mod.text or "",spawnWeight=weight,matchedTag=tag}
			if not lightweight then entry.level=mod.required_level;entry.groups=copyTable(mod.groups);entry.stats=copyTable(mod.stats) end
			result[#result+1]=entry
		end
		if checkpoint and os.clock()-slice>=0.002 then checkpoint();slice=os.clock() end
	end
	table.sort(result,function(a,b) return a.id<b.id end)
	return result
end

local summaryStats={
	["map_drop_scaling_+%"]={key="atlasDrops",pattern="^([%-]?%d+)%% increased Atlas Drops in this Area$"},
	["map_item_drop_rarity_+%"]={key="rarity",pattern="^([%-]?%d+)%% increased Rarity of Items found in this Area$"},
	["map_pack_size_+%"]={key="packSize",pattern="^([%-]?%d+)%% increased Pack size$"},
}
local function readable(text)
	return (text:gsub("%[[^%]|]+|([^%]]+)%]","%1"):gsub("%[([^%]]+)%]","%1"))
end
-- Sum only explicit modifier contributions, preserving ranges and leaving
-- quality, implicit effects and any other map bonuses outside these totals.
function M.summarize(selected,rolls,implicit,quality)
	local totals={atlasDrops={min=0,max=0},rarity={min=0,max=0},packSize={min=0,max=0}}
	local qualityEffect=require("Modules.MapQuality").effect(quality)
	local qualityTotal=qualityEffect and qualityEffect.supported and (qualityEffect.stat=="rarity" or qualityEffect.stat=="packSize")
	local estimate=(implicit or qualityTotal) and {atlasDrops={min=0,max=0},rarity={min=0,max=0},packSize={min=0,max=0}} or nil
	local rateLow,rateHigh=0,0
	if implicit and implicit.id=="MapCorruptionModEffect" then rateLow=implicit.value or implicit.min;rateHigh=implicit.value or implicit.max end
	local effects={};local rollValues=require("Modules.MapRollValues");local byId=rollValues.validate(selected,rolls,M.source())
	for _,id in ipairs(selected or {}) do
		local mod=assert(M.source().mods[id],"Unknown selected area modifier");local fixed={};local values=byId[id]
		for i,stat in ipairs(mod.stats or {}) do local kind=summaryStats[stat.id];if kind then
			local low,high=values and values[i] or stat.min,values and values[i] or stat.max
			local total=totals[kind.key];total.min=total.min+low;total.max=total.max+high
			if estimate then
				-- The game rounding is unverified. Apply the recorded map implicit
				-- to each explicit stat separately and round down in this estimate.
				local values={low*(100+rateLow)/100,low*(100+rateHigh)/100,high*(100+rateLow)/100,high*(100+rateHigh)/100}
				local target=estimate[kind.key];target.min=target.min+math.floor(math.min(unpack(values)));target.max=target.max+math.floor(math.max(unpack(values)))
			end
			if stat.min==stat.max then fixed[kind.key]=stat.min end
		end end
		local replacements=rollValues.render(mod,values);local sourceLines,counts={},{}
		for line in readable(type(mod.text)=="string" and mod.text or ""):gmatch("[^\r\n]+") do sourceLines[#sourceLines+1]=line;counts[line]=(counts[line] or 0)+1 end
		local lines={};for _,line in ipairs(sourceLines) do
			local combined=false
			for _,kind in pairs(summaryStats) do local n=line:match(kind.pattern);if n and fixed[kind.key]==tonumber(n) then combined=true;break end end
			if not combined then lines[#lines+1]=counts[line]==1 and replacements[line] or line end
		end
		effects[#effects+1]={id=id,name=mod.name,lines=lines,hasValues=values~=nil}
	end
	if implicit then
		local key=implicit.id=="MapCorruptionItemRarity" and "rarity" or implicit.id=="MapCorruptionPackSize" and "packSize"
		if key then local low,high=implicit.value or implicit.min,implicit.value or implicit.max;estimate[key].min=estimate[key].min+low;estimate[key].max=estimate[key].max+high end
	end
	if qualityTotal then local total=estimate[qualityEffect.stat];total.min=total.min+qualityEffect.value;total.max=total.max+qualityEffect.value end
	return {totals=totals,estimatedTotals=estimate,effects=effects,qualityEffect=qualityEffect,note="Only selected explicit modifier contributions; excludes quality, implicit effects and other map bonuses. Unmatched or unsampled lines remain ranges.",
		estimateNote=estimate and ("Estimated explicit and supported recorded implicit and quality bonuses; excludes Atlas passives and other effects. Modifier magnitude uses per-stat rounding down, an unverified assumption. Other implicit effects and legacy Item Quantity are not included."..(qualityEffect and not qualityEffect.supported and " The recorded quality effect is not included." or "")) or nil}
end

-- White, yellow and red ordinary maps use the established tier bands. This
-- inspection deliberately does not simulate rolling or claim outcome odds.
function M.inspect(baseId,tier,itemLevel,selected,query,offset,limit,checkpoint,rarity,rolls,corrupted,implicit,quality,observedEffects,potentialNightmare,candidatesOnly)
	assert(type(tier)=="number" and tier==math.floor(tier) and tier>=1 and tier<=17,"Use a map tier from 1 to 17")
	rarity=rarity or "rare";assert(rarity=="magic" or rarity=="rare","Use magic or rare map rarity")
	assert(corrupted==nil or type(corrupted)=="boolean","Invalid map corruption state")
	assert(not corrupted or rarity=="rare","Corrupted map inspection currently requires a rare map")
	assert(not implicit or corrupted,"A map corruption implicit requires a corrupted map")
	local implicitInfo=implicit and require("Modules.MapCorruptionImplicits").describe(implicit,itemLevel) or nil
	observedEffects=require("Modules.MapObservedEffects").validate(observedEffects)
	local blighted=require("Modules.MapObservedEffects").isBlighted(observedEffects)
	assert(type(selected or {})=="table","Selected modifiers must be a list");selected=selected or {}
	query=query or "";assert(type(query)=="string" and #query<=160,"Invalid modifier search")
	local base=assert(M.source().bases[baseId],"Unknown map base")
	local baseTier=baseId:match("^Metadata/Items/Maps/MapKeyTier(%d+)$")
	assert(not baseTier or tonumber(baseTier)==tier,"The map item's tier must match the selected tier")
	local tags=M.baseTags(baseId)
	local nightmare=M.isNightmare(baseId)
	assert(not tags.map_force_6_mods or nightmare,"Special maps need their own crafting rules")
	assert(nightmare == (tier==17),"Nightmare maps require tier 17; ordinary maps require tier 1 to 16")
	assert(not nightmare or rarity=="rare","Nightmare maps require rare rarity")
	for _,tag in ipairs({"low_tier_map","mid_tier_map","top_tier_map","uber_tier_map"}) do tags[tag]=nil end
	tags[nightmare and "uber_tier_map" or tier<=5 and "low_tier_map" or tier<=10 and "mid_tier_map" or "top_tier_map"]=true
	if nightmare and potentialNightmare then
		-- A target picker needs both the initial and subsequently unlocked pools.
		for _,mod in pairs(M.source().mods) do for _,tag in ipairs(mod.adds_tags or {}) do if tag:match("^has_uber_map_") then tags[tag]=true end end end
	end
	local counts={prefix=0,suffix=0};local groups={}
	assert(#(selected or {})<=(corrupted and 9 or rarity=="magic" and 2 or 6),"Too many modifiers for this map state")
	for _,id in ipairs(selected or {}) do
		local mod=assert(M.source().mods[id],"Unknown selected area modifier")
		assert(rarity=="rare" or not rareOnly[id],"This modifier can only roll on rare maps")
		counts[mod.generation_type]=counts[mod.generation_type]+1
		if not corrupted then assert(counts[mod.generation_type]<=(rarity=="magic" and 1 or 3),"Too many modifiers for this map rarity") end
		for _,group in ipairs(mod.groups or {}) do assert(not groups[group],"Selected modifiers share a group");groups[group]=true end
	end
	local eligible=M.candidates(tags,itemLevel,selected,checkpoint,candidatesOnly)
	if checkpoint then checkpoint() end
	local result={};for _,entry in ipairs(eligible) do
		if (corrupted and #selected<9 or not corrupted and counts[entry.side]<(rarity=="magic" and 1 or 3)) and (rarity=="rare" and not blighted or not rareOnly[entry.id]) and (query=="" or (entry.name.." "..entry.text.." "..entry.id):lower():find(query:lower(),1,true)) then result[#result+1]=entry end
	end
	local results,total,nextOffset=page(result,offset,limit)
	return {baseId=baseId,baseName=base.name,tier=tier,itemLevel=itemLevel,rarity=rarity,nightmare=nightmare or nil,corrupted=corrupted or nil,implicit=implicitInfo,observedEffects=observedEffects,counts=counts,candidates=results,total=total,offset=offset or 0,nextOffset=nextOffset,summary=not candidatesOnly and M.summarize(selected,rolls,implicitInfo,quality) or nil,
		source=M.source().source,patch=M.source().patch,
		note=(nightmare and "Nightmare modifiers can unlock other candidates. Draw order and game restrictions are unverified; simulated Chaos outcomes are experimental. Spawn weights are not probabilities." or corrupted and "Manual inspection only: up to nine explicit modifiers are accepted; per-side corruption limits, base availability and map-specific restrictions are unverified. Spawn weights are not probabilities." or "Spawn weights are not outcome probabilities. Base availability, map-specific restrictions and game behavior require verification.")..require("Modules.MapObservedEffects").note(observedEffects)}
end
return M
