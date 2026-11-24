local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build);local filters=require("Modules.LootFilters");local parser=require("Modules.LootFilterParser")
for _,size in ipairs({{640,480},{720,600},{960,640}}) do
 ui:resize(size[1],size[2]);local saved;local original=filters.rule("example","Example",{'BaseType == "Chaos Orb"'});require("Classes.LootFilterAppearance").Open(original,function(value) saved=value end,function() end,{mode="Normal"})
 local compact=size[2]-60<520 or size[1]-40<800
 for _,page in ipairs({"Text","Border","Background","Effects"}) do if compact then ui:click("page"..page) end;if output then ui:frame():write(output.."/"..size[1].."-appearance-"..page..".json") end end
 if compact then ui:click("pageText") end;ui:text("textHex","FFE0A0FF");ui:click("textHexPick");ui:text("hex","FFE0A0FF");ui:click("keep");if compact then ui:click("pageEffects") end;ui:choose("sound","Alert 6");ui:click("effects");if compact then ui:click("pageMap") end;ui:choose("iconShape","Star");ui:click("keep");ui:click("keepRule");assert(saved and parser.parse(saved.text).rules[1].styles.MinimapIcon and parser.parse(saved.text).rules[1].styles.PlayAlertSound,"Appearance edits lost")
local conditionSaved;require("Classes.LootFilterControl").Conditions(original,function(value) conditionSaved=value end,"Normal")
local rows=math.max(1,math.floor((math.min(600,size[2]-60)-330)/40))
ui:click("addCondition");local controls=main.popups[1].controls
assert(not controls.keepRule.enabled() and controls.keepRule.tooltipText():find("Enter a value",1,true),"An empty condition must block saving with an explanation")
ui:text("c"..math.min(rows,2).."values",'"Iron Hat"');assert(controls.keepRule.enabled(),"Entering a condition value should allow saving")
ui:click("addCondition");assert(not controls.keepRule.enabled(),"A second empty condition must block saving")
ui:text("c"..math.min(rows,3).."values",'"Gold Ring"');if output then ui:frame():write(output.."/"..size[1].."-appearance-conditions.json") end
ui:click("keepRule");local blocks=conditionSaved and parser.parse(conditionSaved.text).rules[1].conditions
assert(blocks and #blocks==3 and blocks[2].values[1]=="Iron Hat" and blocks[3].values[1]=="Gold Ring","Advanced conditions were lost")
end
newBuild();ui:bind(build);ui:resize(640,480);local profile=filters.profile("profile","Sample");profile.rules={filters.rule("mine","Chaos pickup",{'BaseType == "Chaos Orb"'})};build.savers.LootFilters:Upsert(profile);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters");ui:click("viewCustomize");ui:click("edit");ui:text("textHex","FFE0A0FF");ui:click("pageEffects");ui:choose("sound","Alert 6");ui:choose("icon","Star");ui:click("keepRule");ui:click("keep");local xml={};build.savers.LootFilters:Save(xml);local restored=filters.new(build);restored:Load(xml);local block=parser.parse(restored.data.profiles[1].rules[1].text).rules[1];assert(block.styles.SetTextColor and block.styles.PlayAlertSound and block.styles.MinimapIcon and block.conditions[1].values[1]=="Chaos Orb","Saved filter lost the pickup or its appearance")
print("FILTER_APPEARANCE_COMPACT_OK");ui:restore()
