local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local map={id="target",title="Delirium map",patch=require("Modules.MapCraftingData").source().patch,baseId="Metadata/Items/Maps/MapKeyTier5",tier=5,itemLevel=68,rarity="rare",selected={},plannedDelirium={currentPercent=0,nextType="Currency Items",gain=10,targetPercent=80},plannedAllflame="Metadata/Items/MapFragments/MeatSackAllflamePack",plannedDeified=true}
 build.savers.AtlasPlans:Upsert({id="pickup-atlas",title="Mapping plan",version="3.30.0c",budget=150,nodes={},mapDrafts={map}})
 local profile=require("Modules.LootFilters").profile("pickup-ui","Atlas supplies");build.savers.LootFilters:Upsert(profile)
 build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);build.viewMode="PLANNER";build.planningWorkspace:Show("filters")
 ui:click("generate");local found
 for _=1,2000 do ui:frame();local value=build.planningWorkspace.cache.filters.layout.snapshot().data.profiles[1];for _,rule in ipairs(value.rules) do if rule.title=="Fine Delirium Orb" and rule.origin=="atlas:pickup-atlas" then found=true end end;if found then break end end
 assert(found,"Saved Atlas target did not generate its pickup")
 if main.popups[1] then ui:click("close") end
 ui:click("viewCustomize");ui:choose("source","My rules");ui:text("search","Fine Delirium Orb");ui:frame();if output then ui:write(output.."/"..size[1].."-atlas-map-pickup.json") end;ui:restore()
end
print("ATLAS_MAP_PICKUPS_UI_OK")
