local output,width=arg[1],tonumber(arg[2]) or 960;arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=width,height=width==960 and 640 or 768});ui:bind(build)
local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40 to Evasion Rating\n+10% to Item Rarity\n+35% to all Elemental Resistances\nReflects 4 Physical Damage to Melee Attackers"
local unique=require("Modules.CraftingUniqueQuality");local options=assert(unique.divineOptions(raw))
local project={id="many-rolls",title="Goldrim rolls",slot="Helmet",startingItem=raw,goals={},steps={}}
build.savers.CraftingProjects:Upsert(project);require("Classes.CraftingUniqueQualityControl").Open(build,project);ui:click("divine")
local controls=main.popups[1].controls;controls.stat:SelByValue("modifier:1","val");ui:text("target",tostring(options[1].current+1));ui:click("addGoal")
controls.stat:SelByValue("modifier:2","val");ui:text("target",tostring(options[2].current+1));if output then ui:frame():write(output.."/"..width.."-unique-multiple-targets.json") end;ui:click("reviewGoals");assert(main.popups[1].title=="Added Divine conditions");if output then ui:frame():write(output.."/"..width.."-unique-multiple-review.json") end;ui:click("choose");assert(controls.goalCount.label():find("0 added",1,true),"Removing a condition did not update the draft")
controls.stat:SelByValue("modifier:1","val");ui:text("target",tostring(options[1].current+1));ui:click("addGoal");controls.stat:SelByValue("modifier:2","val");ui:text("target",tostring(options[2].current+1));ui:click("plan")
local saved=build.savers.CraftingProjects.projects[1];local goals=saved.nativeRecipe.requirements.uniqueModifiers
assert(goals and #goals==2,"Multiple conditions were not saved");assert(not unique.matches(raw,saved.nativeRecipe.requirements),"Starting item unexpectedly met both targets")
local sim=require("Modules.CraftingSimulator");local result=sim.simulate(raw,saved.nativeRecipe,{trials=10,maxActions=10,seed=42,retainSuccesses=10});assert(result.sampled and result.trials==10 and result.successes>0,"Combined simulation did not produce a successful sample")
for _,success in ipairs(result.retainedSuccesses) do assert(unique.matches(success.itemText,saved.nativeRecipe.requirements),"Retained item missed a combined condition") end
local invalid=copyTable(saved.nativeRecipe);invalid.requirements.uniqueModifiers[2]={line=goals[1].line,maxValue=goals[1].minValue-1};assert(not pcall(sim.validateRecipe,invalid),"Contradictory roll limits were accepted")
local xml=build:SaveDB("Multiple unique roll targets");loadBuildFromXML(xml,"Multiple unique roll targets");assert(#build.savers.CraftingProjects.projects[1].nativeRecipe.requirements.uniqueModifiers==2,"Reopening lost targets")
print("UNIQUE_MULTIPLE_TARGETS_OK")
