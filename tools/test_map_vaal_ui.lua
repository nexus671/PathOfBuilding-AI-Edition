-- Exercise conditional map-corruption previews and save/reopen without a window.
local directory=assert(arg[1],"Supply an output directory")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
local map=require("Modules.MapCraftingData")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local base={baseId="Metadata/Items/Maps/MapKeyTier5",tier=5,itemLevel=68,rarity="normal",selected={},id="vaal-implicit-ui",title="Map",patch=map.source().patch}
 local saved;local c=require("Classes.MapModifierControl").Open({initial=base,keep=function(value) saved=require("Modules.AtlasPlanner").validateMapDraft(value);return value.id end})
 ui:click("currency");ui:text("search","Vaal: corruption implicit");ui:frame():write(directory.."/"..size[1].."-map-vaal-implicit-picker.json")
 ui:click("choose");assert(c.rarity:GetSelValueByKey("val")=="corrupted_normal","Map should be corrupted and retain normal rarity")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-implicit-result.json");ui:click("keep");assert(saved.implicit and saved.vaalPreview,"Implicit outcome was not saved");ui:click("close")
 c=require("Classes.MapModifierControl").Open({initial=saved});assert(c.status.label:find("conditional Vaal preview",1,true),"Reopened result lost its conditional label")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-implicit-reopened.json");ui:click("close")
 c=require("Classes.MapModifierControl").Open({initial=base});ui:click("currency");ui:text("search","Vaal: no other change");ui:click("choose")
 assert(c.rarity:GetSelValueByKey("val")=="corrupted_normal","Unchanged outcome did not corrupt the map")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-unchanged.json");ui:click("close")
 local rare=require("Modules.MapCurrency").perform(base,"alchemy",123).state;rare.id="vaal-reroll";rare.title="Rare map";rare.patch=map.source().patch
 c=require("Classes.MapModifierControl").Open({initial=rare});ui:click("currency");ui:text("search","Vaal: reroll at same tier");ui:click("choose")
 assert(c.rarity:GetSelValueByKey("val")=="corrupted_rare","Reroll outcome did not corrupt the map")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-reroll.json");ui:restore();main.popups={}
end
print("MAP_VAAL_UI_OK",15)
