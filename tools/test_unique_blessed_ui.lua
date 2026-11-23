local output,width=arg[1],tonumber(arg[2]) or 960;arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=width,height=width==960 and 640 or 768});ui:bind(build)
local raw="Rarity: UNIQUE\nAndvarius\nGold Ring\nItem Level: 86\nImplicits: 1\n+12% to Item Rarity\n+100 to Dexterity"
local project={id="blessed-test",title="Implicit target",slot="Ring 1",startingItem=raw,goals={},steps={}}
build.savers.CraftingProjects:Upsert(project);require("Classes.CraftingUniqueQualityControl").Open(build,project)
ui:click("divine");ui:click("blessed");assert(main.popups[1].title=="Blessed Orb")
if output then ui:frame():write(output.."/"..width.."-unique-blessed.json") end
ui:click("preview");local unique=require("Modules.CraftingUniqueQuality");local snapshot=build.planningUniqueQualityDrafts and build.planningUniqueQualityDrafts[project.id]
ui:click("resources");local text={};for _,row in ipairs(main.popups[1].controls.results.list) do text[#text+1]=StripEscapes(row[1] or "") end;assert(table.concat(text," "):find("Blessed Orb",1,true),"Preview resource missing");ui:click("close")
ui:click("undo");ui:click("divine");ui:click("blessed");ui:text("target","15");ui:click("plan")
local saved=build.savers.CraftingProjects.projects[1];assert(saved.nativeRecipe.requirements.uniqueImplicit.minValue==15 and saved.steps[1].uniqueCraft.method=="blessed","Blessed plan not saved")
local sim=require("Modules.CraftingSimulator");local result=sim.simulate(raw,saved.nativeRecipe,{trials=10,maxActions=10,seed=42,retainSuccesses=10});assert(result.sampled and result.trials==10 and result.successes>0)
for _,success in ipairs(result.retainedSuccesses) do assert(unique.matches(success.itemText,saved.nativeRecipe.requirements)) end
local single=sim.calculate(raw,{method="blessed"},{},nil,{trials=10,seed=42,requirements=saved.nativeRecipe.requirements});assert(single.sampled and single.trials==10,"Single-action Blessed calculation did not sample")
local rules=require("Modules.LootFilters").generate(build,require("Modules.LootFilters").profile("blessed","Blessed"));local found=false;for _,rule in ipairs(rules) do if rule.origin=="craft:blessed-test" and rule.title=="Blessed Orb" then found=true end end;assert(found,"Blessed pickup missing")
local xml=build:SaveDB("Blessed plan");loadBuildFromXML(xml,"Blessed plan");assert(build.savers.CraftingProjects.projects[1].nativeRecipe.requirements.uniqueImplicit.minValue==15,"Saved implicit target was lost")
print("UNIQUE_BLESSED_UI_OK")
