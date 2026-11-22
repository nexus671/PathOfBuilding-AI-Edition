local output=arg[1];arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local UI=require('Modules.HeadlessUI')
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local p=require('Modules.LootFilters').profile('union-ui','Union UI')
 p.template='Hide\n Class == "Helmets"\nHide\n Class == "Boots"\nShow\n Class == "Helmets" "Boots"'
 local c=require('Classes.LootFilterStructureControl').Open(p);ui:choose('mode','Priority conflicts')
 local function details() local lines={};for _,row in ipairs(c.details.list) do lines[#lines+1]=StripEscapes(row[1] or '') end;return table.concat(lines,' '):gsub('%s+',' ') end
 assert(details():find('collectively',1,true),'Collective conflict was not explained');assert(c.blocking:IsEnabled())
 ui:frame();if output then ui:write(output..'/'..size[1]..'-filter-union.json') end
 ui:click('blocking');assert(details():find('"Helmets"',1,true),'First blocker was not shown');assert(c.blocking:IsEnabled(),'Next blocker was not available')
 ui:click('blocking');assert(details():find('"Boots"',1,true),'Second blocker was not shown');assert(not c.blocking:IsEnabled(),'There should be no later blocker')
 ui:frame();if output then ui:write(output..'/'..size[1]..'-filter-union-blocker.json') end
 ui:click('backConflict');assert(c.mode:GetSelValue()=='Priority conflicts' and details():find('collectively',1,true),'Returning lost the conflict')
 ui:click('close');ui:restore()
end
print('FILTER_UNION_UI_OK')
