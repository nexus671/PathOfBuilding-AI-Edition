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
local weaponRaw='Rarity: NORMAL\nRusted Sword\nItem Level: 86';local weapon=sim.model(weaponRaw);local mod=weapon.byId.LocalAddedColdDamage2
assert(sim.baseRollValue(mod,{0,1},1)==7 and sim.baseRollValue(mod,{0,1},2)==16)
assert(sim.baseRollValue(mod,{1,0},1)==9 and sim.baseRollValue(mod,{1,0},2)==14)
assert(sim.baseRollValue({'+(10-20) to maximum Life','+(1-5) to Strength'},{0.2,0.8},2)==4)
local mana={"+(74-78) to maximum Mana","Non-Channelling Skills have -(8-6) to Total Mana Cost"}
assert(not sim.baseRollReason(mana,2));assert(sim.baseRollValue(mana,{0,0},2)==-8);assert(sim.baseRollValue(mana,{1,1},2)==-6)
assert(sim.baseRollReason({"-(10-5)% increased Damage"},1))
local ring=sim.model("Rarity: NORMAL\nIron Ring\nItem Level: 86");local manaId="IncreasedManaEnhancedLevel50ModCostNew";assert(ring.byId[manaId]);local ringState=copyTable(ring.initial);ringState.rarity="RARE";ringState.affixes={{id=manaId,range={0,0}}}
local leech=assert(ring.byId.LifeLeechPermyriadSuffix1);assert(sim.rollRange(leech,function() return 0.02 end)==0)
local leechRange=sim.rollRange(leech,function() return 0.34 end);assert(math.abs(sim.baseRollValue(leech,leechRange)-0.27)<1e-7)
assert(sim.rollRange(leech,function() return 0.999 end)==1)
local manaGoal={anyOf={manaId},baseValueComponent=2,maxBaseValue=-8};assert(sim.matches(ringState,{manaGoal},nil,ring));ringState.affixes[1].range={1,1};assert(not sim.matches(ringState,{manaGoal},nil,ring))
for _,sample in ipairs({{0,-8},{0.32,-8},{0.34,-7},{0.66,-7},{0.68,-6},{0.999,-6}}) do
 local range=sim.rollRange(ring.byId[manaId],function() return sample[1] end);assert(sim.baseRollValue(ring.byId[manaId],range,2)==sample[2],"Descending rolls must use equal-width outcome buckets")
end
assert(sim.baseRollReason(mod,nil) and sim.baseRollReason(mod,3) and not sim.baseRollReason(mod,2))
local weaponState=copyTable(weapon.initial);weaponState.rarity="RARE";weaponState.affixes={{id="LocalAddedColdDamage2",range={0,1}}}
local minTarget={anyOf={"LocalAddedColdDamage2"},minBaseValue=7,baseValueComponent=1}
local maxTarget={anyOf={"LocalAddedColdDamage2"},minBaseValue=16,baseValueComponent=2}
assert(sim.matches(weaponState,{minTarget,maxTarget},nil,weapon));maxTarget.minBaseValue=17;assert(not sim.matches(weaponState,{minTarget,maxTarget},nil,weapon));maxTarget.minBaseValue=16
local multiEstimate=sim.calculate(weaponRaw,{method="alchemy"},{maxTarget},nil,{trials=20,seed=5});assert(multiEstimate.sampled and multiEstimate.trials==20)
assert(not pcall(sim.validateRecipe,{steps={{method="alchemy"}},targets={{anyOf={"LocalAddedColdDamage2"},baseValueComponent=2}}}))
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
store:Upsert({id="multi-roll",title="Multi roll",slot="Weapon 1",startingItem=weaponRaw,goals={},steps={},nativeRecipe={steps={{method="alchemy"}},targets={minTarget,maxTarget}}})
xml={};store:Save(xml);restored=require("Modules.CraftingProjects").new(build);restored:Load(xml)
assert(restored.projects[2].nativeRecipe.targets[2].baseValueComponent==2,"Saved recipe lost the component")
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
	local parent=require("Classes.CraftingTargetControl").Open({{anyOf={"LocalAddedColdDamage2"}}},nil,nil,function(groups) saved=groups end,1,nil,weapon)
	if output then ui:frame():write(output.."/"..size[1].."-crafting-base-roll-parent.json") end
	ui:click("baseRoll");ui:text("minimum","15");ui:text("maximum","16");ui:text("component","2")
	if output then ui:frame():write(output.."/"..size[1].."-crafting-base-roll.json") end
	ui:click("keep");assert(parent.baseRoll.label()=="Base value set...");ui:click("keep");assert(saved[1].minBaseValue==15 and saved[1].maxBaseValue==16 and saved[1].baseValueComponent==2)
end
print("CRAFTING_BASE_ROLL_OK")
