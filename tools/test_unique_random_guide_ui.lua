-- Verify a random socket preview followed by a bench link remains a usable guide.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local uiModule=require("Modules.HeadlessUI");local unique=require("Modules.CraftingUniqueQuality");local filters=require("Modules.LootFilters");local projects=require("Modules.CraftingProjects")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=uiModule.install({width=size[1],height=size[2]});ui:bind(build)
 local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nSockets: R-G B\n+40% to Fire Resistance"
 local project={id="random-link",title="Random link",slot="Helmet",startingItem=raw,goals={},steps={}}
 local store=build.savers.CraftingProjects;store:Upsert(project)
 local result;for seed=1,300 do local r=unique.randomSockets(raw,"jeweller",require("Modules.CalcEncounter").seed(104729,seed,79));local item=unique.inspect(r.itemText);if #item.sockets==4 then result=r;break end end;assert(result,"Could not construct a four-socket preview")
 local snapshot={itemText=result.itemText,history={raw},actions={"jeweller"},redo={}}
 local control=require("Classes.CraftingUniqueQualityControl").Open(build,project,nil,snapshot)
 assert(control.benchLink:IsEnabled(),"Bench linking should be available");ui:click("benchLink");ui:click("guide")
 local saved=store.projects[1];assert(saved.steps[1].uniqueCraft.method=="jeweller" and saved.steps[2].uniqueCraft.method=="socket_bench","Guide lost a typed action")
 assert(saved.steps[2].action=="Link existing sockets at the crafting bench" and saved.steps[2].stopWhen:find("Check socket count",1,true),"Guide treated a sampled count as guaranteed")
 local xml=build:SaveDB("Random link test");loadBuildFromXML(xml,"Random link test");ui:bind(build)
 saved=build.savers.CraftingProjects.projects[1]
 assert(saved.steps[1].uniqueCraft.method=="jeweller" and saved.steps[2].uniqueCraft.method=="socket_bench","Save and reopen lost the guide")
 local rules=filters.generate(build,filters.profile("random-link","Random link"));local names={};for _,r in ipairs(rules) do if r.origin=="craft:random-link" then names[r.title]=true end end
 assert(names["Jeweller's Orb"] and names["Orb of Fusing"],"Filter pickups lost a guide resource")
 local legacy=copyTable(saved);legacy.steps[2].action=unique.guideAction("socket_bench",1,"Armourer's Scrap",false,4)
 local retained=projects.validate(legacy);assert(retained.steps[2].uniqueCraft and retained.steps[2].uniqueCraft.method=="socket_bench","Older sampled guide lost its typed action")
 build.savers.CraftingProjects:Upsert(retained)
 local oldRules=filters.generate(build,filters.profile("legacy-link","Legacy link"));local oldNames={};for _,r in ipairs(oldRules) do if r.origin=="craft:random-link" then oldNames[r.title]=true end end
 assert(oldNames["Jeweller's Orb"] and oldNames["Orb of Fusing"],"Older guide lost a filter pickup")
 local reset=copyTable(saved);table.insert(reset.steps,2,{action=unique.guideAction("socket_count_bench",4,"Armourer's Scrap",false),uniqueCraft={method="socket_count_bench",count=4}})
 reset.steps[3].action=unique.guideAction("socket_bench",1,"Armourer's Scrap",false,4)
 local resetGuide=projects.validate(reset);assert(resetGuide.steps[3].uniqueCraft,"Known count after a bench reset was not retained")
 legacy.steps[2].action="Link with an unrelated service";assert(not projects.validate(legacy).steps[2].uniqueCraft,"Edited action incorrectly kept its typed pickup")
 local corrupt=copyTable(saved);corrupt.id="corrupt-random-link";corrupt.startingItem=raw.."\nCorrupted"
 corrupt.steps[1].action=unique.guideAction("tainted_jeweller",1,"Armourer's Scrap",true);corrupt.steps[1].uniqueCraft={method="tainted_jeweller",count=1}
 local corruptGuide=projects.validate(corrupt);assert(corruptGuide.steps[2].uniqueCraft,"Corrupted guide lost its bench action")
 build.savers.CraftingProjects:Upsert(corruptGuide)
 local corruptRules=filters.generate(build,filters.profile("corrupt-link","Corrupt link"));local corruptNames={};for _,r in ipairs(corruptRules) do if r.origin=="craft:corrupt-random-link" then corruptNames[r.title]=true end end
 assert(corruptNames["Tainted Jeweller's Orb"] and corruptNames["Orb of Fusing"] and corruptNames["Vaal Orb"],"Corrupted guide lost a filter pickup")

 if output then ui:frame():write(output.."/"..size[1].."-unique-random-guide.json") end
 ui:restore()
end
print("UNIQUE_RANDOM_GUIDE_UI_OK")
