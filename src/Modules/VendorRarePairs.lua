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
return M
