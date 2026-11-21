-- Exercise deleting and restoring an Atlas plan through the native controls.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local store=build.savers.AtlasPlans
	store:Upsert({id="atlas-undo",title="Saved plan",version="3.30.0c",budget=120,nodes={},genesis={version="3.30.0d",nodes={19912,53412}}})
	require("Classes.AtlasPlannerControl").Library(build)
	assert(not main.popups[1].controls.undoRemove:IsEnabled(),"Undo should start unavailable")
	ui:click("delete");assert(#store.plans==0 and main.popups[1].controls.undoRemove:IsEnabled(),"Deleted plan cannot be restored")
	if output then ui:frame():write(output.."/"..size[1].."-atlas-removal.json") end
	ui:click("undoRemove");assert(#store.plans==1 and #store.plans[1].genesis.nodes==2,"Restoring lost the saved plan or Genesis allocations")
	assert(not main.popups[1].controls.undoRemove:IsEnabled(),"Undo stayed available after restoration")
	assert(main.popups[1].controls.info.label:find("Save",1,true),"Restoration did not remind the user to save")
end
print("ATLAS_DELETE_UNDO_UI_OK")
