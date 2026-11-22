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
   if size[1]==960 then
    local manual='abyss_special_notable_17, 4, 0, 0'
    c.searchListFallback:SetText(manual,true);assert(build.timelessData.searchListFallback==manual)
    assert(not c.fallbackWeightsUndo:IsEnabled())
    ui:click('fallbackWeightsButton');local generated=build.timelessData.searchListFallback
    assert(generated~=manual and c.fallbackWeightsUndo:IsEnabled(),'Generate did not retain the previous list')
    ui:click('fallbackWeightsUndo');assert(build.timelessData.searchListFallback==manual,'Undo did not restore the original list')
    ui:frame();local sawUndoHelp=false
    for _,command in ipairs(ui.commands) do
     if command.kind=='text' and command.text and command.text:find('Restore lists changed',1,true) then
      sawUndoHelp=true;assert(command.x>=0 and command.x+command.width<=size[1],'Undo help is clipped')
     end
    end
    assert(sawUndoHelp,'Undo help was not displayed')
    if output then ui:write(output..'/'..size[1]..'-timeless-undo.json') end
    ui:click('fallbackWeightsUndo');assert(build.timelessData.searchListFallback==generated,'Redo did not restore generated weights')
    local edited=generated..'\nabyss_special_notable_17, 9, 0, 0'
    c.searchListFallback:SetText(edited,true);ui:click('fallbackWeightsUndo');assert(build.timelessData.searchListFallback==manual)
    ui:click('fallbackWeightsUndo');assert(build.timelessData.searchListFallback==edited,'Redo lost edits made after generation')
    local desired='abyss_special_notable_17, 3, 0, 0';c.searchList:SetText(desired,true)
    ui:choose('jewelSelect',4,'id');assert(not c.fallbackWeightsUndo:IsEnabled(),'Undo should not apply to another jewel type')
    assert(build.timelessData.searchList=='' and build.timelessData.searchListFallback=='')
    local other='templar_devotion_node, 2, 0, 0';c.searchListFallback:SetText(other,true)
    ui:click('fallbackWeightsButton');assert(c.fallbackWeightsUndo:IsEnabled())
    ui:click('fallbackWeightsUndo');assert(build.timelessData.searchListFallback==other)
    ui:choose('jewelSelect',11,'id')
    assert(build.timelessData.searchList==desired and build.timelessData.searchListFallback==edited,'Switching jewel types lost the first draft')
    assert(c.fallbackWeightsUndo:IsEnabled())
    ui:choose('jewelSelect',4,'id');assert(build.timelessData.searchListFallback==other and c.fallbackWeightsUndo:IsEnabled(),'Switching jewel types lost the second draft or history')
    ui:choose('jewelSelect',11,'id')
    local saved={};build:Save(saved);local savedTimeless
    for _,entry in ipairs(saved) do if entry.elem=='TimelessData' then savedTimeless=entry.attrib;break end end
    assert(savedTimeless and savedTimeless.jewelTypeId=='11' and savedTimeless.searchList==desired and savedTimeless.searchListFallback==edited,'Save did not contain the selected jewel draft')
    ui:click('resetButton');assert(build.timelessData.searchList=='' and build.timelessData.searchListFallback=='')
    ui:click('fallbackWeightsUndo');assert(build.timelessData.searchList==desired and build.timelessData.searchListFallback==edited,'Undo did not restore both reset lists')
    ui:click('fallbackWeightsUndo');assert(build.timelessData.searchList=='' and build.timelessData.searchListFallback=='','Redo did not restore the cleared lists')
    ui:click('fallbackWeightsUndo');ui:click('closeButton');build.treeTab:FindTimelessJewel();c=assert(main.popups[1]).controls
    assert(build.timelessData.searchList==desired and build.timelessData.searchListFallback==edited and not c.fallbackWeightsUndo:IsEnabled(),'Reopening did not retain the selected lists or clear dialog history')
    ui:choose('jewelSelect',4,'id');assert(build.timelessData.searchListFallback=='','Inactive drafts should not persist after closing the dialog')
   end
  end
  ui:click('closeButton');ui:restore()
 end
end
print('TIMELESS_DIALOG_UI_OK')
