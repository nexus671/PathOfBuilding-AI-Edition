local output=arg[1];arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local UI=require('Modules.HeadlessUI')
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 for _,jewel in ipairs({1,4,11}) do
  newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});build.viewMode='TREE';ui:bind(build)
  build.timelessData.jewelType={id=jewel};build.timelessData.conquerorType={};build.timelessData.jewelSocket={id=26196};build.treeTab:FindTimelessJewel()
  local p=assert(main.popups[1]);assert(p.width<=size[1]-24,'Timeless dialog exceeds the window')
  local c=p.controls;c.fallbackWeightsList:SelByValue('Life','stat');assert(c.fallbackWeightsList:GetSelValue().stat=='Life')
  ui:frame()
  if jewel==4 then
   local left=c.conquerorSelect:GetPos();local width=c.conquerorSelect:GetSize();local right=c.devotionSelect1:GetPos()
   assert(right>=left+width,'Devotion selection overlaps the conqueror selection')
   left=c.socketSelect:GetPos();width=c.socketSelect:GetSize();right=c.devotionSelect2:GetPos()
   assert(right>=left+width,'Devotion selection overlaps the socket selection')
  end
  if output then ui:write(output..'/'..size[1]..'-timeless-'..jewel..'.json') end
  if jewel==11 then
   ui:click('searchListFallbackButton');ui:frame();assert(c.searchListFallback.shown)
   local sawHelp=false
   for _,command in ipairs(ui.commands) do
    if command.kind=='text' and command.text and command.text:find('Fallback weights apply',1,true) then
     sawHelp=true;assert(command.x>=0 and command.x+command.width<=size[1],'Fallback help is clipped')
    end
   end
   assert(sawHelp,'Fallback help was not displayed')
   if output then ui:write(output..'/'..size[1]..'-timeless-help.json') end
  end
  ui:click('closeButton');ui:restore()
 end
end
print('TIMELESS_DIALOG_UI_OK')
