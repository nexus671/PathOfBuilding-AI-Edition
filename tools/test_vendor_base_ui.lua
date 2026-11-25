local output=arg[1];arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local UI=require('Modules.HeadlessUI')
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});build.viewMode='ITEMS';ui:bind(build)
 local c=require('Classes.VendorBaseSetsControl').Open(build);ui:frame();if output then ui:write(output..'/'..size[1]..'-base-empty.json') end
 for _,raw in ipairs({'Rarity: Normal\nJade Amulet','Rarity: Magic\nJade Amulet of the Lynx','Rarity: Rare\nDoom Beads\nJade Amulet','Rarity: Unique\nKarui Ward\nJade Amulet'}) do ui.clipboard='Item Class: Amulets\n'..raw..'\n--------\nItem Level: 60';ui:click('paste') end
 assert(#c.entries.list==2 and c.entries.list[2][3]:find('1',1,true),'Set was not shown')
 local names={};for _,row in ipairs(c.details.list) do names[#names+1]=row[1] or '' end;assert(table.concat(names,' '):find('Karui Ward',1,true),'Item names were not shown')
 ui:frame();if output then ui:write(output..'/'..size[1]..'-base-complete.json') end
 ui:click('remove');assert(c.entries.list[2][3]:find('0',1,true));ui:click('undo');assert(c.entries.list[2][3]:find('1',1,true))
 ui.clipboard='Rarity: Normal\nImaginary Base\n--------';ui:click('paste');assert(c.status.label:find('^1',1,true) and #c.entries.list==2,'Invalid paste changed the review')
 ui:click('clear');assert(#c.entries.list==1);ui:click('undo');assert(#c.entries.list==2);ui:click('undo');assert(#c.entries.list==1);ui:click('undo');ui:click('close')
 c=require('Classes.VendorBaseSetsControl').Open(build);assert(c.status.label:find('4 pasted',1,true));ui:click('close');ui:restore()
end
print('VENDOR_BASE_UI_OK')
