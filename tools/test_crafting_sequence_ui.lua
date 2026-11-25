-- Cancelled or failed previews must not consume the next deterministic seed.
arg={};dofile("HeadlessWrapper.lua");newBuild();main.popups={}
local ui=require("Modules.HeadlessUI").install({width=1024,height=768});ui:bind(build)
local project={id="seed",title="Seed",slot="Helmet",startingItem="Rarity: NORMAL\nIron Hat\nItem Level: 86",goals={},steps={}}
build.savers.CraftingProjects:Upsert(project);local workspace=require("Modules.PlanningWorkspace").new(build);build.planningWorkspace=workspace;build.viewMode="PLANNER";workspace:Show("crafting",{kind="workbench",project=project})
local controls=workspace.controls;controls.seed:SetText("bad",true);local before=workspace.cache.crafting.layout.snapshot();controls.apply:Click()
local after=workspace.cache.crafting.layout.snapshot();assert(after.sequence==before.sequence and #after.history==#before.history);assert(main.popups[1]);main:ClosePopup()
controls.seed:SetText("123",true);ui:choose("page","Craft settings");ui:click("allflame");ui:click("use");ui:choose("page","Emulate item")
before=workspace.cache.crafting.layout.snapshot();ui:click("apply");assert(main.popups[1] and main.popups[1].title=="Allflame outcomes");ui:click("close")
after=workspace.cache.crafting.layout.snapshot();assert(after.sequence==before.sequence and #after.history==#before.history)
ui:click("apply");assert(main.popups[1].title=="Allflame outcomes");ui:click("keep");local kept=workspace.cache.crafting.layout.snapshot()
assert(kept.sequence==before.sequence+1 and #kept.history==#before.history+1)
ui:click("undo");controls.seed:SetText("0",true);controls.apply:Click()
assert(main.popups[1] and main.popups[1].title~="Allflame outcomes","An out-of-range base seed must remain invalid")
assert(workspace.cache.crafting.layout.snapshot().sequence==kept.sequence);main:ClosePopup()
controls.seed:SetText("2147483646",true);ui:click("apply")
assert(main.popups[1] and main.popups[1].title=="Allflame outcomes","A valid seed should wrap after prior actions")
ui:click("keep");ui:restore();print("CRAFT_SEQUENCE_UI_OK")
