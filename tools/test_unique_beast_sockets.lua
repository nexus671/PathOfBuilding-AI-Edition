local output=arg[1];arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local sim=require('Modules.CraftingSimulator');local unique=require('Modules.CraftingUniqueQuality')
local raw='Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B'
local action={method='beast_max_sockets'};local result=sim.perform(raw,action,1)
local proj={id='recover-beast',title='Recovery',slot='Helmet',startingItem=raw,goals={},steps={}}
local recovered=require('Modules.PlanningRecovery').clean('uniqueQuality',{plan={kind='uniqueQuality',project=proj,itemText=result.itemText,history={raw},actions={'beast_max_sockets'},redo={}}});assert(recovered.plan.actions[1]=='beast_max_sockets','Recovery lost the action')
local totals=assert(unique.previewResources(raw,{raw},{'beast_max_sockets'}));local costs={};for _,entry in ipairs(totals) do costs[entry.name]=entry.amount end;assert(costs['The Black Morrigan']==1 and costs['Craicic Shield Crab']==1,'Preview resources missing beasts')
assert(result.itemText:find('Sockets: R%-G B W'),'Incorrect unique socket preview')
assert(result.components.beast_black_morrigan==1 and result.components.beast_craicic_shield_crab==1,'Incorrect beast costs')
local warnings={};for _,w in ipairs(result.warnings) do warnings[w.code]=true end;assert(warnings.unique_socket_count_assumptions and warnings.beast_max_sockets_assumptions,'Missing assumptions')
local odds=sim.calculate(raw,action,{},nil,{requirements={exactSockets=4}});assert(odds.successChance==100 and not odds.sampled and odds.exactFor:find('assumed'),'Incorrect unique craft calculation')
local run=sim.simulate(raw,{steps={action},targets={},requirements={exactSockets=4}},{trials=1,maxActions=2});assert(run.sampleSuccess,'Unique recipe did not succeed')
local cat=unique.catalog(raw,'beast_max_sockets',100);local found;for _,entry in ipairs(cat.uniqueActions) do if entry.method=='beast_max_sockets' then found=entry end end;assert(found and found.available and found.components.beast_craicic_shield_crab==1,'AI catalogue missing action')
assert(not pcall(sim.perform,raw..'\nCorrupted',action,1),'Corrupted unique accepted')
local dialla="Rarity: UNIQUE\nDialla's Malefaction\nSage's Robe\nItem Level: 86\nSockets: R-G B";assert(not pcall(sim.perform,dialla,action,1),'Restricted unique accepted')
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
 newBuild();main.popups={};local ui=require('Modules.HeadlessUI').install({width=size[1],height=size[2]});ui:bind(build)
 local project={id='unique-beast-sockets',title='Unique sockets',slot='Helmet',startingItem=raw,goals={},steps={}};build.savers.CraftingProjects:Upsert(project)
 local controls=require('Classes.CraftingUniqueQualityControl').Open(build,project);ui:click('socketCount');assert(main.popups[1].controls.beastSockets:IsEnabled(),'Bestiary button unavailable')
 if output then ui:frame():write(output..'/'..size[1]..'-unique-beast-sockets.json') end
 ui:click('beastSockets');ui:click('guide');ui:click('recipe')
 local saved;for _,entry in ipairs(build.savers.CraftingProjects.projects) do if entry.id==project.id then saved=entry end end
 assert(saved and saved.steps[1].uniqueCraft and saved.steps[1].uniqueCraft.method=='beast_max_sockets','Guide did not retain action')
 assert(saved.nativeRecipe.steps[1].method=='beast_max_sockets','Recipe did not retain action')
 ui:restore();main.popups={}
end
print('UNIQUE_BEAST_SOCKETS_OK')
