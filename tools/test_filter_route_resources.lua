arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local filters=require("Modules.LootFilters")
local project={id="route-test",title="Branched unique",slot="Weapon 1",startingItem="Rarity: UNIQUE\nThe Blood Reaper\nHeadsman Axe\nItem Level: 86\nSockets: R-G-B",goals={},steps={},nativeRecipe={targets={},requirements={minQuality=20},steps={{method="divine",onSuccess=3,onFailure=3},{method="jeweller"},{method="quality"}}}}
build.savers.CraftingProjects:Upsert(project)
local profile=filters.profile("route-test","Route test")
local function resources()
 local found={};local rules,warnings=filters.generate(build,profile)
 for _,rule in ipairs(rules) do if rule.origin=="craft:route-test" then found[rule.title]=true end end
 return found,warnings
end
local found=resources();assert(found["Divine Orb"] and found["Blacksmith's Whetstone"]);assert(not found["Jeweller's Orb"],"An unreachable step created a Jeweller's Orb pickup")
profile.rules=filters.generate(build,profile);profile.trackBuildPickups=true
local dependencies=require("Modules.LootFilterDependencies");assert(not dependencies.report(build,profile).stale)
project.nativeRecipe.steps[1].onFailure=2;build.savers.CraftingProjects:Upsert(project)
found=resources();assert(found["Jeweller's Orb"],"A reachable failure branch lost its pickup");assert(dependencies.report(build,profile).stale,"A newly reachable resource did not mark the filter stale")
project.startingItem="Rarity: UNIQUE\nThe Blood Reaper\nHeadsman Axe\nItem Level: 86";project.nativeRecipe.steps[1].onFailure=3;build.savers.CraftingProjects:Upsert(project)
local _,warnings=resources();for _,warning in ipairs(warnings) do assert(not warning.message:find("Starting socket layout is not explicit",1,true),"An unreachable socket action requested socket review") end
project.nativeRecipe.steps[1].onFailure=2;build.savers.CraftingProjects:Upsert(project)
_,warnings=resources();local reviewed=false;for _,warning in ipairs(warnings) do reviewed=reviewed or not not warning.message:find("Starting socket layout is not explicit",1,true) end;assert(reviewed,"A reachable socket action did not request socket review")
print("Unique recipe route pickup checks passed")
