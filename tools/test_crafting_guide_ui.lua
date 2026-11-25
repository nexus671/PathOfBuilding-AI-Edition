-- Navigate a long guide through the real native controls at supported widths.
local directory=assert(arg[1],"Supply an output directory")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local project={id="long-guide",title="Long crafting guide",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
	for i=1,176 do project.steps[i]={action="Craft step "..i,stopWhen="Stop "..i,onFailure="Recover "..i} end
	local store=build.savers.CraftingProjects;store:Upsert(project)
	require("Classes.CraftingProjectControl").Open(build);ui:click("browseSteps")
	assert(main.popups[1].title=="Crafting guide steps","Guide browser did not open")
	ui:frame():write(directory.."/"..size[1].."-guide-steps-overview.json")
	local c=main.popups[1].controls;assert(c.next:IsEnabled(),"Long guides must have another page");ui:click("next");assert(c.results.list[1].index==101,"Next page did not advance")
	ui:text("search","Recover 176");local x,y=c.results:GetPos();ui:clickAt(x+20,y+12)
	ui:frame():write(directory.."/"..size[1].."-guide-steps-selected.json")
	ui:click("edit");ui:frame():write(directory.."/"..size[1].."-guide-steps-edit.json")
	ui:text("action","Updated craft instruction");ui:text("stop","Updated goal");ui:click("saveStep")
	assert(store.projects[1].steps[176].action=="Updated craft instruction" and store.projects[1].steps[176].onFailure=="Recover 176","Editing the step lost its notes")
	ui:click("toggle");assert(store.projects[1].steps[176].done,"Selected step was not completed")
	ui:frame():write(directory.."/"..size[1].."-guide-steps-done.json")
	ui:choose("status","To do");assert(not c.toggle:IsEnabled(),"A filtered-out step must not remain selected")
	ui:choose("status","Done");x,y=c.results:GetPos();ui:clickAt(x+20,y+12)
	ui:click("toggle");assert(not store.projects[1].steps[176].done,"Step was not restored to to-do")
	ui:choose("status","All steps");x,y=c.results:GetPos();ui:clickAt(x+20,y+12);ui:click("remove")
	assert(main.popups[1].title=="Remove crafting step","Removing a step must be confirmed")
	ui:frame():write(directory.."/"..size[1].."-guide-steps-remove.json");ui:click("confirm")
	assert(#store.projects[1].steps==175,"The selected step was not removed")
	ui:frame():write(directory.."/"..size[1].."-guide-steps-undo.json");ui:click("undoRemove")
	assert(#store.projects[1].steps==176 and store.projects[1].steps[176].onFailure=="Recover 176","Undo did not restore the step and its notes")
	ui:click("close");ui:click("close");ui:click("aiBuild");build.planningWorkspace:Show("crafting");ui:click("tab_plan")
	ui:frame():write(directory.."/"..size[1].."-guide-steps-workspace.json")
	ui:click("browseSteps");assert(main.popups[1].title=="Crafting guide steps","Workspace guide browser did not open")
	ui:restore();main.popups={}
end
print("CRAFTING_GUIDE_UI_OK",21)
