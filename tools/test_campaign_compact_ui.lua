local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build)
for _,size in ipairs({{640,480},{720,600},{960,640}}) do
 ui:resize(size[1],size[2]);local kept;require("Classes.LootFilterCampaignControl").Open(build,nil,function(value) kept=value end,"Normal")
 for _,name in ipairs({"Setup","Weapons","Armour","Recipes"}) do ui:click("page"..name);if output then ui:frame():write(output.."/"..size[1].."-campaign-compact-"..name..".json") end end
 ui:click("recipe5");ui:click("rareSetSlots");ui:click("slot2");ui:click("keep");ui:click("starters");if output then ui:frame():write(output.."/"..size[1].."-campaign-compact-starters.json") end;ui:click("starter1")
 ui:click("pageWeapons");ui:click("weapons2");ui:click("pageArmour");ui:click("defences1");ui:click("pageSetup");ui:text("minAreaLevel","10");ui:click("keep")
 assert(kept and #kept.weapons==3 and #kept.defences==4 and #kept.recipes==1 and kept.minAreaLevel==10 and #kept.rareSetSlots==2,"Campaign settings lost")
end
ui:resize(1280,720);local regular;local controls=require("Classes.LootFilterCampaignControl").Open(build,nil,function(value) regular=value end,"Normal");assert(not controls.page,"Regular layout changed to compact pages");ui:click("weapons1");ui:click("defences1");ui:click("recipe1");ui:click("keep");assert(regular and #regular.weapons==1 and #regular.defences==1 and #regular.recipes==1,"Regular campaign settings lost")
print("CAMPAIGN_COMPACT_OK");ui:restore()
