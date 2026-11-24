-- A new Atlas draft must not overwrite a plan created while the draft is open.
arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true;newBuild()
local ui=require('Modules.HeadlessUI').install({width=960,height=640});ui:bind(build)
local workspace=require('Modules.PlanningWorkspace').new(build);build.planningWorkspace=workspace;build.viewMode='PLANNER';workspace:Show('atlas')
local draft=workspace.cache.atlas.layout.snapshot();local oldId=draft.id
local recovery=require('Modules.PlanningRecovery');local view=workspace.cache.atlas.layout.viewState()
assert(recovery.clean('atlas',{plan=draft,view=view}).view.newDraft==true,'Recovery lost new-draft state')
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
