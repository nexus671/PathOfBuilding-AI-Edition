-- Base roll thresholds use native modifier ranges before item/character scaling.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local sim=require("Modules.CraftingSimulator");local raw='Rarity: NORMAL\nIron Hat\nItem Level: 86';local model=sim.model(raw)
local state=copyTable(model.initial);state.rarity="RARE";state.affixes={{id="IncreasedLife4",range=0.8}}
local regen=assert(model.byId.LifeRegeneration2)
local influenced=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86\nShaper Item")
local suppression=assert(influenced.byId.ChanceToDodgeAttacksInfluence2)
local describe=LoadModule("Modules/StatDescriber")
-- Reconstructed legacy modifiers have no normal spawn weight in this data.
-- Compare each modeled raw tick with PoB's translator, not game drop odds.
local blockBase=sim.model("Rarity: NORMAL\nPinnacle Tower Shield\nItem Level: 86")
local blockData=require("Modules.CraftingAdvanced").data().mods
for _,id in ipairs({"BlockAppliesToSpellsUber1","BlockAppliesToSpellsShieldUber1_"}) do
 local mod=assert(blockBase.byId[id]);local stat=assert(blockData[id]).stats[1]
 for rawValue=stat.min,stat.max do
  local draw=(rawValue-stat.min+0.1)/(stat.max-stat.min+1)
  local expected=tonumber(describe({[stat.id]=rawValue},"stat_descriptions")[1]:match("^(%d+)%%"))
  assert(sim.baseRollValue(mod,sim.rollRange(mod,function() return draw end))==expected,id.." raw block translation mismatch")
 end
end
local blockState=copyTable(blockBase.initial);blockState.rarity="RARE";blockState.affixes={{id="BlockAppliesToSpellsShieldUber1_",range=0}}
local blockSource=sim.toItem(blockBase,blockState).raw;local blockImported=sim.model(blockSource)
assert(blockImported.initial.affixes[1].id=="BlockAppliesToSpellsShieldUber1_","Legacy block identity did not survive import")
local blockReroll=sim.action(blockImported,blockImported.initial,{method="divine"},function() return 2.1/11 end)
assert(sim.matches(blockReroll,{{anyOf={"BlockAppliesToSpellsShieldUber1_"},minBaseValue=9,maxBaseValue=9}},nil,blockImported),"Raw 32 must render and match 9% spell block")
assert(sim.itemText(blockImported,blockReroll):find("9% Chance to Block Spell Damage",1,true),"Legacy block roll rendered incorrectly")
for index,draw in ipairs({0,0.34,0.67}) do
 local range=sim.rollRange(suppression,function() return draw end)
 local expected=({9,10,12})[index]
 local translated=describe({["base_spell_suppression_chance_150%_of_value"]=index+5},"stat_descriptions")
 assert(translated[1]=="+"..expected.."% chance to Suppress Spell Damage")
 assert(sim.baseRollValue(suppression,range)==expected,"Suppression raw roll did not match its translation")
 local trial=copyTable(influenced.initial);trial.rarity="RARE";trial.affixes={{id="ChanceToDodgeAttacksInfluence2",range=range}}
 assert(sim.itemText(influenced,trial):find("+"..expected.."% chance to Suppress Spell Damage",1,true),"Suppression roll did not survive item rendering")
end
local suppressionState=copyTable(influenced.initial);suppressionState.rarity="RARE";suppressionState.affixes={{id="ChanceToDodgeAttacksInfluence2",range=0}}
local suppressionReroll=sim.action(influenced,suppressionState,{method="divine"},function() return 0.34 end)
assert(sim.matches(suppressionReroll,{{anyOf={"ChanceToDodgeAttacksInfluence2"},minBaseValue=10,maxBaseValue=10}},nil,influenced),"Divine suppression goal did not match the raw middle roll")
assert(sim.itemText(influenced,suppressionReroll):find("+10% chance to Suppress Spell Damage",1,true),"Divine suppression roll rendered incorrectly")
local legacyBase=sim.model("Rarity: NORMAL\nTwo-Toned Boots\nItem Level: 86\nRedeemer Item")
local legacyState=copyTable(legacyBase.initial);legacyState.rarity="RARE";legacyState.affixes={{id="ChanceToDodgeAttacksInfluence2",range=0}}
local legacyRaw=sim.toItem(legacyBase,legacyState).raw;local legacyModel=sim.model(legacyRaw)
assert(legacyModel.initial.affixes[1].id=="ChanceToDodgeAttacksInfluence2","Legacy suppression identity did not survive import")
local suppressionRecipe={steps={{method="divine"}},targets={{anyOf={"ChanceToDodgeAttacksInfluence2"},minBaseValue=10,maxBaseValue=10}}}
local suppressionRun=sim.simulate(legacyRaw,suppressionRecipe,{trials=120,maxActions=1,seed=13})
assert(suppressionRun.successes>15 and suppressionRun.successes<65,"Suppression target should occur in sampled Divine rolls")
local delveRaw="Rarity: NORMAL\nSlink Boots\nItem Level: 86";local delve=sim.model(delveRaw)
local delveMod=assert(delve.byId.DelveArmourDodgeAndSpellDodge_)
for index,draw in ipairs({0,0.34,0.67,0.99}) do
 local expected=({4,4,6,6})[index]
 assert(sim.baseRollValue(delveMod,sim.rollRange(delveMod,function() return draw end))==expected,"Delve suppression must use the visible raw stat, not a dummy stat")
