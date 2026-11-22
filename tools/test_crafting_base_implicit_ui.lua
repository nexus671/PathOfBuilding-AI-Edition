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
 local nonvariable=sim.model("Rarity: NORMAL\nStygian Vise\nItem Level: 83");assert(not picker.options(sim,nonvariable,nonvariable.initial),"Fixed implicit should not offer a roll")
 ui:restore()
end
print("CRAFTING_BASE_IMPLICIT_UI_OK")
