-- cspell:ignore Duskwalk
-- Select and retain a hypothetical ordinary base implicit in the item editor.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local uiModule=require("Modules.HeadlessUI");local sim=require("Modules.CraftingSimulator");local picker=require("Modules.CraftingBaseImplicit")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=uiModule.install({width=size[1],height=size[2]});ui:bind(build)
 local raw="Rarity: NORMAL\nRuby Ring\nItem Level: 83";local model=sim.model(raw);local before=copyTable(model.initial);local kept
 local options=assert(picker.options(sim,model,model.initial));assert(#options==11 and options[1].label=="+20% to Fire Resistance" and options[11].label=="+30% to Fire Resistance")
 require("Classes.CraftingItemEditorControl").Open(model,model.initial,function(value) kept=value end)
 if output then ui:frame():write(output.."/"..size[1].."-crafting-implicit-editor.json") end
 ui:click("baseImplicit");ui:text("search","+30% to Fire Resistance");if output then ui:frame():write(output.."/"..size[1].."-crafting-base-implicit.json") end
 ui:click("choose");ui:click("keep");assert(kept and kept.baseImplicitRanges[1]==1 and kept.baseImplicitReconstructed,"Selected implicit not retained")
 assert(StripEscapes(itemLib.formatModLine(sim.toItem(model,kept).implicitModLines[1],false)):find("+30% to Fire Resistance",1,true),"Selected implicit did not render")
 local reopened=sim.model(assert(sim.itemText(model,kept)));local preview=sim.toItem(reopened,reopened.initial)
 assert(StripEscapes(itemLib.formatModLine(preview.implicitModLines[1],false)):find("+30% to Fire Resistance",1,true),"Reopening changed the selected implicit")
 local catalyst=sim.model("Rarity: NORMAL\nRuby Ring\nItem Level: 83\nCatalyst: Prismatic\nCatalystQuality: 20");local scaled=assert(picker.options(sim,catalyst,catalyst.initial));assert(scaled[1].label=="+24% to Fire Resistance" and scaled[#scaled].label=="+36% to Fire Resistance","Catalyst-scaled choices are incorrect")
 local scaledState=picker.apply(sim,catalyst,catalyst.initial,scaled[#scaled].roll);assert(StripEscapes(itemLib.formatModLine(sim.toItem(catalyst,scaledState).implicitModLines[1],false)):find("+36% to Fire Resistance",1,true),"Catalyst result differed from its choice")
 assert(before.baseImplicitRanges==nil and model.initial.baseImplicitRanges==nil,"Editing changed the original state")
 local corrupted=copyTable(model.initial);corrupted.corrupted=true;assert(not picker.options(sim,model,corrupted),"Corrupted base should be excluded")
 local fixedBase=sim.model("Rarity: NORMAL\nStygian Vise\nItem Level: 83");assert(not picker.options(sim,fixedBase,fixedBase.initial),"Fixed implicit should not offer a roll")
 local tagged=sim.model("Rarity: NORMAL\nDuskwalk Slippers\nItem Level: 83\nImplicits: 2\n{tags:attack}10% reduced Movement Speed\n47% increased Cooldown Recovery Rate of Movement Skills")
 local unsafe,why=picker.options(sim,tagged,tagged.initial);assert(not unsafe and why:find("tags or properties",1,true),"Changed implicit tags were not rejected")
 local boots=sim.model("Rarity: NORMAL\nDuskwalk Slippers\nItem Level: 83");local keptBoots
 require("Classes.CraftingItemEditorControl").Open(boots,boots.initial,function(value) keptBoots=value end)
 ui:click("baseImplicit");ui:text("search","50% increased Cooldown Recovery Rate of Movement Skills")
 if output then ui:frame():write(output.."/"..size[1].."-crafting-multi-implicit.json") end
 ui:click("choose");ui:click("keep");local result=sim.toItem(boots,assert(keptBoots))
 assert(StripEscapes(itemLib.formatModLine(result.implicitModLines[1],false))=="10% reduced Movement Speed","Other implicit changed")
 assert(StripEscapes(itemLib.formatModLine(result.implicitModLines[2],false))=="50% increased Cooldown Recovery Rate of Movement Skills","Selected implicit changed")
 local reopenedBoots=sim.model(assert(sim.itemText(boots,keptBoots)));local saved=sim.toItem(reopenedBoots,reopenedBoots.initial)
 assert(StripEscapes(itemLib.formatModLine(saved.implicitModLines[1],false))=="10% reduced Movement Speed" and StripEscapes(itemLib.formatModLine(saved.implicitModLines[2],false))=="50% increased Cooldown Recovery Rate of Movement Skills","Reopening changed the implicits")
 -- Synthetic second variable line verifies a non-default roll stays intact.
 local synthetic=sim.model("Rarity: NORMAL\nDuskwalk Slippers\nItem Level: 83");synthetic.baseImplicitTemplates[1]="(10-20)% reduced Movement Speed"
 local start=copyTable(synthetic.initial);start.baseImplicitRanges={0.25,0.4};start.baseImplicitReconstructed=true;start=sim.validateState(synthetic,start)
 local candidates=assert(picker.options(sim,synthetic,start));local selected
 for _,candidate in ipairs(candidates) do if candidate.lineIndex==2 and candidate.roll==1 then selected=candidate;break end end
 assert(selected and selected.statePatch.baseImplicitRanges[1]==0.25,"Choice did not preserve the other roll")
 local selectedItem=sim.toItem(synthetic,picker.apply(sim,synthetic,start,selected.roll,selected.lineIndex))
 assert(StripEscapes(itemLib.formatModLine(selectedItem.implicitModLines[1],false))=="13% reduced Movement Speed","Selecting another line changed the existing roll")
 local bow=sim.model("Rarity: NORMAL\nHedron Bow\nItem Level: 83");local bowOptions=assert(picker.options(sim,bow,bow.initial));local bowChoice
 for _,entry in ipairs(bowOptions) do if entry.label=="Adds 46 to 83 Fire Damage" then bowChoice=entry;break end end
 assert(bowChoice and #bowOptions==150 and bowChoice.roll[1]==0 and bowChoice.roll[2]==1,"Independent implicit values missing")
 local bowKept
 require("Classes.CraftingItemEditorControl").Open(bow,bow.initial,function(value) bowKept=value end)
 ui:click("baseImplicit");ui:text("search","Adds 46 to 83 Fire Damage")
 if output then ui:frame():write(output.."/"..size[1].."-crafting-damage-implicit.json") end
 ui:click("choose");ui:click("keep");assert(bowKept,"Independent implicit choice was not kept")
 assert(StripEscapes(itemLib.formatModLine(sim.toItem(bow,bowKept).implicitModLines[1],false))==bowChoice.label,"UI changed the independent implicit values")
 local bowState=picker.apply(sim,bow,bow.initial,bowChoice.roll,bowChoice.lineIndex)
 assert(StripEscapes(itemLib.formatModLine(sim.toItem(bow,bowState).implicitModLines[1],false))==bowChoice.label,"Independent implicit values changed")
 local bowSaved=sim.model(assert(sim.itemText(bow,bowState)))
 assert(StripEscapes(itemLib.formatModLine(sim.toItem(bowSaved,bowSaved.initial).implicitModLines[1],false))==bowChoice.label,"Reopening changed independent implicit values")
 ui:restore()
end
print("CRAFTING_BASE_IMPLICIT_UI_OK")
