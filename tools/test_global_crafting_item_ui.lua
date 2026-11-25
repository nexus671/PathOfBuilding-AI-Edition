local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local sim=require("Modules.CraftingSimulator");local inventory=require("Modules.CraftingInventory")
local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
	newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
	local project={id="navigation-test",title="Helmet project",slot="Helmet",startingItem=raw,goals={},steps={},inventory={}}
	local state=sim.perform(raw,{method="alchemy"},42).state
	for i=1,30 do local item=inventory.capture(project,state,i==30 and "Needle item" or "Other item");item.id="snapshot-"..i;item.at=1700000100-i;project.inventory[i]=item end
	build.savers.CraftingProjects:Upsert(project);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build)
	local workspace=build.planningWorkspace;workspace:Show("crafting",{kind="workbench",project=project});workspace.controls.currency_alchemy:Click();workspace.controls.item:Click()
	local original=workspace:CraftingDraft(project.id).state;assert(original.rarity=="RARE")
	require("Classes.PlanningToolsControl").Open(build);ui:text("search","Needle item");assert(main.popups[1].controls.choose:IsEnabled())
	if output then ui:frame():write(output.."/"..size[1].."-global-crafting-item-search.json") end
	ui:click("choose");local controls=main.popups[1].controls
	assert(controls.itemTitle.buf=="Needle item" and controls.items.scroll>0 and controls.resume:IsEnabled())
	if output then ui:frame():write(output.."/"..size[1].."-global-crafting-item-selected.json") end
	ui:click("resume");local draft=build.planningWorkspace.cache.crafting.layout.snapshot()
	assert(draft and draft.kind=="workbench" and draft.project.startingItem==raw);assert(#build.savers.CraftingProjects.projects[1].inventory==30);assert(tableDeepEquals(original,workspace:CraftingDraft(project.id).state))
	ui:restore();main.popups={}
end
print("GLOBAL_CRAFTING_ITEM_NAVIGATION_OK")
