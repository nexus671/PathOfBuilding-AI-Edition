-- Review an AI journey replacement through the native proposal controls.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local bridge=require("Modules.DesktopBuildBridge");local journey=require("Modules.BuildJourney")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local current=journey.empty();current.resources={{id="chaos",title="Chaos Orbs"}};current.ledger={{id="stash",resourceId="chaos",kind="add",amount=100,at=1}};current.milestones={{id="maps",title="Reach maps"}}
	build.savers.BuildJourney:Replace(current)
	bridge.prepared=bridge.prepare(build,{mode="edit",title="Revise journey",baseRevision=bridge.revision(build),operations={{type="set_build_journey",journey=journey.empty()}}})
	require("Classes.BuildProposalControl").Review();ui:choose("page","Changes")
	local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," "):gsub("%s+"," ")
	assert(text:find("Removed milestone: Reach maps [maps]",1,true) and text:find("Removed ledger entry: add 100 Chaos Orbs [stash]",1,true),"Proposal review omitted journey removals")
	assert(#build.savers.BuildJourney.data.ledger==1,"Review changed the current journey")
	if output then ui:frame():write(output.."/"..size[1].."-ai-journey-proposal.json") end
	bridge.prepared=nil
end
print("AI_JOURNEY_PROPOSAL_UI_OK")
