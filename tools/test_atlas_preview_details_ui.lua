arg={};dofile('HeadlessWrapper.lua');newBuild();main.popups={}
local ui=require('Modules.HeadlessUI').install({width=1024,height=768});ui:bind(build)
local plan={id='test',title='Test',version='3.30.0c',budget=120,nodes={},desired={65225},notes=''}
local targets=require('Modules.AtlasTargets')
require('Classes.AtlasTargetsControl').Open(build,{current=function() return plan end,selected=function() return nil end,change=function(next) plan=next end,mode=function(value) return value or 'Select nodes' end,showTree=function() end})
local controls=main.popups[1].controls
plan.desired={};assert(not controls.targetCalculate:IsEnabled());assert(controls.targetCalculate.tooltipText():find('Mark at least one',1,true));assert(controls.targetApply.tooltipText():find('Calculate a route first',1,true))
plan.desired={65225};assert(controls.targetCalculate:IsEnabled())
local function details() local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=row[1] or '' end;return StripEscapes(table.concat(lines,' ')) end
ui:click('targetCalculate');for i=1,1000 do ui:frame();if not targets.jobs[build].thread then break end end
assert(targets.jobs[build].result,targets.jobs[build].error);ui:frame();assert(details():find('Preview investment',1,true))
ui:choose('routeMode','Rebuild from start');ui:frame();assert(details():find('Current allocated investment',1,true),'Stale route details remained after changing route mode');assert(controls.targetApply.tooltipText():find('route mode changed',1,true))
ui:choose('routeMode','Retain existing allocations');ui:frame();assert(details():find('Preview investment',1,true),'Valid preview details were not restored')
plan.title='Changed';ui:frame();assert(details():find('Current allocated investment',1,true),'Stale route details remained after editing the plan')
plan.title='Test';ui:frame();assert(details():find('Preview investment',1,true),'Preview was not restored when the plan was restored')
ui:click('targetCalculate');targets.jobs[build].paused=true;ui:frame();assert(controls.targetCalculate.tooltipText():find('replaces the running calculation',1,true));assert(controls.targetApply.tooltipText():find('Resume the paused',1,true));assert(details():find('Current allocated investment',1,true),'Stale route details remained while recalculating')
ui:restore();print('ATLAS_PREVIEW_DETAILS_OK')
