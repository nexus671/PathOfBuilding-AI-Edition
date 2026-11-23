-- Exercise conditional map-corruption previews and save/reopen without a window.
local directory=assert(arg[1],"Supply an output directory")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
local map=require("Modules.MapCraftingData")
local currency=require("Modules.MapCurrency")
for _,tier in ipairs({1,5,15}) do
 local input={baseId="Metadata/Items/Maps/MapKeyTier"..tier,tier=tier,itemLevel=83,rarity="rare",selected={},observedEffects={}}
 local before=copyTable(input);local result=currency.perform(input,"vaal_tier_up",42);local next=result.state
 assert(tableDeepEquals(input,before),"Tier-up preview changed its input")
 assert(next.tier==tier+1 and next.baseId=="Metadata/Items/Maps/MapKeyTier"..(tier+1) and next.itemLevel==83 and next.corrupted and next.vaalPreview and next.vaalTierUpPreview,"Invalid tier-up result")
 assert(#next.selected>=4 and #next.selected<=6 and result.note:find("unchanged item level",1,true),"Tier-up assumptions or modifiers missing")
 assert(tableDeepEquals(next,currency.perform(input,"vaal_tier_up",42).state),"Tier-up result is not reproducible")
end
for _,input in ipairs({
 {baseId="Metadata/Items/Maps/MapKeyTier16",tier=16,itemLevel=83,rarity="rare",selected={}},
 {baseId="Metadata/Items/Maps/MapKeyTier5",tier=5,itemLevel=83,rarity="magic",selected={}},
 {baseId="Metadata/Items/Maps/MapWorldsStrand",tier=5,itemLevel=83,rarity="rare",selected={}},
 {baseId="Metadata/Items/Maps/MapKeyTier5",tier=5,itemLevel=83,rarity="rare",selected={},plannedDeified=true},
}) do assert(not pcall(currency.perform,input,"vaal_tier_up",42),"Unsupported tier-up was accepted") end
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
 ui:frame():write(directory.."/"..size[1].."-map-vaal-reroll.json");ui:click("close")
 c=require("Classes.MapModifierControl").Open({initial=rare,keep=function(value) saved=require("Modules.AtlasPlanner").validateMapDraft(value);return value.id end})
 ui:click("currency");ui:text("search","Vaal: +1 tier reroll");ui:click("choose")
 assert(c.tier:GetSelValueByKey("val")==6 and c.rarity:GetSelValueByKey("val")=="corrupted_rare","Tier-up preview did not update the map")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-tier-up.json");ui:click("keep")
 assert(saved.tier==6 and saved.baseId=="Metadata/Items/Maps/MapKeyTier6" and saved.vaalPreview and saved.vaalTierUpPreview,"Tier-up preview was not saved")
 ui:click("close");c=require("Classes.MapModifierControl").Open({initial=saved})
 assert(c.tier:GetSelValueByKey("val")==6 and c.status.label:find("Conditional tier-up",1,true),"Reopened tier-up preview lost its assumption label")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-tier-up-reopened.json");ui:restore();main.popups={}
end
print("MAP_VAAL_UI_OK",21)
