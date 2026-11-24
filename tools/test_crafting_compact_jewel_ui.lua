local out=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild();local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build)
local model=require("Modules.CraftingSimulator").model("Rarity: NORMAL\nCobalt Jewel\nItem Level: 86");local kept
require("Classes.CraftingTargetControl").Open({},nil,nil,function(_,requirements) kept=requirements end,0,"Cobalt Jewel",model)
if out then ui:frame():write(out.."/640-crafting-compact-jewel-target.json") end
ui:click("chooseUnique");ui:click("choose");ui:click("uniqueRoll");assert(main.popups[1] and main.popups[1].title=="Unique jewel roll");if out then ui:frame():write(out.."/640-crafting-compact-jewel-roll.json") end
local minimum=assert(main.popups[1].controls.stat.tooltipText():match("|%s*(-?%d+)%-"),"No supported roll range");ui:text("value",minimum);ui:click("keep");assert(main.popups[1] and main.popups[1].title=="Item properties");ui:click("keep");assert(kept and kept.uniqueName and (kept.uniqueModifier or kept.uniqueModifiers),"Unique jewel roll target was not kept");print("CRAFTING_COMPACT_JEWEL_OK");ui:restore()
