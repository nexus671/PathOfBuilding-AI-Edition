-- Compare user-supplied identified rare item names; does not access the stash.
local M={maxBytes=4*1024*1024}
local function clean(line)
 return (line:gsub("^%s+",""):gsub("%s+$",""))
end
function M.parse(raw)
 assert(type(raw)=="string" and #raw>0 and #raw<=24000 and not raw:find("%z"),"Paste one copied item up to 24 KiB")
 raw=raw:gsub("\r\n","\n"):gsub("\r","\n")
 local lines={};for line in (raw.."\n"):gmatch("([^\n]*)\n") do line=clean(line);if line~="" then lines[#lines+1]=line end end
 local index=1;if lines[index] and lines[index]:match("^Item Class:") then index=index+1 end
 assert(lines[index] and lines[index]:lower()=="rarity: rare","Only identified rare items can be compared")
 for _,line in ipairs(lines) do assert(line~="Unidentified" and not line:match("^Unidentified %(Tier %d+%)$"),"Identify the item before comparing its name") end
 local name,base=lines[index+1],lines[index+2]
 assert(name and base and name~="--------" and base~="--------" and #name<=120 and #base<=160 and not name:find("[%c%^]") and not base:find("[%c%^]"),"The copied rare item needs a visible name and base")
 return {name=name,base=base}
end
function M.review(items)
 assert(type(items)=="table","Supply copied rare items")
 local groups,totalBytes={},0;for index,raw in ipairs(items) do
  assert(type(raw)=="string","Item "..index.." must be copied item text")
  totalBytes=totalBytes+#raw;assert(totalBytes<=M.maxBytes,"Copied items exceed the 4 MiB review limit")
  local ok,item=pcall(M.parse,raw);assert(ok,"Item "..index..": "..tostring(item))
  local group=groups[item.name] or {name=item.name,count=0,items={}}
  group.count=group.count+1;group.items[#group.items+1]={index=index,base=item.base};groups[item.name]=group
 end
 local result={};for _,group in pairs(groups) do
  group.exalted=math.floor(group.count/3);group.chaos=math.floor((group.count%3)/2);group.remaining=group.count%3%2
  result[#result+1]=group
 end
 table.sort(result,function(a,b) if a.count~=b.count then return a.count>b.count end return a.name<b.name end)
 return {groups=result,totalItems=#items,note="Name matches only. Counts assume each paste is a different item; verify item eligibility and the vendor offer in game. No stash is read or changed."}
end
-- A full set is assembled from copied item classes and item levels only.
-- The result is a suggestion, not proof that the game will accept a trade.
local setClasses={
 ["Helmets"]="Helmet",["Body Armours"]="Body Armour",["Gloves"]="Gloves",["Boots"]="Boots",
 ["Amulets"]="Amulet",["Belts"]="Belt",["Rings"]="Ring",["Shields"]="Shield",
 ["Claws"]="One hand",["Daggers"]="One hand",["Rune Daggers"]="One hand",["One Hand Axes"]="One hand",
 ["One Hand Maces"]="One hand",["One Hand Swords"]="One hand",["Thrusting One Hand Swords"]="One hand",
 ["Sceptres"]="One hand",["Wands"]="One hand",["Bows"]="Two hand",["Staves"]="Two hand",
 ["Warstaves"]="Two hand",["Two Hand Axes"]="Two hand",["Two Hand Maces"]="Two hand",["Two Hand Swords"]="Two hand",
}
local setSlots={"Helmet","Body Armour","Gloves","Boots","Amulet","Belt","Ring"}
function M.parseSet(raw)
 assert(type(raw)=="string" and #raw>0 and #raw<=24000 and not raw:find("%z"),"Paste one copied item up to 24 KiB")
 raw=raw:gsub("\r\n","\n"):gsub("\r","\n")
 local lines={};for line in (raw.."\n"):gmatch("([^\n]*)\n") do line=clean(line);if line~="" then lines[#lines+1]=line end end
 local class=lines[1] and lines[1]:match("^Item Class:%s*(.+)$");local slot=setClasses[class]
 assert(slot,"Copy a supported rare equipment item with its item class")
 assert(lines[2] and lines[2]:lower()=="rarity: rare","Only rare equipment can be used in a rare set")
 local unidentified,level,quality=false,nil,0
 for _,line in ipairs(lines) do
  if line=="Unidentified" or line:match("^Unidentified %(Tier %d+%)$") then unidentified=true end
  local v=line:match("^Item Level:%s*(%d+)$");if v then assert(not level,"Copied item has multiple item levels");level=tonumber(v) end
  local q=line:match("^Quality:%s*%+?(%d+)%%") or line:match("^Quality %([^%)]+%):%s*%+?(%d+)%%");if q then quality=tonumber(q) end
 end
 assert(level and level>=1 and level<=100,"The copied item needs an item level from 1 to 100")
 local base=lines[unidentified and 3 or 4];assert(base and base~="--------" and #base<=160 and not base:find("[%c%^]"),"The copied rare item needs a visible base type")
 return {base=base,class=class,slot=slot,level=level,quality=quality,unidentified=unidentified}
end
function M.reviewSets(items,preference)
 preference=preference or "highest";assert(preference=="highest" or preference=="chaos","Choose highest item level or Chaos Orb sets")
 assert(type(items)=="table","Supply copied rare items")
 for index in pairs(items) do assert(type(index)=="number" and index==math.floor(index) and index>=1 and index<=#items,"Copied items must be an array") end
 local buckets={};for _,slot in ipairs(setSlots) do buckets[slot]={} end;buckets["One hand"]={};buckets["Two hand"]={};buckets.Shield={}
 local bytes=0;local excluded={}
 for index,raw in ipairs(items) do
  assert(type(raw)=="string","Item "..index.." must be copied item text");bytes=bytes+#raw;assert(bytes<=M.maxBytes,"Copied items exceed the 4 MiB review limit")
  local ok,item=pcall(M.parseSet,raw);assert(ok,"Item "..index..": "..tostring(item));item.index=index
  if preference=="chaos" and item.level<60 then excluded[#excluded+1]=item else buckets[item.slot][#buckets[item.slot]+1]=item end
 end
 -- Use high-level items first to avoid spending a low-level item in a set
 -- when a higher-level alternative is available. This is not a value optimizer.
 for _,bucket in pairs(buckets) do table.sort(bucket,function(a,b) if a.level~=b.level then return a.level<b.level end return a.index>b.index end) end
 local groups={}
 local function findAnchor(includeUnusable)
  local selected
  for _,slot in ipairs({"Helmet","Body Armour","Gloves","Boots","Amulet","Belt","Ring","Two hand","One hand","Shield"}) do
   local bucket=buckets[slot];local low,high=1,#bucket
   while low<=high do local mid=math.floor((low+high)/2);if bucket[mid].level<=74 then low=mid+1 else high=mid-1 end end
   local candidate=bucket[high]
   local usable=includeUnusable or slot~="One hand" and slot~="Shield" or #buckets["One hand"]+#buckets.Shield>=2
   if candidate and usable and (not selected or candidate.level>selected.level) then selected=candidate end
  end
  return selected
 end
 while true do
  local possible=math.huge
  for _,slot in ipairs(setSlots) do possible=math.min(possible,math.floor(#buckets[slot]/(slot=="Ring" and 2 or 1))) end
  local two,one,shields=#buckets["Two hand"],#buckets["One hand"],#buckets.Shield
  possible=math.min(possible,two+math.floor((one+shields)/2))
  if possible==0 then break end
  local anchor=preference=="chaos" and findAnchor() or nil
  if preference=="chaos" and not anchor then break end
  -- Prefer the highest-level weapon combination that leaves enough equipment
  -- for the remaining possible sets. Two shields are a historical recipe
  -- option; its current eligibility still needs confirmation in game.
  local choice,score
  local function consider(first,second,twos,ones,shieldCount)
   if two-twos+math.floor((one-ones+shields-shieldCount)/2)<possible-1 then return end
   local firstItem=buckets[first][#buckets[first]]
   local secondItem=second and buckets[second][#buckets[second]-(first==second and 1 or 0)]
   if not firstItem or second and not secondItem then return end
   local level=secondItem and math.min(firstItem.level,secondItem.level) or firstItem.level
   if not score or level>score then score=level;choice={first,second} end
  end
  consider("Two hand",nil,1,0,0)
  if one>=1 and shields>=1 then consider("One hand","Shield",0,1,1) end
  if one>=2 then consider("One hand","One hand",0,2,0) end
  if shields>=2 then consider("Shield","Shield",0,0,2) end
  assert(choice,"Could not assemble the suggested weapon slots")
  if anchor and (anchor.slot=="Two hand" or anchor.slot=="One hand" or anchor.slot=="Shield") then
   if anchor.slot=="Two hand" then choice={"Two hand"}
   else
    local other,best
    for _,slot in ipairs({"One hand","Shield"}) do
     local bucket=buckets[slot];local candidate=bucket[#bucket]
     if candidate==anchor then candidate=bucket[#bucket-1] end
     if candidate and (not best or candidate.level>best.level) then other,best=slot,candidate end
    end
    assert(other,"Could not complete the suggested one-hand slots");choice={anchor.slot,other}
   end
  end
  local group={items={},minLevel=100,unidentified=true,quality20=true}
  local function take(slot)
   local position=#buckets[slot]
   if anchor and anchor.slot==slot then
    for i,entry in ipairs(buckets[slot]) do if entry.index==anchor.index then position=i;break end end
    anchor=nil
   end
   local item=table.remove(buckets[slot],position);group.items[#group.items+1]=item;group.minLevel=math.min(group.minLevel,item.level)
   group.unidentified=group.unidentified and item.unidentified;group.quality20=group.quality20 and item.quality>=20
  end
  for _,slot in ipairs(setSlots) do take(slot);if slot=="Ring" then take(slot) end end
  take(choice[1]);if choice[2] then take(choice[2]) end
  group.reward=group.minLevel<60 and "Orb of Alchemy" or group.minLevel<75 and "Chaos Orb" or "Regal Orb"
  groups[#groups+1]=group
 end
 local remaining=excluded;for _,bucket in pairs(buckets) do for _,item in ipairs(bucket) do remaining[#remaining+1]=item end end;table.sort(remaining,function(a,b) return a.index<b.index end)
 -- Progress is based only on unused copies, so an item already assigned to a
 -- set cannot also appear to satisfy the next one.
 local missing={}
 for _,slot in ipairs(setSlots) do local needed=(slot=="Ring" and 2 or 1)-#buckets[slot];if needed>0 then missing[#missing+1]={slot=slot,count=needed} end end
 if #buckets["Two hand"]==0 then
  local one,shields=#buckets["One hand"],#buckets.Shield
  if one+shields==0 then missing[#missing+1]={slot="Weapon",count=1,detail="Two-handed weapon, or two one-handed weapons or shields"}
  elseif one+shields<2 then missing[#missing+1]={slot="Weapon or shield",count=1,detail="Another one-handed weapon or shield; a two-handed weapon also works"} end
 end
 if preference=="chaos" then
  if not findAnchor(true) then missing[#missing+1]={slot="Item level 60-74",count=1}
  elseif not findAnchor() and #buckets["Two hand"]>0 then
   missing[#missing+1]={slot="Chaos-level item or weapon partner",count=1,detail="Use another level 60-74 item, or pair the existing one-handed item with another one-handed weapon or shield"}
  end
 end
 return {preference=preference,groups=groups,remaining=remaining,missing=missing,totalItems=#items,note=(preference=="chaos" and "Chaos grouping is heuristic and may not maximize the number of sets. " or "").."Suggested groups use copied classes and item levels. Weapon combinations, identification and quality bonuses, special items and vendor priority need in-game verification. Each paste must be a different item; no stash is accessed."}
end
return M
