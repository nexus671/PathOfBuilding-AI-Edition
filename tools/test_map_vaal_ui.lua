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
local templeInput={baseId="Metadata/Items/Maps/MapKeyTier16",tier=16,itemLevel=83,rarity="rare",selected={}}
local temple=currency.perform(templeInput,"vaal_temple",42)
assert(temple.state.baseId=="Metadata/Items/Maps/MapWorldsVaalTemple" and temple.state.tier==16 and temple.state.corrupted and temple.state.vaalPreview,"Invalid Vaal Temple preview")
assert(temple.baseImplicit and temple.baseImplicit.text:find("10 additional guarded Vaal Vessels",1,true),"Vaal Temple base implicit is missing")
local copiedText="Item Class: Maps\nRarity: Rare\nAncient Example\nVaal Temple Map\n--------\nMap Tier: 16\nItem Level: 83\n--------\nArea contains 10 additional guarded Vaal Vessels (implicit)\n--------\nMonsters have 100% increased Area of Effect\n--------\nTravel to this Map by using it in a personal Map Device.\n--------\nCorrupted"
local copiedMap=require("Modules.MapClipboard").parse(copiedText)
assert(copiedMap.baseImplicitObserved and copiedMap.baseImplicit.id==temple.baseImplicit.id and not copiedMap.state.observedEffects,"Copied Vaal Temple base implicit was not recognized")
local dualText=copiedText:gsub("Area contains 10 additional guarded Vaal Vessels %(implicit%)","+15%% Item Rarity (implicit)\nArea contains 10 additional guarded Vaal Vessels (implicit)")
local dualMap=require("Modules.MapClipboard").parse(dualText)
assert(dualMap.baseImplicitObserved and dualMap.state.implicit and dualMap.state.implicit.id=="MapCorruptionItemRarity" and dualMap.state.implicit.value==15 and not dualMap.state.observedEffects,"Base and corruption implicits were not kept separately")
local otherText=copiedText:gsub("Vaal Vessels %(implicit%)","Vaal Vessels (implicit)\nArea is Influenced by the Originator's Memories (implicit)")
local otherMap=require("Modules.MapClipboard").parse(otherText)
assert(otherMap.state.observedEffects and #otherMap.state.observedEffects==1 and otherMap.state.observedEffects[1].text=="Area is Influenced by the Originator's Memories","Other copied implicits were lost")
local repeatedText=copiedText:gsub("Vaal Vessels %(implicit%)","Vaal Vessels (implicit)\nArea contains 10 additional guarded Vaal Vessels (implicit)")
assert(not pcall(require("Modules.MapClipboard").parse,repeatedText),"Duplicate base implicits were accepted")
local invalidTemple=copyTable(templeInput);invalidTemple.tier=15;invalidTemple.baseId="Metadata/Items/Maps/MapKeyTier15"
assert(not pcall(currency.perform,invalidTemple,"vaal_temple",42),"Non-tier-16 Vaal Temple input was accepted")
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
 ui:frame():write(directory.."/"..size[1].."-map-vaal-tier-up-reopened.json");ui:click("close")
 local templeDraft=copyTable(templeInput);templeDraft.id="temple-ui";templeDraft.title="Temple";templeDraft.patch=map.source().patch
 c=require("Classes.MapModifierControl").Open({initial=templeDraft,keep=function(value) saved=require("Modules.AtlasPlanner").validateMapDraft(value);return value.id end})
 ui:click("currency");ui:text("search","Vaal: Vaal Temple outcome");ui:click("choose")
 assert(c.tier:GetSelValueByKey("val")==16 and c.rarity:GetSelValueByKey("val")=="corrupted_rare","Vaal Temple preview did not update the map")
 local rows={};for _,line in ipairs(c.affixes.list) do rows[#rows+1]=StripEscapes(line[1] or "") end
 assert(table.concat(rows," "):gsub("%s+"," "):find("10 additional guarded Vaal Vessels",1,true),"Vaal Temple base implicit is not visible")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-temple.json");ui:click("keep")
 assert(saved.baseId=="Metadata/Items/Maps/MapWorldsVaalTemple" and saved.vaalPreview,"Vaal Temple preview was not saved")
 ui:click("close");c=require("Classes.MapModifierControl").Open({initial=saved});assert(c.status.label:find("Conditional Vaal Temple",1,true),"Reopened Vaal Temple lost its assumption label")
 ui:frame():write(directory.."/"..size[1].."-map-vaal-temple-reopened.json");ui:click("close")
 local copied=copyTable(saved);copied.observedEffects={{kind="implicit",text="Area contains 10 additional guarded Vaal Vessels"}}
 c=require("Classes.MapModifierControl").Open({initial=copied,keep=function(value) saved=require("Modules.AtlasPlanner").validateMapDraft(value);return value.id end});rows={};for _,line in ipairs(c.affixes.list) do rows[#rows+1]=StripEscapes(line[1] or "") end
 local _,matches=table.concat(rows," "):gsub("%s+"," "):gsub("10 additional guarded Vaal Vessels","")
 assert(matches==1,"Copied base implicit should not be displayed twice")
 ui.clipboard=dualText;ui:click("pasteMap");ui:frame():write(directory.."/"..size[1].."-map-temple-copy-review.json");ui:click("keep")
 assert(not c.status.label:find("Conditional Vaal Temple",1,true),"Copied map was mistaken for a conditional preview")
 rows={};for _,line in ipairs(c.affixes.list) do rows[#rows+1]=StripEscapes(line[1] or "") end
 local _,copiedMatches=table.concat(rows," "):gsub("%s+"," "):gsub("10 additional guarded Vaal Vessels","")
 assert(copiedMatches==1,"Copied map should show one recognized base implicit")
 assert(table.concat(rows," "):find("+15% Item Rarity",1,true),"Copied corruption implicit is not visible")
 ui:frame():write(directory.."/"..size[1].."-map-temple-copy-applied.json");ui:click("keep")
 assert(saved.baseId=="Metadata/Items/Maps/MapWorldsVaalTemple" and saved.implicit and saved.implicit.id=="MapCorruptionItemRarity" and saved.implicit.value==15 and not saved.vaalPreview and not saved.observedEffects,"Copied map did not save both implicits correctly")
 ui:click("close");c=require("Classes.MapModifierControl").Open({initial=saved});rows={};for _,line in ipairs(c.affixes.list) do rows[#rows+1]=StripEscapes(line[1] or "") end
 local reopened=table.concat(rows," "):gsub("%s+"," ");assert(reopened:find("10 additional guarded Vaal Vessels",1,true) and reopened:find("+15% Item Rarity",1,true),"Reopened copied map lost an implicit")
 ui:restore();main.popups={}
end
print("MAP_VAAL_UI_OK",33)
