-- Review copied items only; no stash access or currency transaction.
local M={maxBytes=4*1024*1024}
local function clean(value) return (value:gsub("^%s+",""):gsub("%s+$","")) end
function M.parse(raw)
	assert(type(raw)=="string" and #raw>0 and #raw<=24000 and not raw:find("%z"),"Paste one copied item up to 24 KiB")
	raw=raw:gsub("\r\n","\n"):gsub("\r","\n")
	local lines={};for line in (raw.."\n"):gmatch("([^\n]*)\n") do line=clean(line);if line~="" then lines[#lines+1]=line end end
	local class=lines[1] and lines[1]:match("^Item Class:%s*(.+)$")
	local kind=require("Modules.LootFilterCampaign").qualityCategory(class)
	assert(kind,"Copy a weapon, armour or shield with its item class")
	local rarity=lines[2] and lines[2]:match("^Rarity:%s*(%a+)$")
	assert(rarity and ({Normal=true,Magic=true,Rare=true,Unique=true})[rarity],"The copied item needs a supported rarity")
	local base=lines[rarity=="Normal" and 3 or 4]
	assert(base and base~="--------" and #base<=160 and not base:find("[%c%^]"),"The copied item needs a visible base type")
	local quality
	for _,line in ipairs(lines) do
		local value=line:match("^Quality:%s*%+?(%d+)%%") or line:match("^Quality %([^%)]+%):%s*%+?(%d+)%%")
		if value then assert(not quality,"Copied item has multiple quality values");quality=tonumber(value) end
	end
	assert(quality and quality>=1 and quality<=100,"The copied item needs quality between 1% and 100%")
	return {base=base,class=class,rarity=rarity,quality=quality,category=kind=="Quality weapon" and "Weapons" or "Armour"}
end
function M.review(items)
	assert(type(items)=="table","Supply copied items")
	for index in pairs(items) do assert(type(index)=="number" and index==math.floor(index) and index>=1 and index<=#items,"Copied items must be an array") end
	local categories={{name="Weapons",reward="Blacksmith's Whetstone",items={},groups={},leftover={}},{name="Armour",reward="Armourer's Scrap",items={},groups={},leftover={}}}
	local byName={Weapons=categories[1],Armour=categories[2]};local bytes=0
	for index,raw in ipairs(items) do
		assert(type(raw)=="string","Item "..index.." must be copied item text");bytes=bytes+#raw;assert(bytes<=M.maxBytes,"Copied items exceed the 4 MiB review limit")
		local ok,item=pcall(M.parse,raw);assert(ok,"Item "..index..": "..tostring(item));item.index=index
		local category=byName[item.category];category.items[#category.items+1]=item
	end
	for _,category in ipairs(categories) do
		local rest={}
		for _,item in ipairs(category.items) do
			if item.rarity=="Normal" and item.quality>=20 then category.groups[#category.groups+1]={items={item},quality=item.quality,single=true}
			else rest[#rest+1]=item end
		end
		table.sort(rest,function(a,b) if a.quality~=b.quality then return a.quality>b.quality end return a.index<b.index end)
		local group,total={},0
		for _,item in ipairs(rest) do
			group[#group+1]=item;total=total+item.quality
			if #group>=2 and total>=40 then category.groups[#category.groups+1]={items=group,quality=total};group={};total=0 end
		end
		category.leftover=group;category.leftoverQuality=total
	end
	return {categories=categories,totalItems=#items,note="Suggested groups use a simple high-quality-first order, not an optimal packing. Each paste must be a different item. Check eligibility and the actual vendor offer; this does not read your stash."}
end
return M
