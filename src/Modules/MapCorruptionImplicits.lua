-- Pinned client data for manually recorded map corruption implicits.
local M={};local data
local function source()
 if not data then local file=assert(io.open("Data/Crafting/MapCorruption330.json","rb"));data=assert(require("dkjson").decode(file:read("*a")));file:close() end
 return data
end
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
 local notes={"Corruption implicit is recorded separately; modifier totals exclude its effects."}
 if entry.legacy then notes[#notes+1]="Legacy implicit: it no longer rolls in the pinned 3.30 data." end
 if itemLevel and itemLevel<entry.requiredLevel then notes[#notes+1]="The item level is below the pinned modifier level; verify this item in game." end
 return {id=implicit.id,value=value,text=text,min=stat.min,max=stat.max,legacy=entry.legacy or nil,requiredLevel=entry.requiredLevel,notes=notes}
end
return M
