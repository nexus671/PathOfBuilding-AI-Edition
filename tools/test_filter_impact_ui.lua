local output,width=arg[1],tonumber(arg[2]) or 960;arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=width,height=width==960 and 640 or 768});ui:bind(build)
local filters=require("Modules.LootFilters");local before=filters.profile("impact","Impact review");before.template="Show\n"
local sample={Class="Stackable Currency",BaseType="Chaos Orb",Rarity="Normal",ItemLevel=83,AreaLevel=83}
before.sampleSets={{id="examples",title="Examples",samples={sample}}};build.savers.LootFilters:Upsert(before)
local after=copyTable(before);after.rules={{id="hide-chaos",title="Hide Chaos",text='Hide\n BaseType == "Chaos Orb"'}}
local impact=require("Modules.LootFilterImpact");local comparison=impact.page(impact.prepare(before,after),{sample},0,50)
assert(comparison.results[1].category=="Visibility changed" and comparison.results[1].before.action=="Show" and comparison.results[1].after.action=="Hide")
local styled=copyTable(before);styled.rules={{id="style",title="Color Chaos",text='Show\n BaseType == "Chaos Orb"\n SetTextColor 255 0 0'}}
assert(impact.page(impact.prepare(before,styled),{sample}).results[1].category=="Style changed")
local uncertain=copyTable(before);uncertain.rules={{id="unknown",title="Unknown tier",text='Hide\n UnidentifiedItemTier >= 2'}}
assert(impact.page(impact.prepare(before,uncertain),{sample}).results[1].category=="Needs review")
local many={};for i=1,51 do many[i]=sample end;local prepared=impact.prepare(before,after);local first=impact.page(prepared,many,0,50);assert(first.nextOffset==50 and #first.results==50);assert(#impact.page(prepared,many,50,50).results==1)
local data=copyTable(build.savers.LootFilters.data);data.profiles[1]=after
build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER"
build.planningWorkspace:Show("filters",{data=data,selected=after.id,page="Simulate",sceneKind="Saved examples",sampleSetId="examples",sample=sample,dirty=true})
ui:click("sceneStats");assert(main.popups[1].controls.secondary,"Saved comparison was not offered");ui:click("secondary")
assert(main.popups[1].title=="Compare saved and draft");local controls=main.popups[1].controls;local text={};for _,row in ipairs(controls.details.list) do text[#text+1]=StripEscapes(row[1] or "") end
assert(table.concat(text," "):find("Visibility changed",1,true),"Comparison did not explain the change")
if output then ui:frame():write(output.."/"..width.."-filter-impact.json") end
ui:click("inspect");assert(not main.popups[1] and build.planningWorkspace.page=="filters","Inspect did not return to the filter")
assert(build.planningWorkspace.cache.filters.layout.snapshot().dirty,"Inspect discarded the filter draft")
local paged=require("Classes.LootFilterImpactControl").Open(before,after,many,function() end);assert(paged.next:IsEnabled() and not paged.previous:IsEnabled())
ui:click("next");assert(paged.page.label:find("51%-51 of 51") and paged.previous:IsEnabled() and not paged.next:IsEnabled(),"Comparison paging failed")
ui:click("previous");assert(paged.page.label:find("1%-50 of 51"),"Comparison did not return to the first page");ui:click("close")
print("FILTER_IMPACT_UI_OK")
