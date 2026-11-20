-- Review copied items only; no stash access or currency transaction.
local M={maxBytes=4*1024*1024}
local function clean(value) return (value:gsub("^%s+",""):gsub("%s+$","")) end
local function groupByQuality(items)
	local groups,group,total={}, {},0
	for _,item in ipairs(items) do
		group[#group+1]=item;total=total+item.quality
		if #group>=2 and total>=40 then groups[#groups+1]={items=group,quality=total};group={};total=0 end
	end
	return groups,group,total
end
-- Search small collections exactly, with a fixed work budget. Larger or hard
-- inputs keep the linear heuristic; no item is rejected because of its count.
local function bestGroups(items)
	local greedy,leftover,leftoverQuality=groupByQuality(items)
	local total=0;for _,item in ipairs(items) do total=total+item.quality end
	if #greedy==math.min(math.floor(total/40),math.floor(#items/2)) then return greedy,leftover,leftoverQuality,true end
	if #items>14 then return greedy,leftover,leftoverQuality,false end
	local bit=require("bit");local band=bit.band;local size=2^#items;local sums,counts,minimum,positions={[0]=0},{[0]=0},{},{}
	for i=1,#items do positions[2^(i-1)]=i end
	for mask=1,size-1 do
		local first=band(mask,-mask);local prior=mask-first;local q=items[positions[first]].quality
		sums[mask]=sums[prior]+q;counts[mask]=counts[prior]+1;minimum[mask]=math.min(minimum[prior] or q,q)
	end
	local best,choice={[0]=0},{};local work,aborted=0,false
	local function solve(mask)
		if best[mask]~=nil then return best[mask] end
		local upper=math.min(math.floor(sums[mask]/40),math.floor(counts[mask]/2))
		if upper==0 then best[mask]=0;choice[mask]=0;return 0 end
		local first=band(mask,-mask);local value,selected=0,0;local sub=mask
		while sub>0 do
			work=work+1;if work>100000 then aborted=true;return 0 end
			if band(sub,first)~=0 and counts[sub]>=2 and sums[sub]>=40 and (counts[sub]==2 or sums[sub]-minimum[sub]<40) then
				local candidate=1+solve(mask-sub);if aborted then return 0 end
				if candidate>value then value,selected=candidate,sub end
				if value==upper then break end
			end
			sub=band(sub-1,mask)
		end
		if value<upper then local without=solve(mask-first);if aborted then return 0 end;if without>value then value,selected=without,0 end end
		best[mask]=value;choice[mask]=selected;return value
	end
	local mask=size-1;solve(mask);if aborted then return greedy,leftover,leftoverQuality,false end
	local groups,remaining,remainingQuality={},{},0
	while mask>0 do
		if best[mask]==0 then for i,item in ipairs(items) do if band(mask,2^(i-1))~=0 then remaining[#remaining+1]=item;remainingQuality=remainingQuality+item.quality end end;break end
		local selected=choice[mask]
		if selected==0 then local first=band(mask,-mask);local item=items[positions[first]];remaining[#remaining+1]=item;remainingQuality=remainingQuality+item.quality;mask=mask-first
		else local group={};for i,item in ipairs(items) do if band(selected,2^(i-1))~=0 then group[#group+1]=item end end;groups[#groups+1]={items=group,quality=sums[selected]};mask=mask-selected end
	end
	return groups,remaining,remainingQuality,true
end
function M.parse(raw)
	assert(type(raw)=="string" and #raw>0 and #raw<=24000 and not raw:find("%z"),"Paste one copied item up to 24 KiB")
	raw=raw:gsub("\r\n","\n"):gsub("\r","\n")
	local lines={};for line in (raw.."\n"):gmatch("([^\n]*)\n") do line=clean(line);if line~="" then lines[#lines+1]=line end end
	local class=lines[1] and lines[1]:match("^Item Class:%s*(.+)$")
	local kind=require("Modules.LootFilterCampaign").qualityCategory(class)
	local flaskClasses={ ["Life Flasks"]=true,["Mana Flasks"]=true,["Hybrid Flasks"]=true,["Utility Flasks"]=true,["Critical Utility Flasks"]=true,["Tinctures"]=true }
	local category=kind=="Quality weapon" and "Weapons" or kind=="Quality armour" and "Armour" or flaskClasses[class] and "Flasks and tinctures" or (class=="Skill Gems" or class=="Support Gems") and "Gems"
	assert(category,"Copy a weapon, armour, flask, tincture or gem with its item class")
	local rarity=lines[2] and lines[2]:match("^Rarity:%s*(%a+)$")
	assert(category=="Gems" and rarity=="Gem" or category~="Gems" and rarity and ({Normal=true,Magic=true,Rare=true,Unique=true})[rarity],"The copied item needs a supported rarity")
	-- Magic items normally have one displayed name, including their affixes.
	-- Unidentified rare or unique items can also have a single name line.
	-- Keep that visible name for review without guessing the underlying base.
	local function property(line)
		return line and (line:match("^Quality[:%s%(]") or line:match("^Item Level:") or line:match("^Sockets:") or line:match("^Requirements:"))
	end
	local endOfName=lines[4]=="--------" or property(lines[4])
	local singleName=endOfName and (rarity=="Magic" or (rarity=="Rare" or rarity=="Unique") and (raw:match("\nUnidentified\n") or raw:match("\nUnidentified %(Tier %d+%)\n") or raw:match("\nUnidentified$") or raw:match("\nUnidentified %(Tier %d+%)$")))
	local base=lines[(rarity=="Normal" or rarity=="Gem" or singleName) and 3 or 4]
	assert(base and base~="--------" and not property(base) and #base<=160 and not base:find("[%c%^]"),"The copied item needs a visible base type")
	local quality
	for _,line in ipairs(lines) do
		local value=line:match("^Quality:%s*%+?(%d+)%%") or line:match("^Quality %([^%)]+%):%s*%+?(%d+)%%")
		if value then assert(not quality,"Copied item has multiple quality values");quality=tonumber(value) end
	end
	assert(quality and quality>=1 and quality<=100,"The copied item needs quality between 1% and 100%")
	return {base=base,class=class,rarity=rarity,quality=quality,category=category}
end
function M.review(items)
	assert(type(items)=="table","Supply copied items")
	for index in pairs(items) do assert(type(index)=="number" and index==math.floor(index) and index>=1 and index<=#items,"Copied items must be an array") end
	local categories={{name="Weapons",reward="Blacksmith's Whetstone",items={},groups={},leftover={}},{name="Armour",reward="Armourer's Scrap",items={},groups={},leftover={}},{name="Flasks and tinctures",reward="Glassblower's Bauble",items={},groups={},leftover={}},{name="Gems",reward="Gemcutter's Prism",items={},groups={},leftover={}}}
	local byName={};for _,category in ipairs(categories) do byName[category.name]=category end;local bytes=0
	for index,raw in ipairs(items) do
		assert(type(raw)=="string","Item "..index.." must be copied item text");bytes=bytes+#raw;assert(bytes<=M.maxBytes,"Copied items exceed the 4 MiB review limit")
		local ok,item=pcall(M.parse,raw);assert(ok,"Item "..index..": "..tostring(item));item.index=index
		local category=byName[item.category];category.items[#category.items+1]=item
	end
	for _,category in ipairs(categories) do
		local rest={}
		for _,item in ipairs(category.items) do
			if category.name=="Gems" and item.quality>20 then category.eligibilityUncertain=true end
			if item.rarity=="Normal" and item.quality>=20 or category.name=="Gems" and item.quality==20 then category.groups[#category.groups+1]={items={item},quality=item.quality,single=true,singleKind=category.name=="Gems" and "gem" or "normal"}
			else rest[#rest+1]=item end
		end
		table.sort(rest,function(a,b) if a.quality~=b.quality then return a.quality>b.quality end return a.index<b.index end)
		local groups,leftover,leftoverQuality,optimal=bestGroups(rest)
		for _,group in ipairs(groups) do category.groups[#category.groups+1]=group end
		category.leftover=leftover;category.leftoverQuality=leftoverQuality;category.optimal=optimal and not category.eligibilityUncertain
	end
	return {categories=categories,totalItems=#items,note="Optimal counts are proven for the modeled recipe and supplied quality values when marked; otherwise groups are suggestions. Single-item offers for gems above 20% are unverified. Each paste must be a different item. Check eligibility and the actual vendor offer; this does not read your stash."}
end
return M
