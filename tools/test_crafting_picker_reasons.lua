arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true;newBuild()
local ui=require('Modules.HeadlessUI').install({width=1024,height=768});ui:bind(build)
local model=require('Modules.CraftingSimulator').model('Rarity: NORMAL\nSomatic Wand\nItem Level: 86')
local state=copyTable(model.initial);local allowAlternative=false;local conflict=false
local c=require('Classes.CraftingModifierControl').Open(model,state,{choose=function() end,chooseReason=function() if conflict then return 'Already in this group.' end end,alternative=function() end,canAlternative=function() return allowAlternative end,alternativeReason=function() if conflict then return 'Conflicting target scope.' end end,present=function() end})
assert(not c.alternative:IsEnabled() and c.alternative.tooltipText()=='Add a target group first.')
allowAlternative=true;conflict=true;assert(not c.choose:IsEnabled() and c.choose.tooltipText()=='Already in this group.')
assert(not c.alternative:IsEnabled() and c.alternative.tooltipText()=='Conflicting target scope.')
conflict=false;state.destroyed=true;assert(not c.present:IsEnabled() and c.present.tooltipText():find('destroyed',1,true))
state.destroyed=nil;state.veil={};assert(not c.present:IsEnabled() and c.present.tooltipText():find('unveil',1,true))
state.veil=nil;ui:text('search','zzzzzz-no-such-modifier');assert(not c.choose:IsEnabled() and c.choose.tooltipText()=='Select a modifier first.')
assert(not c.alternative:IsEnabled() and c.alternative.tooltipText()=='Select a modifier first.')
assert(not c.present:IsEnabled() and c.present.tooltipText()=='Select a modifier first.')
ui:restore()
for _,size in ipairs({{640,480},{960,640},{1280,720}}) do
 local host=require('Modules.HeadlessUI').install({width=size[1],height=size[2]});host:bind(build)
 for _,variant in ipairs({'choose','alternative','all'}) do
  local staged=false;local options={choose=function() end}
  if variant~='choose' then options.alternative=function() end end
  if variant=='all' then options.present=function() staged=true end end
  local controls=require('Classes.CraftingModifierControl').Open(model,copyTable(model.initial),options)
  local previousRight
  for _,key in ipairs({'choose','alternative','present','close'}) do local control=controls[key];if control then
   local x=control:GetPos();local width=control:GetSize();assert(not previousRight or x>=previousRight,key..' overlaps another action at '..size[1]);assert(x>=0 and x+width<=size[1],key..' is off screen');previousRight=x+width
  end end
  if variant=='all' then assert(controls.present:IsEnabled());host:click('present');assert(staged,'Present action did not run') else host:click('close') end
 end
 host:restore()
end
print('CRAFTING_PICKER_REASONS_OK')
