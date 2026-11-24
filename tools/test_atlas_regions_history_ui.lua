local output,width=arg[1],tonumber(arg[2]) or 960;arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=width,height=width==960 and 640 or 768});ui:bind(build)
local input={{mechanic="Blight",maps={{name="Beach Map",freeThreads=2},{name="Strand Map",freeThreads=3}}},{mechanic="Breach",maps={{name="beach map",freeThreads=4},{name="Dunes Map",freeThreads=1}}}}
local kept;local controls=require("Classes.AtlasRegionsControl").Open({shapedRegions=input},function(value) kept=value end)
assert(not controls.undo:IsEnabled() and not controls.redo:IsEnabled(),"Empty history was enabled")
ui:click("overview");ui:text("search","Beach Map");ui:click("choose");local confirm=main.popups[1].controls;confirm.objective1.state=true;ui:click("apply")
assert(controls.undo:IsEnabled(),"Run did not create history");if output then ui:frame():write(output.."/"..width.."-atlas-region-history.json") end
ui:click("undo");assert(controls.redo:IsEnabled(),"Run could not be redone")
ui:click("redo");ui:click("undo")
controls.region:SelByValue("Blight");controls.region.selFunc();controls.list.onClick({line=controls.list.list[1]});ui:text("count","7");ui:click("upsert");assert(not controls.redo:IsEnabled(),"New edit did not clear redo")
ui:click("undo");assert(controls.count.buf=="2","Undo left a stale edit value");ui:click("redo");ui:click("undo")
ui:click("remove");ui:click("undo");assert(controls.remove:IsEnabled(),"Undo did not restore the removed selection")
ui:click("removeRegion");ui:click("undo");assert(controls.remove:IsEnabled(),"Undo did not restore the removed region")
ui:click("keep")
assert(kept[1].maps[1].freeThreads==2 and kept[1].maps[2].freeThreads==3 and kept[2].maps[1].freeThreads==4,"Undo did not restore every overlapping region")
assert(input[1].maps[1].freeThreads==2 and input[2].maps[1].freeThreads==4,"Editing changed the saved input")
build.savers.AtlasPlans:Upsert({id="region-history",title="Region history",version="3.30.0c",budget=150,nodes={},shapedRegions=kept})
local xml=build:SaveDB("Region history");loadBuildFromXML(xml,"Region history");local restored=build.savers.AtlasPlans.plans[1].shapedRegions
assert(restored[1].maps[1].freeThreads==2 and restored[2].maps[1].freeThreads==4,"Saved Atlas plan lost restored region counts")
local high=require("Classes.AtlasRegionsControl").Open({shapedRegions={{mechanic="Blight",maps={{name="Beach Map",freeThreads=101}}}}},function() end)
high.region:SelByValue("Blight");high.region.selFunc();high.list.onClick({line=high.list.list[1]})
assert(not high.threadCheck:IsEnabled() and high.status.label:find("supports up to 100",1,true) and high.threadCheck.tooltipText():find("supports up to 100",1,true),"Unsupported Thread count was not explained before checking")
for _,key in ipairs({"upsert","remove","run","threadCheck","removeRegion","overview","undo","redo"}) do local x=high[key]:GetPos();local w=high[key]:GetSize();assert(x>=0 and x+w<=width,key.." extends beyond the window") end
if output then ui:frame():write(output.."/"..width.."-atlas-region-thread-limit.json") end
high.close:Click()
print("ATLAS_REGION_HISTORY_UI_OK")
