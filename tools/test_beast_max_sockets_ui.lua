local output=arg[1];arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
 newBuild();main.popups={};local ui=require('Modules.HeadlessUI').install({width=size[1],height=size[2]});ui:bind(build)
 local raw='Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G B'
 local c=require('Classes.CraftingSimulatorControl').Open(build,{id='beast-sockets-ui',title='Bestiary sockets',slot='Body Armour',startingItem=raw,goals={},steps={},preferredMethod='beast_max_sockets'})
 ui:click('settings');ui:text('paletteSearch','Bestiary: maximum sockets');assert(main.popups[1].controls.paletteUse:IsEnabled(),'Bestiary socket craft unavailable')
 if output then ui:frame():write(output..'/'..size[1]..'-beast-max-sockets.json') end
 ui:click('paletteUse');ui:click('item');assert(not main.popups[1].controls.apply:IsEnabled(),'Maximum socket craft remained available at maximum');ui:click('undo');assert(main.popups[1].controls.apply:IsEnabled(),'Undo did not restore craft availability')
 ui:restore();main.popups={}
end
print('BEAST_MAX_SOCKETS_UI_OK')
