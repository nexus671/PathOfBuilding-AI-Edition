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
end
print("FILTER_REVIEW_UI_OK")
