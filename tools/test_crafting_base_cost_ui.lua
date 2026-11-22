arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86"
local project={id="base-cost-ui",title="Base cost",slot="Body Armour",startingItem=raw,goals={},steps={},preferredMethod="alchemy",nativeRecipe={steps={{method="alchemy"}},targets={},requirements={minAffixes=1}}}
require("Classes.CraftingSimulatorControl").Open(build,project)
ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:text("price","1")
local function run()
    ui:click("runRecipe");local tasks=require("Modules.CraftingTasks")
    for _=1,200 do if not tasks.job then break end;tasks.tick(build) end
    assert(not tasks.job,"Simulation did not finish")
    local lines={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do lines[#lines+1]=StripEscapes(row[1] or "") end
    return table.concat(lines," ")
end
local noBase=run();assert(noBase:find("Starting item counted at zero",1,true),noBase);assert(noBase:find("Mean spent: 1.00 chaos",1,true),noBase)
ui:text("baseCost","5");local priced=run();assert(priced:find("Starting item: 5 chaos each",1,true),priced);assert(priced:find("Mean spent: 6.00 chaos",1,true),priced)
ui:click("distribution");local details={};for _,row in ipairs(main.popups[1].controls.results.list) do details[#details+1]=StripEscapes(row[1] or "") end
assert(table.concat(details," "):find("Starting item: 5 chaos each",1,true),"Distribution omitted starting-item cost");ui:click("close")
ui:text("baseCost","0.005");local small=run();assert(small:find("Starting item: 0.005 chaos each",1,true),small)
ui:click("tab_craft");ui:click("tab_simulate");local restored={};for _,row in ipairs(main.popups[1].controls.resultSummary.list) do restored[#restored+1]=StripEscapes(row[1] or "") end
assert(table.concat(restored," "):find("Starting item: 0.005 chaos each",1,true),"Navigating away lost the captured base cost")
print("CRAFTING_BASE_COST_UI_OK")
