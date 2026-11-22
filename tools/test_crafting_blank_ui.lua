-- Exercise a reversible blank starting item without modifying saved builds.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local projects=require("Modules.CraftingProjects")
local original="Rarity: RARE\nExample Belt\nStygian Vise\nItem Level: 83\nCatalyst: Prismatic\nCatalystQuality: 20\n+54% to Cold Resistance\nCorrupted"
local target="Rarity: NORMAL\nStygian Vise\nItem Level: 86"
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 require("Classes.CraftingProjectWizard").Open(build,nil,original,"Belt",nil,function() end,function() end)
 local c=main.popups[1].controls;c.target:SetText(target)
 assert(not c.undoBlank:IsEnabled(),"Undo should start unavailable")
 ui:click("blankStarting");assert(c.starting.buf=="Rarity: NORMAL\nStygian Vise\nItem Level: 83","Blank base is incorrect")
 assert(c.target.buf==target,"Blank base changed the target");assert(not c.blankStarting:IsEnabled(),"Blanking twice could lose the original")
 local model=require("Modules.CraftingSimulator").model(c.starting.buf);assert(#model.initial.affixes==0 and not model.initial.corrupted,"Blank base retained item properties")
 if output then ui:frame():write(output.."/"..size[1].."-crafting-blank-base.json") end
 ui:click("undoBlank");assert(c.starting.buf==original and c.target.buf==target,"Undo did not restore the original starting item")
 ui:click("blankStarting");ui:text("starting",c.starting.buf.."\nQuality: 1");assert(not c.undoBlank:IsEnabled(),"Undo could overwrite later edits")
 local ok=pcall(projects.blankBase,"Rarity: NORMAL\nIron Hat");assert(not ok,"Missing item level was accepted")
 local equipped=build.itemsTab.slots.Belt.selItemId;ui:click("blankStarting");ui:click("next");ui:click("next");ui:click("next");ui:click("save")
 local saved=assert(build.savers.CraftingProjects.projects[1]);assert(saved.startingItem=="Rarity: NORMAL\nStygian Vise\nItem Level: 83" and saved.targetItem==target,"Saved project changed its starting item or target")
 assert(build.itemsTab.slots.Belt.selItemId==equipped,"Keeping the guide changed equipped gear")
 local xml={};build.savers.CraftingProjects:Save(xml);local reopened=projects.new(build);reopened:Load(xml)
 assert(reopened.projects[1].startingItem==saved.startingItem and reopened.projects[1].targetItem==target,"Reopening changed the guide")
 ui:restore()
end
print("CRAFTING_BLANK_BASE_UI_OK")
