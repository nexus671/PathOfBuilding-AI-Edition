local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build)
for _,size in ipairs({{640,480},{720,600},{960,640}}) do
 ui:resize(size[1],size[2]);local saved;local compact=math.min(560,size[2]-60)<520 or math.min(820,size[1]-40)<760
 require("Classes.LootFilterControl").EditSample({BaseType="Chaos Orb",Class="Stackable Currency",Rarity="Normal",ItemLevel=83},function(value) saved=value end)
 ui:text("ItemLevel","84");if output then ui:frame():write(output.."/"..size[1].."-sample-item.json") end
 if compact then ui:click("pageProperties") end;ui:choose("Corrupted","Yes");ui:text("HasInfluence","None");if output then ui:frame():write(output.."/"..size[1].."-sample-properties.json") end
 ui:click("moreSample");assert(main.popups[1] and main.popups[1].title=="More sample properties");if output then ui:frame():write(output.."/"..size[1].."-sample-more.json") end;ui:click("keepExtra");ui:click("useSample");assert(saved and saved.ItemLevel==84 and saved.Corrupted==true and type(saved.HasInfluence)=="table","Sample fields lost across pages")
end
ui:resize(640,480);require("Classes.LootFilterControl").EditSample({BaseType="Chaos Orb"},function() end,"Corrupted");assert(main.popups[1].controls.Corrupted:IsShown(),"Requested property was not opened");ui:clickAt(5,5);ui:click("cancel");assert(not main.popups[1],"Cancel did not close sample editor")
newBuild();ui:bind(build);ui:resize(640,480);local filters=require("Modules.LootFilters");local profile=filters.profile("profile","Sample");profile.rules={filters.rule("mine","Chaos pickup",{'BaseType == "Chaos Orb"','ItemLevel >= 80'})};build.savers.LootFilters:Upsert(profile);build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters");ui:click("viewSimulate");ui:click("sampleEdit");ui:click("pageItem");ui:text("BaseType","Chaos Orb");ui:text("Class","Stackable Currency");ui:text("ItemLevel","83");ui:text("Rarity","Normal");ui:click("pageProperties");ui:choose("Corrupted","No");ui:click("useSample");local snapshot=build.planningWorkspace.cache.filters.layout.snapshot();assert(snapshot.sample.BaseType=="Chaos Orb" and snapshot.sample.ItemLevel==83 and snapshot.sample.Corrupted==false,"Simulator lost the edited drop");local _,_,parsed=filters.compile(snapshot.data.profiles[1],true);local result=require("Modules.LootFilterParser").simulate(parsed,snapshot.sample);assert(result.status=="matched" and result.action=="Show","Configured drop did not match the rule")
print("FILTER_SAMPLE_COMPACT_OK");ui:restore()


