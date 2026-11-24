-- Force ID collisions and verify saving a new project never replaces an existing one.
arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true;newBuild()
local data=require('Modules.PlanningData');local originalSha=require('sha1');local old=package.loaded.sha1
local calls=0;package.loaded.sha1=function() calls=calls+1;return string.rep(calls==1 and 'a' or 'b',40) end
assert(data.newId('craft-',{{id='craft-'..string.rep('a',16)}},16)=='craft-'..string.rep('b',16));assert(calls==2)
package.loaded.sha1=function() return string.rep('a',40) end
local ok,err=pcall(data.newId,'craft-',{{id='craft-'..string.rep('a',16)}},16);assert(not ok and tostring(err):find('unique planning ID',1,true))
package.loaded.sha1=old or originalSha
local ui=require('Modules.HeadlessUI').install({width=960,height=640});ui:bind(build)
local raw='Rarity: NORMAL\nIron Hat\nItem Level: 86';local store=build.savers.CraftingProjects
store:Upsert({id='craft-existing',title='Keep me',slot='Helmet',startingItem=raw,goals={},steps={}})
local realNewId=data.newId;local attempts=0
data.newId=function(prefix,entries,length) attempts=attempts+1;if attempts==1 then return 'craft-existing' end;return realNewId(prefix,entries,length) end
local kept;require('Classes.CraftingProjectWizard').Open(build,nil,raw,'Helmet',nil,function() end,function(value) kept=value end)
ui:choose('wizardPage','Review');ui:click('save');data.newId=realNewId
assert(kept and kept.id~='craft-existing');assert(#store.projects==2 and store.projects[1].title=='Keep me')
ui:restore();print('PLANNING_ID_COLLISION_OK')
local atlas=require('Modules.AtlasPlanner');local plans=build.savers.AtlasPlans
local version=atlas.defaultVersion(build.spec.treeVersion);local existing={id='atlas-'..string.rep('a',12),title='Existing atlas',version=version,budget=atlas.tree(version).maxPoints,nodes={},notes=''}
plans:Upsert(existing);local view=require('Modules.HeadlessUI').install({width=960,height=640});view:bind(build);require('Classes.AtlasPlannerControl').Open(build,existing)
calls=0;package.loaded.sha1=function() calls=calls+1;return string.rep(calls==1 and 'a' or 'b',40) end
view:click('new');view:click('keep');package.loaded.sha1=old or originalSha
assert(#plans.plans==2 and plans.plans[1].title=='Existing atlas');assert(plans.plans[2].id=='atlas-'..string.rep('b',12));view:restore();print('ATLAS_ID_COLLISION_OK')
local inv=require('Modules.CraftingInventory');local sim=require('Modules.CraftingSimulator');local project=store.projects[1]
local state=sim.perform(raw,{method='alchemy'},42).state
local prior=inv.capture(project,state,'Existing snapshot');prior.id='item-'..string.rep('a',20)
data.newId=function(prefix,entries,length)
 calls=0;package.loaded.sha1=function() calls=calls+1;return string.rep(calls==1 and 'a' or 'b',40) end
 local result=realNewId(prefix,entries,length);package.loaded.sha1=old or originalSha;return result
end
local snapshot=inv.capture(project,state,'New snapshot',nil,{prior});assert(snapshot.id=='item-'..string.rep('b',20))
local resumed=inv.project(snapshot,{{id='craft-'..string.rep('a',20)}});assert(resumed.id=='craft-'..string.rep('b',20));data.newId=realNewId
print('INVENTORY_ID_COLLISION_OK')
newBuild();main.popups={};local filterUI=require('Modules.HeadlessUI').install({width=960,height=640});filterUI:bind(build)
local filters=require('Modules.LootFilters');local profile=filters.profile('filter-existing','Existing filter');profile.rules={filters.rule('rule-existing','Keep this rule',{'BaseType == "Iron Hat"'})};build.savers.LootFilters:Upsert(profile)
build.planningWorkspace=require('Modules.PlanningWorkspace').new(build);build.viewMode='PLANNER';build.planningWorkspace:Show('filters');filterUI:click('viewCustomize');filterUI:choose('source','My rules')
attempts=0;data.newId=function(prefix,entries,length) attempts=attempts+1;if attempts==1 then return 'rule-existing' end;return realNewId(prefix,entries,length) end
filterUI:click('add');filterUI:click('keepRule');data.newId=realNewId
local draft=build.planningWorkspace.cache.filters.layout.snapshot();local saved=draft.data.profiles[1].rules
assert(#saved==2 and saved[1].title=='Keep this rule' and saved[2].id~='rule-existing');filterUI:restore();print('FILTER_RULE_ID_COLLISION_OK')
newBuild();main.popups={};local filterCopyUI=require('Modules.HeadlessUI').install({width=960,height=640});filterCopyUI:bind(build)
local original=filters.profile('filter-'..string.rep('a',20),'Original');build.savers.LootFilters:Upsert(original)
build.planningWorkspace=require('Modules.PlanningWorkspace').new(build);build.viewMode='PLANNER';build.planningWorkspace:Show('filters')
data.newId=function(prefix,entries,length)
 calls=0;package.loaded.sha1=function() calls=calls+1;return string.rep(calls==1 and 'a' or 'b',40) end
 local result=realNewId(prefix,entries,length);package.loaded.sha1=old or originalSha;return result
end
filterCopyUI:click('manage');filterCopyUI:text('search','Duplicate profile');filterCopyUI:click('choose');data.newId=realNewId
local copied=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles
assert(#copied==2 and copied[1].title=='Original' and copied[2].id=='filter-'..string.rep('b',20));filterCopyUI:restore();print('FILTER_PROFILE_ID_COLLISION_OK')
newBuild();main.popups={};local gemUI=require('Modules.HeadlessUI').install({width=960,height=640});gemUI:bind(build)
local journey=build.savers.BuildJourney;journey:Put('milestones',{id='gem-'..string.rep('a',20),title='Existing milestone',priority=3,dependencies={}})
require('Classes.GemQualityPlanControl').Open(build);gemUI.clipboard='Item Class: Active Skill Gems\nRarity: Gem\nArc\n--------\nLevel: 20\nQuality: +12%';gemUI:click('paste')
data.newId=function(prefix,entries,length)
 calls=0;package.loaded.sha1=function() calls=calls+1;return string.rep(calls==1 and 'a' or 'b',40) end
 local result=realNewId(prefix,entries,length);package.loaded.sha1=old or originalSha;return result
end
gemUI:click('keep');data.newId=realNewId
assert(#journey.data.milestones==2 and journey.data.milestones[1].title=='Existing milestone' and journey.data.milestones[2].id=='gem-'..string.rep('b',20));gemUI:restore();print('GEM_MILESTONE_ID_COLLISION_OK')
