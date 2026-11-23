local output=arg[1];arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local raw='Item Class: Helmets\nRarity: Rare\nVortex Visage\nIron Hat\n--------\nItem Level: 80'
local vendor=require('Modules.VendorRarePairs');local list={raw,raw,raw,raw}
local e=vendor.review(list);assert(e.groups[1].exalted==1 and e.groups[1].remaining==1 and #e.groups[1].trades[1].itemIndices==3)
local c=vendor.review(list,'chaos');assert(c.groups[1].chaos==2 and c.groups[1].remaining==0 and c.groups[1].trades[2].itemIndices[2]==4)
assert(not pcall(vendor.review,list,'invalid'),'Invalid priority was accepted')
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
 newBuild();main.popups={};local ui=require('Modules.HeadlessUI').install({width=size[1],height=size[2]});ui:bind(build)
 local controls=require('Classes.VendorRarePairsControl').Open(build)
 for _=1,4 do ui.clipboard=raw;ui:click('paste') end
 ui:choose('preference','chaos','val');assert(build.planningVendorRarePreference=='chaos')
 local lines={};for _,row in ipairs(controls.details.list) do lines[#lines+1]=row[1] or '' end
 local summary=table.concat(lines,' ');assert(summary:find('2 Chaos',1,true) and summary:find('Chaos Orb #2',1,true),'Trade assignment is not displayed')
 if output then ui:frame():write(output..'/'..size[1]..'-same-name-choice.json') end
 ui:click('close');local reopened=require('Classes.VendorRarePairsControl').Open(build);assert(reopened.preference:GetSelValueByKey('val')=='chaos','Priority was not retained in this build')
 newBuild();assert(not build.planningVendorRarePreference,'Priority leaked to another build');ui:restore();main.popups={}
end
print('SAME_NAME_CHOICE_OK')
