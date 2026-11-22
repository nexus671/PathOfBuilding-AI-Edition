-- Review a saved filter tracking change through the native profile tools.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local profile=require("Modules.LootFilters").profile("review-ui","Review filter");profile.trackBuildPickups=true
	build.savers.LootFilters:Upsert(profile);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters")
	ui:click("manage");ui:text("search","Disable pickup update notices");ui:click("choose")
	ui:click("manage");ui:text("search","Review changes");ui:click("choose")
	assert(main.popups[1].title=="Filter changes","Filter review did not open")
	local details={};for _,row in ipairs(main.popups[1].controls.details.list) do details[#details+1]=StripEscapes(row[1] or "") end
	assert(table.concat(details," "):find("Build pickup notices: Enabled -> Disabled",1,true),"Review omitted the notice setting")
	if output then ui:frame():write(output.."/"..size[1].."-filter-tracking-review.json") end
	ui:click("close")
	local project={id="manual-notice",title="Helmet crafting",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}};build.savers.CraftingProjects:Upsert(project)
	ui:click("generate");for i=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].title=="Review build pickups","Manual guide notice did not open")
	local notice={};for _,row in ipairs(main.popups[1].controls.details.list) do notice[#notice+1]=StripEscapes(row[1] or "") end
	assert(table.concat(notice," "):find("Written guide steps",1,true),"Manual guide notice was not visible")
	if output then ui:frame():write(output.."/"..size[1].."-filter-pickup-notice.json") end
	ui:click("choose");assert(build.planningWorkspace.page=="crafting","Pickup notice did not open the crafting source")
	assert(build.planningWorkspace.controls.libraryPage:GetSelValue()=="Plan","Manual guide notice did not open the saved guide")
	assert(build.planningWorkspace.selections.crafting==project.id,"Manual guide notice opened a different project")
	if output then ui:frame():write(output.."/"..size[1].."-filter-notice-guide.json") end
	build.planningWorkspace:Show("filters");local restored=build.planningWorkspace.cache.filters.layout.snapshot()
	assert(restored.dirty and restored.data.profiles[1].trackBuildPickups==true,"Opening a notice discarded the generated filter draft")
	local linked=false;for _,rule in ipairs(restored.data.profiles[1].rules) do if rule.origin=="craft:"..project.id then linked=true end end
	assert(linked,"Opening a notice discarded the project's generated pickup")
end
for _,kind in ipairs({"atlas","budget"}) do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	if kind=="atlas" then
		build.savers.AtlasPlans:Upsert({id="warning-atlas",title="Atlas warning",version="3.30.0c",budget=150,nodes={},strategy={maps="Strand Map"}})
	else
		local journey=require("Modules.BuildJourney").empty();journey.resources={{id="warning-budget",title="Beach Maps"}};build.savers.BuildJourney:Replace(journey)
	end
	local profile=require("Modules.LootFilters").profile("source-ui","Source test");build.savers.LootFilters:Upsert(profile);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters")
	ui:click("generate");for i=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].title=="Review build pickups",kind.." notice did not open")
	ui:click("choose");assert(build.planningWorkspace.page==(kind=="atlas" and "atlas" or "journey"),kind.." notice opened the wrong source")
end
do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	local project={id="preserve-work",title="Helmet crafting",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={{action="Use a rare currency"}}};build.savers.CraftingProjects:Upsert(project)
	local profile=require("Modules.LootFilters").profile("draft-check","Filter");build.savers.LootFilters:Upsert(profile)
	local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace;build.viewMode="PLANNER";workspace:Show("crafting")
	ui:click("native");ui:choose("page","Emulate item");ui:click("currency_transmute");ui:click("item")
	local before=workspace.cache.crafting.layout.snapshot().state;assert(before and #before.affixes>0,"Working craft was not created")
	workspace:Show("filters");ui:click("generate");for i=1,2000 do ui:frame();if main.popups[1] and main.popups[1].title=="Review build pickups" then break end end
	assert(main.popups[1] and main.popups[1].title=="Review build pickups");ui:click("choose")
	ui:click("tab_item");ui:click("native");local after=workspace.cache.crafting.layout.snapshot().state
	assert(tableDeepEquals(before,after) and tableDeepEquals(after,before),"Opening the guide discarded the working craft")
end
print("FILTER_REVIEW_UI_OK")
