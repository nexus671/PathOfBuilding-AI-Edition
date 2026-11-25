-- Count bundled unique-item range shapes without reading or changing a build.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local entries,names,rangeLines,multiLines,variantEntries=0,{},0,0,0
local entriesWithRanges=0
for _,group in pairs(data.uniques or {}) do for _,raw in ipairs(group) do
 entries=entries+1
 local name=raw:match("^%s*([^\r\n]+)");if name then names[name]=(names[name] or 0)+1 end
 local found=false
 for line in raw:gmatch("[^\r\n]+") do
  local ranges=0;for _ in line:gmatch("%(%-?[%d%.]+%-%-?[%d%.]+%)") do ranges=ranges+1 end
  if ranges>0 then found=true;rangeLines=rangeLines+1;if ranges>1 then multiLines=multiLines+1 end end
 end
 if found then entriesWithRanges=entriesWithRanges+1 end
 if raw:find("Variant:",1,true) or raw:find("{variant:",1,true) then variantEntries=variantEntries+1 end
end end
local distinct,repeated=0,0;for _,count in pairs(names) do distinct=distinct+1;if count>1 then repeated=repeated+1 end end
print("UNIQUE_RANGE_AUDIT "..require("dkjson").encode({entries=entries,distinctNames=distinct,repeatedNames=repeated,entriesWithRanges=entriesWithRanges,rangeLines=rangeLines,multipleRangesOnLine=multiLines,entriesWithVariants=variantEntries,limitations="Counts bundled text shapes only; does not prove live Divine Orb behavior, identity matching, roll independence or current game data."}))
