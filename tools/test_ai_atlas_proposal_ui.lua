-- Review an AI Atlas replacement through native proposal controls.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local bridge=require("Modules.DesktopBuildBridge");local atlas=require("Modules.AtlasPlanner")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local original=atlas.connect({id="atlas-review",title="Atlas review",version="3.30.0c",budget=150,nodes={}}, {57123})
	original.genesis={version="3.30.0d",nodes={19912,53412}};original.strategy={maps="Strand Map",scarabs="",requirements="",avoid="",notes=""}
	original.mapDrafts={{id="planned",title="Planned map",patch="3.30.0.2.2",baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}}
	build.savers.AtlasPlans:Upsert(original)
	local proposed=copyTable(original);proposed.nodes={};proposed.genesis.nodes={19912};proposed.strategy=nil;proposed.mapDrafts=nil
	bridge.prepared=bridge.prepare(build,{mode="edit",title="Revise Atlas",baseRevision=bridge.revision(build),operations={{type="set_atlas_plan",plan=proposed}}})
	require("Classes.BuildProposalControl").Review();ui:choose("page","Changes")
	local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," "):gsub("%s+"," ")
	for _,expected in ipairs({"Atlas passives:","Genesis passives: 0 added, 1 removed", "Removed Atlas passive:","Removed Genesis passive: Currency / Encrusted Fruit", "Removed map draft: Planned map"}) do assert(text:find(expected,1,true),expected) end
	assert(#build.savers.AtlasPlans.plans[1].nodes>0,"Review changed the current Atlas plan")
	if output then ui:frame():write(output.."/"..size[1].."-ai-atlas-proposal.json") end
	bridge.prepared=nil
end
print("AI_ATLAS_PROPOSAL_UI_OK")
