arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true;newBuild()
local function item(class,level) return 'Item Class: '..class..'\nRarity: Rare\nExample Base\n--------\nItem Level: '..level..'\n--------\nUnidentified' end
local input={};for n=1,2 do for _,class in ipairs({'Helmets','Body Armours','Gloves','Boots','Amulets','Belts','Rings','Rings','Bows'}) do input[#input+1]=item(class,80) end end
for _,class in ipairs({'One Hand Swords','Shields','Shields'}) do input[#input+1]=item(class,70) end
local result=require('Modules.VendorRarePairs').reviewSets(input,'chaos');assert(#result.groups==1 and result.maxSetsUpperBound==1 and result.maximumProven,'Two low weapons were incorrectly counted as two Chaos sets')
build.planningVendorRareSetItems=input;build.planningVendorRareSetPreference='chaos'
local ui=require('Modules.HeadlessUI').install({width=960,height=640});ui:bind(build);local c=require('Classes.VendorRareSetsControl').Open(build)
local text={};for _,row in ipairs(c.details.list) do text[#text+1]=row[1] or '' end
assert(table.concat(text,' '):find('Maximum set count',1,true),'The review did not display the proven maximum');ui:restore();main.popups={}
print('VENDOR_CHAOS_BOUND_OK')
