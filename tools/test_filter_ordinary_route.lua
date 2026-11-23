arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local filters=require("Modules.LootFilters")
local project={id="ordinary-route",title="Branched armour",slot="Body Armour",startingItem="Rarity: NORMAL\nPlate Vest\nItem Level: 86",goals={},steps={},nativeRecipe={targets={},requirements={minAffixes=1},steps={{method="alchemy",onSuccess=3,onFailure=3},{method="alteration"},{method="chaos"}}}}
build.savers.CraftingProjects:Upsert(project)
local profile=filters.profile("ordinary-route","Ordinary route");profile.trackBuildPickups=true
local function has(rules,name) for _,rule in ipairs(rules) do if rule.origin=="craft:ordinary-route" and rule.title==name then return true end end;return false end
profile.rules=filters.generate(build,profile)
assert(has(profile.rules,"Orb of Alchemy") and has(profile.rules,"Chaos Orb"));assert(not has(profile.rules,"Orb of Alteration"),"Skipped step incorrectly produces a pickup")
local deps=require("Modules.LootFilterDependencies");assert(not deps.report(build,profile).stale)
project.nativeRecipe.steps[1].onFailure=2;build.savers.CraftingProjects:Upsert(project)
assert(has(filters.generate(build,profile),"Orb of Alteration"));assert(deps.report(build,profile).stale)
local donor="Rarity: NORMAL\nIron Hat\nItem Level: 86"
project.nativeRecipe.steps[2]={method="recombine",donorItem=donor};project.nativeRecipe.steps[1].onFailure=3;build.savers.CraftingProjects:Upsert(project)
local function donorRule(rules) for _,rule in ipairs(rules) do if rule.origin=="craft:ordinary-route" and rule.id:match("^craft%-donor%-") then return true end end;return false end
assert(not donorRule(filters.generate(build,profile)),"Skipped donor became a pickup")
project.nativeRecipe.steps[1].onFailure=2;build.savers.CraftingProjects:Upsert(project)
assert(donorRule(filters.generate(build,profile)),"Reachable donor pickup is missing")
print("Ordinary recipe route pickup checks passed")
