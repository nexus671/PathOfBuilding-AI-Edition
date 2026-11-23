local output,width,height=arg[1],tonumber(arg[2]) or 640,tonumber(arg[3]) or 480;arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=width,height=height});ui:bind(build);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("atlas")
ui:click("nodeDetails");assert(main.popups[1].title=="Selected Atlas node");main:ClosePopup()
ui:text("search","Essence");ui:click("matchBrowse");assert(main.popups[1].title=="Atlas search matches");ui:click("choose");assert(not main.popups[1]);ui:click("browse");ui:text("search","Essence");ui:click("choose");assert(not main.popups[1]);local c=build.planningWorkspace.controls;assert(c.canvas.focus);ui:click("nodeDetails");assert(main.popups[1].title=="Selected Atlas node");main:ClosePopup();assert(c.allocate:IsEnabled());ui:click("allocate");assert(#build.planningWorkspace.cache.atlas.layout.snapshot().nodes>0)
ui:click("more");ui:text("search","Plan tools");ui:click("choose");assert(main.popups[1] and main.popups[1].title=="Atlas plan tools");main:ClosePopup()
ui:click("more");ui:text("search","Targets");ui:click("choose");assert(main.popups[1]);main:ClosePopup()
if output then ui:frame():write(output.."/"..width.."-atlas-compact.json") end
print("ATLAS_COMPACT_OK");ui:restore()
