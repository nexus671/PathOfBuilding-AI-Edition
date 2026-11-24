local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("crafting")
if output then ui:frame():write(output.."/640-crafting-compact-empty.json") end
ui:click("startProject");assert(main.popups[1]);ui:text("title","Starter helmet");ui:text("starting","Rarity: NORMAL\nIron Hat\nItem Level: 86");if output then ui:frame():write(output.."/640-crafting-compact-wizard-item.json") end
ui:click("next");ui:text("target","Rarity: NORMAL\nIron Hat\nItem Level: 86");ui:text("goals","Maximum life");if output then ui:frame():write(output.."/640-crafting-compact-wizard-target.json") end
ui:click("next");ui:text("steps","Use an Orb of Alchemy");if output then ui:frame():write(output.."/640-crafting-compact-wizard-plan.json") end
ui:click("next");if output then ui:frame():write(output.."/640-crafting-compact-wizard-review.json") end;ui:click("save");assert(#build.savers.CraftingProjects.projects==1 and build.savers.CraftingProjects.projects[1].steps[1].action=="Use an Orb of Alchemy" and build.savers.CraftingProjects.projects[1].targetItem:find("Iron Hat",1,true),"Wizard did not keep the crafting guide")
print("CRAFTING_COMPACT_WIZARD_OK");ui:restore()
