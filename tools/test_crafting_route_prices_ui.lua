arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
local project={id="route-prices",title="Branched armour",slot="Body Armour",startingItem="Rarity: NORMAL\nPlate Vest\nItem Level: 86",goals={},steps={},preferredMethod="alchemy",nativeRecipe={targets={},requirements={minAffixes=1},steps={{method="alchemy",onSuccess=3,onFailure=3},{method="alteration"},{method="chaos"}}}}
require("Classes.CraftingSimulatorControl").Open(build,project)
ui:click("tab_simulate");ui:click("resourcePrices");local controls=main.popups[1].controls
local function visible(query)
 controls.search:SetText(query,true);local rows={};for _,row in ipairs(controls.resources.list) do rows[#rows+1]=StripEscapes(row[1] or "") end;return table.concat(rows," ")
end
assert(visible("Orb of Alchemy"):find("Orb of Alchemy",1,true),"Selected or reachable action is missing")
assert(visible("Chaos Orb"):find("Chaos Orb",1,true),"Reachable recipe resource is missing")
assert(not visible("Orb of Alteration"):find("Orb of Alteration",1,true),"Skipped recipe resource is listed")
print("CRAFTING_ROUTE_PRICES_UI_OK")
