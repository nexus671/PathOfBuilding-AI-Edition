-- A new Atlas draft must not overwrite a plan created while the draft is open.
arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true;newBuild()
local ui=require('Modules.HeadlessUI').install({width=960,height=640});ui:bind(build)
local workspace=require('Modules.PlanningWorkspace').new(build);build.planningWorkspace=workspace;build.viewMode='PLANNER';workspace:Show('atlas')
local draft=workspace.cache.atlas.layout.snapshot();local oldId=draft.id
local recovery=require('Modules.PlanningRecovery');local view=workspace.cache.atlas.layout.viewState()
assert(recovery.clean('atlas',{plan=draft,view=view}).view.newDraft==true,'Recovery lost new-draft state')
local legacy=copyTable(view);legacy.newDraft=nil;assert(recovery.clean('atlas',{plan=draft,view=legacy}).view.newDraft==nil,'Legacy recovery state was rejected')
local invalid=copyTable(view);invalid.newDraft='yes';assert(not pcall(recovery.clean,'atlas',{plan=draft,view=invalid}),'Invalid draft state was accepted')
ui:text('title','My unsaved draft')
local existing=copyTable(draft);existing.title='Created elsewhere';build.savers.AtlasPlans:Upsert(existing)
workspace:Show('filters');workspace:Show('atlas')
assert(workspace.cache.atlas.layout.snapshot().id==oldId,'Draft identity changed on navigation')
local store=build.savers.AtlasPlans;local save=store.Upsert;store.Upsert=function() error('Simulated save failure',0) end
ui:click('keep');store.Upsert=save
assert(workspace.cache.atlas.layout.snapshot().id==oldId and #store.plans==1,'Failed save changed the draft or saved plans')
assert(main.popups[1],'Save failure did not display a message');main:ClosePopup()
ui:click('keep');local plans=build.savers.AtlasPlans.plans
assert(#plans==2,'Keeping draft replaced another plan');assert(plans[1].id==oldId and plans[1].title=='Created elsewhere')
assert(plans[2].id~=oldId and plans[2].title=='My unsaved draft')
local newId=plans[2].id;assert(workspace.cache.atlas.layout.snapshot().id==newId,'Workspace did not follow the new ID')
assert(recovery.clean('atlas',{plan=workspace.cache.atlas.layout.snapshot(),view=workspace.cache.atlas.layout.viewState()}).view.newDraft==false,'Recovery retained a new-draft marker after saving')
assert(not workspace.atlasDrafts[oldId] and workspace.atlasDrafts[newId] and workspace.atlasDrafts[newId].plan.id==newId,'Session draft was not rekeyed')
ui:click('keep');assert(#build.savers.AtlasPlans.plans==2,'Keeping the same draft created a duplicate')
workspace:Show('filters');workspace:Show('atlas');assert(workspace.cache.atlas.layout.snapshot().id==newId,'Navigation restored the old ID')
ui:restore();print('ATLAS_SAVE_COLLISION_OK')
-- A separate unsaved Atlas draft is also reserved when creating another plan.
newBuild();main.popups={};local otherUI=require('Modules.HeadlessUI').install({width=960,height=640});otherUI:bind(build)
local other=require('Modules.PlanningWorkspace').new(build);build.planningWorkspace=other;build.viewMode='PLANNER';other:Show('atlas')
local reserved=copyTable(other.cache.atlas.layout.snapshot());reserved.id='atlas-'..string.rep('a',12);reserved.title='Reserved draft';other.atlasDrafts[reserved.id]={plan=reserved}
local planning=require('Modules.PlanningData');local nextId=planning.newId;local sha=package.loaded.sha1 or require('sha1')
planning.newId=function(prefix,entries,length)
 local calls=0;package.loaded.sha1=function() calls=calls+1;return string.rep(calls==1 and 'a' or 'b',40) end
 local result=nextId(prefix,entries,length);package.loaded.sha1=sha;return result
end
otherUI:click('new');planning.newId=nextId
assert(other.cache.atlas.layout.snapshot().id=='atlas-'..string.rep('b',12),'New plan reused a session draft ID')
assert(other.atlasDrafts[reserved.id] and other.atlasDrafts[reserved.id].plan.title=='Reserved draft','Creating a plan replaced another draft')
otherUI:restore();print('ATLAS_SESSION_DRAFT_ID_OK')
-- Restoring a recovered new draft must retain its new-record status.
newBuild();main.popups={};local recoveryUI=require('Modules.HeadlessUI').install({width=960,height=640});recoveryUI:bind(build)
local before=require('Modules.PlanningWorkspace').new(build);build.planningWorkspace=before;build.viewMode='PLANNER';before:Show('atlas');recoveryUI:text('title','Recovered draft')
local beforeLayout=before.cache.atlas.layout;local saved=recovery.clean('atlas',{plan=beforeLayout.snapshot(),view=beforeLayout.viewState()});local taken=saved.plan.id
local external=copyTable(saved.plan);external.title='Existing after restart';build.savers.AtlasPlans:Upsert(external)
local after=require('Modules.PlanningWorkspace').new(build);build.planningWorkspace=after;after.drafts.atlas=saved;after.atlasDrafts[taken]=saved;after:Show('atlas');recoveryUI:click('keep')
local restored=build.savers.AtlasPlans.plans;assert(#restored==2 and restored[1].title=='Existing after restart' and restored[2].title=='Recovered draft' and restored[2].id~=taken,'Recovered draft replaced the saved plan')
recoveryUI:restore();print('ATLAS_RECOVERY_COLLISION_OK')
-- The active unsaved draft is reserved before navigation saves it in the workspace.
newBuild();main.popups={};local activeUI=require('Modules.HeadlessUI').install({width=960,height=640});activeUI:bind(build)
local active=require('Modules.PlanningWorkspace').new(build);build.planningWorkspace=active;build.viewMode='PLANNER';active:Show('atlas');activeUI:text('title','Active draft')
local activeId=active.cache.atlas.layout.snapshot().id;assert(not active.atlasDrafts[activeId],'Fixture needs an unrecorded active draft')
local activeSuffix=assert(activeId:match('^atlas%-(%x+)$'));local alternate=activeSuffix==string.rep('b',12) and 'c' or 'b'
local activePlanning=require('Modules.PlanningData');local activeNewId=activePlanning.newId;local activeSha=package.loaded.sha1 or require('sha1')
activePlanning.newId=function(prefix,entries,length)
 local attempts=0;package.loaded.sha1=function() attempts=attempts+1;return attempts==1 and activeSuffix..string.rep('0',28) or string.rep(alternate,40) end
 local result=activeNewId(prefix,entries,length);package.loaded.sha1=activeSha;return result
end
activeUI:click('new');activePlanning.newId=activeNewId
assert(active.cache.atlas.layout.snapshot().id~=activeId,'New plan reused the active unsaved draft ID')
assert(active.atlasDrafts[activeId] and active.atlasDrafts[activeId].plan.id==activeId,'Active draft was lost during navigation')
activeUI:restore();print('ATLAS_ACTIVE_DRAFT_ID_OK')
-- Search session drafts by the complete title, including text beyond its display width.
newBuild();main.popups={};local searchUI=require('Modules.HeadlessUI').install({width=960,height=640});searchUI:bind(build)
local searchWorkspace=require('Modules.PlanningWorkspace').new(build);build.planningWorkspace=searchWorkspace;build.viewMode='PLANNER';searchWorkspace:Show('atlas')
local longPlan=copyTable(searchWorkspace.cache.atlas.layout.snapshot());longPlan.title=string.rep('Long farming plan ',5)..'SENTINEL'
local another=copyTable(longPlan);another.id=longPlan.id..'-other';another.title=string.rep('Long farming plan ',5)..'ANOTHER'
require('Classes.AtlasPlannerControl').Library(build,{atlasDrafts=function() return {{plan=longPlan,conflict=true},{plan=another}} end})
local choices=main.popups[1].controls.plans;assert(not choices.list[1].label:find('SENTINEL',1,true),'Fixture title did not exceed the visible label')
searchUI:click('plans');for char in ('SENTINEL'):gmatch('.') do searchUI:dispatch(searchUI:activeHost(),{{type='Char',key=char}}) end
assert(choices:GetMatchCount()==1 and choices.searchInfos[1].matches,'Long draft title cannot be found by its ending')
local tip={lines={}};function tip:Clear() self.lines={} end;function tip:AddLine(_,line) self.lines[#self.lines+1]=line end
choices.tooltipFunc(tip,'HOVER',1,choices.list[1]);local count=#tip.lines;choices.tooltipFunc(tip,'HOVER',1,choices.list[1])
assert(#tip.lines==count and table.concat(tip.lines,' '):find('SENTINEL',1,true),'Draft tooltip must show the complete title without accumulating lines')
searchUI:frame();local sx,sy=choices:GetPos();local _,sh=choices:GetSize();searchUI:clickAt(sx+30,sy+sh+10)
assert(choices:GetSelValueByKey('val')==longPlan.id,'Selecting a filtered title must select the matching draft')
main.popups={};searchUI:restore();print('ATLAS_DRAFT_SEARCH_OK')