end
local delveState=copyTable(delve.initial);delveState.rarity="RARE";delveState.affixes={{id="DelveArmourDodgeAndSpellDodge_",range=0}}
local delveSource=sim.toItem(delve,delveState).raw;local delveImported=sim.model(delveSource)
assert(delveImported.initial.affixes[1].id=="DelveArmourDodgeAndSpellDodge_","Delve suppression identity did not survive import")
local delveRecipe={steps={{method="divine"}},targets={{anyOf={"DelveArmourDodgeAndSpellDodge_"},minBaseValue=5,maxBaseValue=5}}}
assert(sim.simulate(delveSource,delveRecipe,{trials=120,maxActions=1,seed=13}).successes==0,"A 5% Delve roll must not appear in the modeled recipe")
local checkedSuppression=0;local metadata=require("Modules.CraftingAdvanced").data().mods
for id,mod in pairs(influenced.byId) do
 local stats=metadata[id] and metadata[id].stats;local stat=stats and #stats==1 and stats[1]
 if stat and stat.id=="base_spell_suppression_chance_150%_of_value" and #mod==1 and mod[1]:match("^%+%(%d+%-%d+%)%% chance to Suppress Spell Damage$") and stat.max>stat.min then
  local steps=stat.max-stat.min
  for offset=0,steps do
   local range=sim.rollRange(mod,function() return (offset+0.1)/(steps+1) end)
   local translated=describe({[stat.id]=stat.min+offset},"stat_descriptions")
   local expected=tonumber(translated[1]:match("%+(%d+)%%"))
   assert(sim.baseRollValue(mod,range)==expected,id.." raw suppression translation mismatch")
  end
  checkedSuppression=checkedSuppression+1
 end
end
assert(checkedSuppression>1,"Expected several variable suppression tiers")
local first=sim.rollRange(regen,function() return 0.001 end);assert(first==0)
local middle=sim.rollRange(regen,function() return 0.5 end);assert(math.abs(middle-177/354)<1e-10)
assert(sim.baseRollValue(regen,middle)==5.1)
assert(sim.rollRange(regen,function() return 0.9999 end)==1)
for _,case in ipairs({{"LifeRegenerationEssence2",121,300,2,5},{"LifeRegenerationEssence7",1801,2400,30,40}}) do
 local mod=assert(model.byId[case[1]])
 for _,draw in ipairs({0,0.25,0.5,0.999999}) do
  local range=sim.rollRange(mod,function() return draw end)
  local actual=(case[4]+range*(case[5]-case[4]))*60
  local expected=case[2]+math.floor(draw*(case[3]-case[2]+1))
  assert(math.abs(actual-expected)<1e-7,case[1].." did not sample the pinned raw tick")
 end
end
local regenState=copyTable(model.initial);regenState.rarity="RARE";regenState.affixes={{id="LifeRegeneration2",range=0.5}}
local divined=sim.perform(raw,{method="divine"},7,regenState);local reroll=divined.state.affixes[1].range
assert(math.abs(reroll*354-math.floor(reroll*354+0.5))<1e-8,"Divine reroll must retain a raw per-minute tick")
assert(divined.itemText:find("Regenerate 4 Life per second",1,true))
local regenGoal={anyOf={"LifeRegeneration2"},minBaseValue=4,maxBaseValue=4}
assert(sim.matches(divined.state,{regenGoal},nil,model))


local jewelRaw="Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86";local jewel=sim.model(jewelRaw);local manaRegen=assert(jewel.byId.AbyssFlatManaShieldRegenerationJewel1)
local manaTick=sim.rollRange(manaRegen,function() return 0.02 end);assert(math.abs(manaTick-1/54)<1e-10,"Mana regeneration must use raw per-minute ticks")
local jewelState=copyTable(jewel.initial);jewelState.rarity="RARE";jewelState.affixes={{id="AbyssFlatManaShieldRegenerationJewel1",range=0.5}}
local manaDivined=sim.perform(jewelRaw,{method="divine"},7,jewelState);local manaReroll=manaDivined.state.affixes[1].range;assert(math.abs(manaReroll*54-math.floor(manaReroll*54+0.5))<1e-8,"Divine reroll lost the raw mana-regeneration tick")

for _,case in ipairs({{"Rarity: NORMAL\nHubris Circlet\nItem Level: 86\nCrusader Item","EnergyShieldRegenInfluence1"},{"Rarity: NORMAL\nPlate Vest\nItem Level: 86\nElder Item","LifeRegenerationRatePercentUber1"}}) do
 local percentModel=sim.model(case[1]);local percentMod=assert(percentModel.byId[case[2]]);assert(math.abs(sim.rollRange(percentMod,function() return 0.04 end)-1/30)<1e-9,"Percentage regeneration must use raw per-minute ticks")
end

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
