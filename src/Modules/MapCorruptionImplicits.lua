-- Pinned client data for manually recorded map corruption implicits.
local M={};local data
local function source()
 if not data then local file=assert(io.open("Data/Crafting/MapCorruption330.json","rb"));data=assert(require("dkjson").decode(file:read("*a")));file:close() end
 return data
end
function M.roll(itemLevel,blighted,random)
 assert(type(itemLevel)=="number" and itemLevel==math.floor(itemLevel) and itemLevel>=1 and itemLevel<=100,"Invalid map item level")
 local entries={};local total=0
 for id,entry in pairs(source().entries) do
  local weight=0
  for _,spawn in ipairs(entry.spawnWeights) do if spawn.tag=="default" or spawn.tag=="infected_map" and blighted then weight=spawn.weight;break end end
  if not entry.legacy and itemLevel>=entry.requiredLevel and weight>0 then entries[#entries+1]={id=id,entry=entry,weight=weight};total=total+weight end
 end
 table.sort(entries,function(a,b) return a.id<b.id end)
 assert(total>0,"No supported corruption implicit is available for this map")
 local target=random()*total;local picked
 for _,candidate in ipairs(entries) do target=target-candidate.weight;if target<0 then picked=candidate;break end end
 assert(picked,"Could not select a corruption implicit")
 local stat=picked.entry.stat;return {id=picked.id,value=stat.min+math.floor(random()*(stat.max-stat.min+1))}
end
function M.source() local value=source();return {patch=value.patch,sha256=value.sourceSha256} end
function M.list()
 local result={};for id,entry in pairs(source().entries) do result[#result+1]={id=id,label=entry.text..(entry.legacy and " [legacy]" or "")} end
 table.sort(result,function(a,b) return a.label<b.label end);return result
end
function M.describe(implicit,itemLevel)
 assert(type(implicit)=="table" and type(implicit.id)=="string","Invalid map corruption implicit")
 local entry=assert(source().entries[implicit.id],"Unknown map corruption implicit")
 local stat=entry.stat;local value=implicit.value
 if value~=nil then assert(type(value)=="number" and value==math.floor(value) and value>=stat.min and value<=stat.max,"Implicit value is outside the current source range") end
 local text=entry.text
 if value~=nil and stat.min~=stat.max then text=text:gsub("%(%-?%d+%-%-?%d+%)",tostring(value),1) end
 local notes={"Explicit-only totals exclude this implicit. Estimated totals include supported rarity, pack size and modifier magnitude effects; other effects remain separate."}
 if entry.legacy then notes[#notes+1]="Legacy implicit: it no longer rolls in the pinned 3.30 data." end
 if itemLevel and itemLevel<entry.requiredLevel then notes[#notes+1]="The item level is below the pinned modifier level; verify this item in game." end
 return {id=implicit.id,value=value,text=text,min=stat.min,max=stat.max,legacy=entry.legacy or nil,requiredLevel=entry.requiredLevel,notes=notes}
end
return M
