-- Review an AI filter proposal through the native proposal controls.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local bridge=require("Modules.DesktopBuildBridge");local filters=require("Modules.LootFilters")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local first=filters.profile("first","First");local second=filters.profile("second","Second");second.trackBuildPickups=true
	build.savers.LootFilters:Replace({schemaVersion=1,activeId="first",profiles={first,second}})
	local changed=copyTable(second);changed.trackBuildPickups=false
	bridge.prepared=bridge.prepare(build,{mode="edit",title="Revise filters",baseRevision=bridge.revision(build),operations={{type="set_loot_filters",filters={schemaVersion=1,activeId="second",profiles={changed}}}}})
	require("Classes.BuildProposalControl").Review();ui:choose("page","Changes")
	local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
	local text=table.concat(lines," "):gsub("%s+"," ")
	assert(text:find("Active profile changed",1,true) and text:find("Profile removed",1,true) and text:find("Build pickup notices: Enabled -> Disabled",1,true),"Proposal review omitted filter changes")
	assert(#build.savers.LootFilters.data.profiles==2,"Review changed the current build")
	if output then ui:frame():write(output.."/"..size[1].."-ai-filter-proposal.json") end
	bridge.prepared=nil
end
print("AI_FILTER_PROPOSAL_UI_OK")
