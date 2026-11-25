-- Exercise a linked crafting guide directly from Journey without changing gear.
local directory=assert(arg[1],"Supply an output directory")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local project={id="linked-guide",title="Helmet craft",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Find a base",onFailure="Try another map"},{action="Roll life"}}}
	build.savers.CraftingProjects:Upsert(project)
	local journey=require("Modules.BuildJourney").empty();journey.wishlist={{id="hat",title="Helmet upgrade",slot="Helmet",route="craft",projectId=project.id}}
	build.savers.BuildJourney:Replace(journey);ui:click("aiBuild");build.planningWorkspace:Show("journey",{page="Gear",selected="hat"})
	local function detail() local result={};for _,row in ipairs(build.planningWorkspace.controls.details.list) do result[#result+1]=row[1] or "" end;return table.concat(result," ") end
	assert(detail():find("0 / 2 steps done",1,true),"Journey did not show guide progress")
	ui:frame():write(directory.."/"..size[1].."-journey-craft-guide-before.json");ui:click("openGuide")
	assert(main.popups[1].title=="Crafting guide steps","Linked guide did not open")
	local c=main.popups[1].controls;local x,y=c.results:GetPos();ui:clickAt(x+20,y+12);ui:click("toggle");ui:click("close")
	assert(detail():find("1 / 2 steps done",1,true) and detail():find("Roll life",1,true),"Journey did not refresh guide progress")
	ui:frame():write(directory.."/"..size[1].."-journey-craft-guide-after.json")
	assert(build.viewMode=="PLANNER" and build.planningWorkspace.page=="journey","Guide changed the active planning page")
	build.planningWorkspace:Show("journey",{page="Overview",selected="hat"});assert(detail():find("1 / 2 steps done",1,true),"Overview did not show guide progress")
	ui:frame():write(directory.."/"..size[1].."-journey-craft-guide-overview.json");ui:click("openGuide");ui:click("close")
	build.savers.BuildJourney:Put("wishlist",{id="missing",title="Missing craft",slot="Helmet",route="craft",projectId="missing-project"})
	build.planningWorkspace:Show("journey",{page="Gear",selected="missing"});local button=build.planningWorkspace.controls.openGuide
	assert(button:IsShown() and not button:IsEnabled() and button.tooltipText():find("missing",1,true),"Missing guide was not explained")
	ui:frame():write(directory.."/"..size[1].."-journey-craft-guide-missing.json")
	ui:restore();main.popups={}
end
print("JOURNEY_CRAFT_GUIDE_UI_OK",12)
