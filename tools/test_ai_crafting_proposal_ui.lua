-- Review an AI crafting-project update through native proposal controls.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local bridge=require("Modules.DesktopBuildBridge")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local recipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}
	local original={id="review",title="Helmet guide",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={"High life"},steps={{action="Use an Orb of Alchemy"},{action="Finish the helmet",done=true}},nativeRecipe=recipe,recipeAlternatives={{name="Alternative",recipe=copyTable(recipe)}},primarySimulation={trials=20,maxActions=3,seed=7}}
	original.simulation={trials=100,successes=5,patch="3.30",observedAt=1,notes="Old assumptions"}
	build.savers.CraftingProjects:Upsert(original)
	local proposed=copyTable(original);table.remove(proposed.steps,2);proposed.recipeAlternatives={};proposed.primarySimulation=false
	proposed.simulation.notes="New assumptions"
	bridge.prepared=bridge.prepare(build,{mode="edit",title="Revise guide",baseRevision=bridge.revision(build),operations={{type="set_crafting_project",project=proposed}}})
	require("Classes.BuildProposalControl").Review();ui:choose("page","Changes")
	local lines={};for _,row in ipairs(main.popups[1].controls.details.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," "):gsub("%s+"," ")
	for _,expected in ipairs({"Removed guide step 2: [done] Finish the helmet","Alternative recipe 'Alternative' removed","Primary simulation defaults: 20 trials, 3 actions, seed 7 -> (not saved)","Supplied simulation notes: Old assumptions -> New assumptions"}) do assert(text:find(expected,1,true),expected) end
	assert(#build.savers.CraftingProjects.projects[1].steps==2,"Review changed the saved guide")
	if output then ui:frame():write(output.."/"..size[1].."-ai-crafting-proposal.json") end
	bridge.prepared=nil
end
print("AI_CRAFTING_PROPOSAL_UI_OK")
