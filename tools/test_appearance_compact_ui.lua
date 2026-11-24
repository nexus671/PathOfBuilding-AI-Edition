local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build);local filters=require("Modules.LootFilters");local parser=require("Modules.LootFilterParser")
for _,size in ipairs({{640,480},{720,600},{960,640}}) do
 ui:resize(size[1],size[2]);local saved;local original=filters.rule("example","Example",{'BaseType == "Chaos Orb"'});require("Classes.LootFilterAppearance").Open(original,function(value) saved=value end,function() end,{mode="Normal"})
 local compact=size[2]-60<520 or size[1]-40<800
 for _,page in ipairs({"Text","Border","Background","Effects"}) do if compact then ui:click("page"..page) end;if output then ui:frame():write(output.."/"..size[1].."-appearance-"..page..".json") end end
 if compact then ui:click("pageText") end;ui:text("textHex","FFE0A0FF");ui:click("textHexPick");ui:text("hex","FFE0A0FF");ui:click("keep");if compact then ui:click("pageEffects") end;ui:choose("sound","Alert 6");ui:click("effects");if compact then ui:click("pageMap") end;ui:choose("iconShape","Star");ui:click("keep");ui:click("keepRule");assert(saved and parser.parse(saved.text).rules[1].styles.MinimapIcon and parser.parse(saved.text).rules[1].styles.PlayAlertSound,"Appearance edits lost")
local conditionSaved;require("Classes.LootFilterControl").Conditions(original,function(value) conditionSaved=value end,"Normal");ui:click("addCondition");ui:click("addCondition");if output then ui:frame():write(output.."/"..size[1].."-appearance-conditions.json") end;ui:click("keepRule");assert(conditionSaved and #parser.parse(conditionSaved.text).rules[1].conditions==3,"Advanced conditions were lost")
end
print("FILTER_APPEARANCE_COMPACT_OK");ui:restore()
