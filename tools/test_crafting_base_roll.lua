-- Base roll thresholds use native modifier ranges before item/character scaling.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local sim=require("Modules.CraftingSimulator");local raw='Rarity: NORMAL\nIron Hat\nItem Level: 86';local model=sim.model(raw)
local state=copyTable(model.initial);state.rarity="RARE";state.affixes={{id="IncreasedLife4",range=0.8}}
local goal={anyOf={"IncreasedLife4"},minBaseValue=65,maxBaseValue=67}
assert(sim.singleBaseRoll(model.byId.IncreasedLife4,0.8)==66)
assert(sim.matches(state,{goal},nil,model));state.affixes[1].range=0.5;assert(not sim.matches(state,{goal},nil,model))
state.affixes[1].range=1;assert(not sim.matches(state,{goal},nil,model))
local either={anyOf={"IncreasedLife3","IncreasedLife4"},minBaseValue=50}
state.affixes[1]={id="IncreasedLife3",range=0.8};assert(sim.matches(state,{either},nil,model))
state.affixes[1].range=0;assert(not sim.matches(state,{either},nil,model));either.negate=true;assert(sim.matches(state,{either},nil,model))
assert(sim.singleBaseRoll({"Adds (1-2) to (3-4) Fire Damage"},0.5)==nil)
assert(sim.singleBaseRoll({"+(0-5) to Level 20 Example"},0)==0)
assert(not pcall(sim.validateRecipe,{steps={{method="alchemy"}},targets={{anyOf={"IncreasedLife4"},scope="implicit",minBaseValue=1}}}))
assert(not pcall(sim.validateRecipe,{steps={{method="alchemy"}},targets={{anyOf={"IncreasedLife4"},minBaseValue=70,maxBaseValue=60}}}))
local result=sim.calculate(raw,{method="alchemy"},{goal},nil,{trials=30,seed=5})
assert(result.sampled and result.trials==30 and result.successChance>=0 and result.successChance<=100)
local magic;for seed=1,100 do local candidate=sim.perform(raw,{method="transmute"},seed).state;if #candidate.affixes==1 then magic=candidate;break end end
assert(magic,"Could not create a one-modifier magic item")
local finite=sim.calculate(raw,{method="augmentation"},{goal},magic,{trials=20,seed=5});assert(finite.sampled and finite.trials==20,"A roll-sensitive augmentation must use sampling")
local recipe={steps={{method="alchemy"}},targets={goal}}
local run=sim.simulate(raw,recipe,{trials=20,maxActions=1,seed=5});assert(run.trials==20,"Base-roll recipe did not simulate")
newBuild();local store=build.savers.CraftingProjects;store:Upsert({id="base-roll",title="Base roll",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
local xml={};store:Save(xml);local restored=require("Modules.CraftingProjects").new(build);restored:Load(xml)
assert(restored.projects[1].nativeRecipe.targets[1].minBaseValue==65 and restored.projects[1].nativeRecipe.targets[1].maxBaseValue==67,"Saved recipe lost the base-roll target")
local complex;for _,entry in ipairs(model.mods) do local n=0;for _,line in ipairs(entry.mod) do for _ in line:gmatch("%(%-?%d+%.?%d*%-%-?%d+%.?%d*%)") do n=n+1 end end;if n>1 then complex=entry.id;break end end
assert(complex and not pcall(sim.calculate,raw,{method="alchemy"},{{anyOf={complex},minBaseValue=1}},nil,{trials=2,seed=5}),"Ambiguous multi-value modifier must be rejected")
local tincture='Item Class: Tinctures\nRarity: MAGIC\nPersevering Prismatic Tincture of Mastery\nPrismatic Tincture\nItem Level: 85\nQuality: 18\nImplicits: 1\n100% increased Elemental Damage with Melee Weapons\n30% reduced Mana Burn rate\n30% increased Melee Weapon Attack Speed'
local tinctureModel=sim.model(tincture);local imported={{anyOf={"TinctureIncreasedAttackSpeed3"},minBaseValue=1}}
local ok,why=pcall(sim.matches,tinctureModel.initial,imported,nil,tinctureModel);assert(not ok and tostring(why):find("original base roll is unknown",1,true))
local rerolled=sim.perform(tincture,{method="alteration"},3).state;local affix=rerolled.affixes[1]
assert(sim.matches(rerolled,{{anyOf={affix.id},minBaseValue=0}},nil,tinctureModel),"A newly generated tincture roll should be usable")
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build);local saved
	local parent=require("Classes.CraftingTargetControl").Open({{anyOf={"IncreasedLife4"}}},nil,nil,function(groups) saved=groups end,1,nil,model)
	if output then ui:frame():write(output.."/"..size[1].."-crafting-base-roll-parent.json") end
	ui:click("baseRoll");ui:text("minimum","65");ui:text("maximum","67")
	if output then ui:frame():write(output.."/"..size[1].."-crafting-base-roll.json") end
	ui:click("keep");assert(parent.baseRoll.label()=="Base value set...");ui:click("keep");assert(saved[1].minBaseValue==65 and saved[1].maxBaseValue==67)
end
print("CRAFTING_BASE_ROLL_OK")
