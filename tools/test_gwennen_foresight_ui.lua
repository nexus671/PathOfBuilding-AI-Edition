local output=assert(arg[1]);arg={};dofile('HeadlessWrapper.lua');main.disableDevAutoSave=true
local sim=require('Modules.CraftingSimulator');local UI=require('Modules.HeadlessUI');local raw='Rarity: RARE\nExample\nIron Hat\nItem Level: 86'
newBuild();local model=sim.model(raw);local original=copyTable(model.initial);local craft={method='gwennen',firstOutcome=1002,secondOutcome=1000}
local direct=sim.action(model,original,{method='hinekora_lock'},function() return 0.25 end);assert(direct.foreseeing and sim.components({method='hinekora_lock'})['Metadata/Items/Currency/CurrencyHinekorasLock']==1);assert(not pcall(sim.action,model,direct,{method='hinekora_lock'},function() return 0.25 end))
assert(require('Modules.CraftingGwennen').isForesightCurrency('chaos') and require('Modules.CraftingGwennen').isForesightCurrency('essence') and not require('Modules.CraftingGwennen').isForesightCurrency('gwennen') and not require('Modules.CraftingGwennen').isForesightCurrency('locus'))
local locked,details=sim.action(model,original,craft,function() return 0.25 end);assert(locked.foreseeing and details.gwennen.outcome==1002 and not original.foreseeing)
local sample=sim.perform(raw,{method='chaos'},123,locked);local repeatSample=sim.perform(raw,{method='chaos'},123,locked);assert(tableDeepEquals(sample.state,repeatSample.state) and locked.foreseeing and not sample.state.foreseeing)
assert(sim.validateState(model,locked).foreseeing);local invalid=copyTable(locked);invalid.mirrored=true;assert(not pcall(sim.validateState,model,invalid));invalid=copyTable(locked);invalid.corrupted=true;assert(not pcall(sim.validateState,model,invalid));assert(not pcall(sim.validateRecipe,{steps={{method='chaos'}},targets={},requirements={foreseeing=true,mirrored=true}}));local modified=sim.action(model,locked,{method='chaos'},function() return 0.42 end);assert(not modified.foreseeing and locked.foreseeing)
local service=sim.action(model,locked,{method='gwennen',firstOutcome=1000,secondOutcome=1000},function() return 0.25 end);assert(not service.foreseeing)
local calc=sim.calculate(raw,craft,{},nil,{requirements={foreseeing=true},trials=1});assert(not calc.sampled and #calc.outcomes==2 and calc.successChance==50)
local found=0;for _,o in ipairs(calc.outcomes) do if o.state.foreseeing then found=found+1;assert(o.chance==50) end end;assert(found==1)
local recipeResult=sim.simulate(raw,{steps={{method='hinekora_lock'}},targets={},requirements={foreseeing=true}},{trials=1,maxActions=1,currency='chaos',prices={hinekora_lock=5}});assert(recipeResult.successChance==100 and recipeResult.meanCost==5 and recipeResult.resourceUsage[1].name=="Hinekora's Lock")
local inventory=require('Modules.CraftingInventory');local project={id='foresight',title='Foreseeing',slot='Helmet',startingItem=raw,goals={},steps={}};project.inventory={inventory.capture(project,locked,'Locked item')}
local store=build.savers.CraftingProjects;store:Upsert(project);local xml={};store:Save(xml);local restored=require('Modules.CraftingProjects').new(build);restored:Load(xml);assert(restored.projects[1].inventory[1].state.foreseeing)
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local p={id='foresight-ui',title='Foreseeing',slot='Helmet',startingItem=raw,goals={},steps={},preferredMethod='chaos',nativeRecipe={targets={},initialState=locked}}
 local c=require('Classes.CraftingSimulatorControl').Open(build,p);assert(c.apply:IsEnabled());ui:click('apply')
 assert(main.popups[1].title=='Foreseeing: hypothetical sample');ui:frame():write(output..'/'..size[1]..'-craft-foresight-preview.json');ui:click('close')
 ui:click('apply');assert(main.popups[1].title=='Foreseeing: hypothetical sample');ui:click('keep');assert(not main.popups[1].title or main.popups[1].title~='Foreseeing: hypothetical sample')
 ui:click('undo');ui:click('apply');assert(main.popups[1].title=='Foreseeing: hypothetical sample');ui:click('close');main.popups={}
 local kept;local target=require('Classes.CraftingTargetControl').Open({}, {foreseeing=true},nil,function(_,v) kept=v end);assert(target.mirrored:GetSelValue()=='Must be foreseeing');ui:frame():write(output..'/'..size[1]..'-craft-foresight-target.json');ui:choose('mirrored','Neither mirrored nor foreseeing');ui:click('keep');assert(kept.foreseeing==false and kept.mirrored==false)
 ui:restore();main.popups={}
end
for _,case in ipairs({{method='essence',title='Foreseeing: hypothetical sample'},{method='bench',title='Review modeled action'}}) do
 newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
 local p={id='review-'..case.method,title='Review',slot='Helmet',startingItem=raw,goals={},steps={},preferredMethod=case.method,nativeRecipe={targets={},initialState=locked}}
 local c=require('Classes.CraftingSimulatorControl').Open(build,p);assert(c.apply:IsEnabled(),case.method..' must be available');ui:click('apply');assert(main.popups[1].title==case.title,case.method..' must be reviewed');ui:frame():write(output..'/960-craft-foresight-'..case.method..'.json');ui:click('close');ui:click('apply');assert(main.popups[1].title==case.title);ui:click('keep');ui:click('undo');ui:click('apply');assert(main.popups[1].title==case.title);ui:click('close');ui:restore();main.popups={}
end
newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
local c=require('Classes.CraftingSimulatorControl').Open(build,{id='lock-action-ui',title='Lock action',slot='Helmet',startingItem=raw,goals={},steps={}})
ui:click('settings');ui:text('paletteSearch',"Hinekora's Lock");assert(main.popups[1].controls.paletteUse:IsEnabled());ui:frame():write(output..'/960-craft-hinekora-palette.json');ui:click('paletteUse');ui:click('item')
local lines={};for _,row in ipairs(main.popups[1].controls.itemMods.list) do lines[#lines+1]=StripEscapes(row[1] or '') end;assert(table.concat(lines,' '):find('Foreseeing',1,true));ui:restore();main.popups={}
print('GWENNEN_FORESIGHT_OK')
