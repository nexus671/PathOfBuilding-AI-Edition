local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local preview=require("Modules.CraftingBenchRarityPreview");local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
local magic=preview.preview(raw,"MAGIC",42);local rare=preview.preview(raw,"RARE",42,magic.state)
assert(magic.conditional and rare.conditional and magic.state.rarity=="MAGIC" and rare.state.rarity=="RARE")
assert(not magic.probability and not rare.price and preview.preview(raw,"MAGIC",42).itemText==magic.itemText)
assert(not pcall(preview.preview,raw,"UNIQUE",42,nil,"Goldrim"))
local refs=preview.uniqueCandidates(raw);local found=false;for _,entry in ipairs(refs.candidates) do if entry.title=="Ezomyte Peak" then found=true end end;assert(found)
local unique=preview.preview(raw,"UNIQUE",42,nil,"Ezomyte Peak");assert(unique.conditional and unique.itemText:find("Ezomyte Peak",1,true))
local template=preview.proposal(raw,magic,"Helmet","Conditional","example");local entry=template.inventory[1];entry.title="Renamed";assert(require("Modules.CraftingInventory").project(entry).notes==template.notes)
assert(template.originNote==template.notes);local migrated=copyTable(template);migrated.originNote=nil;assert(require("Modules.CraftingProjects").validate(migrated).originNote==template.notes)
local prior=copyTable(template);prior.inventory={};assert(table.concat(require("Modules.CraftingProjects").reviewChanges(prior,template),"\n"):find("source note: Conditional",1,true))
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local project={id="bench-example",title="Bench example",slot="Helmet",startingItem=raw,goals={},steps={{action="Original guide"}}};build.savers.CraftingProjects:Upsert(project)
 local c=require("Classes.CraftingSimulatorControl").Open(build,project);c.page:SelByValue("Craft settings");c.page.selFunc();assert(c.benchRarity:IsShown());c.benchRarity:Click()
 local popup=main.popups[1].controls;assert(not popup.copy:IsEnabled() and not popup.keep:IsEnabled());popup.generate:Click();assert(popup.copy:IsEnabled() and #popup.exampleMods.list>0);popup.keep:Click();assert(not popup.keep:IsEnabled())
 assert(build.savers.CraftingProjects.projects[2].run.state.rarity=="MAGIC");assert(build.savers.CraftingProjects.projects[2].notes:find("Conditional",1,true))
 popup.outcome:SelByValue("UNIQUE","val");popup.outcome.selFunc();assert(not popup.copy:IsEnabled());popup.unique:SelByValue("Ezomyte Peak","val");popup.unique.selFunc();popup.generate:Click();assert(popup.copy:IsEnabled());popup.keep:Click()
 assert(build.savers.CraftingProjects.projects[3].startingItem:find("Ezomyte Peak",1,true));assert(build.savers.CraftingProjects.projects[1].steps[1].action=="Original guide")
 if output then ui:frame():write(output.."/"..size[1].."-bench-rarity-example.json") end
 if size[1]==960 then
  main.popups={};build.savers.CraftingProjects:Upsert(template);local resumed
  local inventory=require("Classes.CraftingInventoryControl").Open(build,{resume=function(project) resumed=project end});assert(inventory.source:IsEnabled());if output then ui:frame():write(output.."/960-inventory-source.json") end;inventory.source:Click();local source=main.popups[1].controls;assert(#source.details.list>0 and source.details.list[1][1]:find("Conditional",1,true));if output then ui:frame():write(output.."/960-inventory-source-detail.json") end;main:ClosePopup();inventory.itemTitle:SetText("User renamed",true);inventory.rename:Click();inventory.resume:Click()
  assert(resumed and resumed.notes==template.notes and resumed.run.state.rarity=="MAGIC");resumed.notes="My own notes"
  local resumedControl=require("Classes.CraftingSimulatorControl").Open(build,resumed);resumedControl.keepItem:Click();assert(build.savers.CraftingProjects.projects[5].inventory[1].originNote==template.notes);assert(build.savers.CraftingProjects.projects[5].originNote==template.notes)
  local xml=build:SaveDB("Bench examples");loadBuildFromXML(xml,"Bench examples");assert(build.savers.CraftingProjects.projects[2].run.state.rarity=="MAGIC");assert(build.savers.CraftingProjects.projects[3].notes:find("Conditional",1,true));assert(build.savers.CraftingProjects.projects[4].inventory[1].originNote==template.notes);assert(build.savers.CraftingProjects.projects[5].inventory[1].originNote==template.notes);assert(build.savers.CraftingProjects.projects[5].originNote==template.notes)
  local legacy=copyTable(build.savers.CraftingProjects.projects[5]);legacy.originNote=nil;legacy.notes="Updated by older client";build.savers.CraftingProjects:Upsert(legacy);assert(build.savers.CraftingProjects.projects[5].originNote==template.notes)
 end
 ui:restore();main.popups={}
end
newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
local emptyProject={id="bench-empty",title="No unique reference",slot="Weapon 2",startingItem="Rarity: NORMAL\nTwig Spirit Shield\nItem Level: 86",goals={},steps={}}
build.savers.CraftingProjects:Upsert(emptyProject)
local emptyControl=require("Classes.CraftingSimulatorControl").Open(build,emptyProject);emptyControl.page:SelByValue("Craft settings");emptyControl.page.selFunc();emptyControl.benchRarity:Click()
local emptyPopup=main.popups[1].controls;emptyPopup.outcome:SelByValue("UNIQUE","val");emptyPopup.outcome.selFunc()
assert(#emptyPopup.unique.list==0 and not emptyPopup.generate:IsEnabled());assert(emptyPopup.generate.tooltipText():find("No bundled unique references",1,true))
emptyPopup.outcome:SelByValue("MAGIC","val");emptyPopup.outcome.selFunc();assert(emptyPopup.generate:IsEnabled())
ui:restore();main.popups={}
newBuild();local browse=UI.install({width=960,height=640});browse:bind(build)
local collection={id="inventory-cache",title="Inventory cache",slot="Helmet",startingItem=raw,goals={},steps={}}
local snapshots=require("Modules.CraftingInventory");collection.inventory={snapshots.capture(collection,preview.preview(raw,"MAGIC",42).state,"Magic"),snapshots.capture(collection,preview.preview(raw,"RARE",42).state,"Rare")};build.savers.CraftingProjects:Upsert(collection)
local inventoryControl=require("Classes.CraftingInventoryControl").Open(build,{});local first=inventoryControl.savedItemMods.list;local firstText={};for _,row in ipairs(first) do firstText[#firstText+1]=row[1] or "" end
inventoryControl.items:OnKeyDown("RIGHT");local secondText={};for _,row in ipairs(inventoryControl.savedItemMods.list) do secondText[#secondText+1]=row[1] or "" end;assert(table.concat(firstText,"\n")~=table.concat(secondText,"\n"))
inventoryControl.items:OnKeyDown("LEFT");local again={};for _,row in ipairs(inventoryControl.savedItemMods.list) do again[#again+1]=row[1] or "" end;assert(table.concat(firstText,"\n")==table.concat(again,"\n"));browse:restore();main.popups={}
print("BENCH_RARITY_PREVIEW_OK")
