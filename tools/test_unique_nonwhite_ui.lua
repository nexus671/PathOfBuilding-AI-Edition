arg={};dofile('HeadlessWrapper.lua');newBuild()
local sim=require('Modules.CraftingSimulator');local q=require('Modules.CraftingUniqueQuality');local raw='Rarity: UNIQUE\nThe Surrender\nEzomyte Tower Shield\nItem Level: 86\nSockets: W-W-W'
for count=2,3 do for seed=1,20 do local result=sim.perform(raw,{method='socket_colour_bench',count=count},seed);local item=q.inspect(result.itemText);local seen=0;for _,s in ipairs(item.sockets) do if s.color~='W' then seen=seen+1 end end;assert(seen>=count);assert(result.components.chromatic==({[2]=5,[3]=20})[count]) end end
local corrupted=sim.perform(raw..'\nCorrupted',{method='socket_colour_bench',count=3},1);assert(corrupted.components['Metadata/Items/Currency/CurrencyCorrupt']==20)
local recipe={steps={{method='socket_colour_bench',count=2}},targets={},requirements={socketColours='RR'}};local r=sim.simulate(raw,recipe,{trials=10,maxActions=1,seed=42});assert(r.trials==10)
print('UNIQUE_BENCH_BACKEND_OK')
local output=sim.calculate(raw..'\nCorrupted',{method='socket_colour_bench',count=2},{},nil,{trials=10,seed=4,requirements={socketColours='WWW'}});assert(output.components.chromatic==5 and output.components['Metadata/Items/Currency/CurrencyCorrupt']==5);local found=false;for _,w in ipairs(output.warnings) do if w.code=='unique_socket_target_unreachable' then found=true end end;assert(found)
local cat=q.catalog(raw,'',100);local found=0;for _,e in ipairs(cat.uniqueActions) do if e.method=='socket_colour_bench' then found=found+1;assert(e.action.count>=2 and e.action.count<=4) end end;assert(found==3)
local used=assert(q.previewResources(raw,{raw},{'socket_colour_bench:3'},nil,false));local chromatic=false;for _,entry in ipairs(used) do if entry.name=='Chromatic Orb' then chromatic=entry.amount==20 end end;assert(chromatic)
local dialla="Rarity: UNIQUE\nDialla's Malefaction\nSage's Robe\nItem Level: 86\nSockets: R-G-B";assert(q.colourReason(dialla,'socket_colour_bench',2):find('no%-white%-socket'));assert(not q.colourReason(dialla,'socket_colour_bench',3));assert(q.colourReason(dialla,'socket_colour_bench',4))
local expected=q.colourTargetReason(q.inspect(raw),'socket_colour_bench','WWW',false,true,2);assert(expected and expected:find('guaranteed non%-white'))
print('UNIQUE_BENCH_CALCULATE_OK')

newBuild();main.popups={}
local ui=require('Modules.HeadlessUI').install({width=1024,height=768});ui:bind(build)
local project={id='nonwhite',title='Bench',slot='Helmet',startingItem='Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W',goals={},steps={}};build.savers.CraftingProjects:Upsert(project)
local control=require('Classes.CraftingUniqueQualityControl').Open(build,project);ui:click('socketCount');ui:click('colours');ui:choose('method','socket_colour_bench:3','val');assert(main.popups[1].controls.apply:IsEnabled());ui:click('apply');assert((control.currencyNote.list[1][1] or ''):find('20 Chromatic',1,true));ui:click('guide');ui:click('recipe')
local saved=build.savers.CraftingProjects.projects[1];assert(saved.steps[1].uniqueCraft.method=='socket_colour_bench' and saved.steps[1].uniqueCraft.count==3,'Guide lost bench action');assert(saved.nativeRecipe.steps[1].method=='socket_colour_bench' and saved.nativeRecipe.steps[1].count==3,'Recipe lost bench action')
local preview=sim.perform(project.startingItem,{method='socket_colour_bench',count=3},1).itemText;local recovered=require('Modules.PlanningRecovery').clean('uniqueQuality',{plan={kind='uniqueQuality',project=project,itemText=preview,history={project.startingItem},actions={'socket_colour_bench:3'},redo={}}});assert(recovered.plan.actions[1]=='socket_colour_bench:3')
local f=require('Modules.LootFilters');local rules=f.generate(build,f.profile('pickups','Pickups'));local found=false;for _,r in ipairs(rules) do if r.origin=='craft:nonwhite' and r.text:find('Chromatic Orb',1,true) then found=true end end;assert(found,'Bench guide omitted chromatic pickup')
local xml=build:SaveDB('Bench test');loadBuildFromXML(xml,'Bench test');assert(build.savers.CraftingProjects.projects[1].steps[1].uniqueCraft.count==3);ui:restore();print('UNIQUE_NONWHITE_UI_OK')

newBuild();main.popups={};local host=require('Modules.HeadlessUI').install({width=960,height=640});host:bind(build)
local direct={id='direct-bench',title='Direct bench',slot='Helmet',startingItem='Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: W-W W W\nCorrupted',goals={},steps={}};build.savers.CraftingProjects:Upsert(direct)
require('Classes.CraftingUniqueQualityControl').Open(build,direct);host:click('socketCount');host:click('colours');host:choose('method','socket_colour_bench:3','val');assert(main.popups[1].controls.availability.label():find('20 Chromatic + 20 Vaal',1,true));host:text('target','RRR');host:text('attempts','30');assert(main.popups[1].controls.plan:IsEnabled());host:click('plan')
local saved=build.savers.CraftingProjects.projects[1];assert(saved.nativeRecipe.steps[1].count==3 and saved.steps[1].uniqueCraft.count==3);assert(saved.steps[1].action:find('20 Vaal Orbs',1,true))
local filters=require('Modules.LootFilters');local pickups=filters.generate(build,filters.profile('p','Pickups'));local names={};for _,entry in ipairs(pickups) do if entry.origin=='craft:direct-bench' then names[entry.title]=true end end
local chromatic,vaal=false,false;for title in pairs(names) do chromatic=chromatic or title:find('Chromatic Orb',1,true)~=nil;vaal=vaal or title:find('Vaal Orb',1,true)~=nil end;assert(chromatic and vaal,'Corrupted guide omitted its pickup resources')
local xml=build:SaveDB('Direct bench');loadBuildFromXML(xml,'Direct bench');assert(build.savers.CraftingProjects.projects[1].nativeRecipe.steps[1].count==3);host:restore();print('UNIQUE_NONWHITE_DIRECT_OK')
