local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build)
for _,size in ipairs({{640,480},{720,600},{960,640}}) do
 ui:resize(size[1],size[2]);local kept;require("Classes.LootFilterGlobalControl").Open(require("Modules.LootFilters").profile("p","Test"),function(value) kept=value end)
 if output then ui:frame():write(output.."/"..size[1].."-global-compact-style.json") end;ui:choose("minimumFontSize",40,"val");if size[2]<634 or size[1]<660 then ui:click("pageColours") end;ui:text("textColor","FFE0A0FF");ui:click("textColorPick");if output then ui:frame():write(output.."/"..size[1].."-global-compact-picker.json") end;ui:text("hex","FFE0A0FF");ui:click("keep");if output then ui:frame():write(output.."/"..size[1].."-global-compact-colours.json") end;ui:click("keep");assert(kept and kept.appearance.minimumFontSize==40 and kept.appearance.textColor,"Appearance changes lost")
 require("Classes.LootFilterGlobalControl").Open(require("Modules.LootFilters").profile("p","Test"),function() end,{previewAppearance={textColor={255,224,160,255},borderColor={192,160,96,255}}})
 local controls=main.popups[1].controls;assert(controls.colourHint.label:find("Whole%-filter overrides: text, border") and controls.textColor.tooltipText and not controls.backgroundColor.tooltipText,"Category editor must identify the overridden colours")
 if size[2]<634 or size[1]<660 then ui:click("pageColours") end;if output then ui:frame():write(output.."/"..size[1].."-category-overrides.json") end;ui:click("close")
end
print("GLOBAL_COMPACT_OK");ui:restore()

