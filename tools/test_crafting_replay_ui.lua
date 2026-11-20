local directory=assert(arg[1]);arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI");local tasks=require("Modules.CraftingTasks")
for _,size in ipairs({{960,640},{1024,768},{1280,720}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local p={id="replay-render",title="Saved simulation",slot="Body Armour",startingItem="Rarity: NORMAL\nPlate Vest\nItem Level: 86",goals={},steps={},preferredMethod="alchemy",nativeRecipe={steps={{method="quality"}},targets={},requirements={minQuality=1}},priceBook={currency="chaos",source="Manual",quotedAt=1700000000,values={["Metadata/Items/Currency/CurrencyArmourQuality"]=2}}}
 local c=require("Classes.CraftingSimulatorControl").Open(build,p);ui:frame();ui:click("tab_simulate");ui:text("trials","2");ui:text("budget","1");ui:click("runRecipe")
 for i=1,1000 do if not tasks.job then break end;tasks.tick(build) end
 assert(not tasks.job);ui:click("keepWorking");local xml={};build.savers.CraftingProjects:Save(xml);main.popups={};newBuild();build.savers.CraftingProjects:Load(xml);ui:bind(build)
 c=require("Classes.CraftingSimulatorControl").Open(build,build.savers.CraftingProjects.projects[1]);ui:frame();ui:click("tab_simulate");assert(c.distribution:IsEnabled() and c.distribution:GetProperty("label")=="Rerun saved")
 ui.cursorX,ui.cursorY=-100,-100;ui:frame():write(directory.."/"..size[1].."-saved-replay.json")
 ui:click("distribution");for i=1,1000 do if not tasks.job then break end;tasks.tick(build) end;assert(not tasks.job and build.craftingAnalyses[p.id].results.simulation)
 ui:frame():write(directory.."/"..size[1].."-saved-replay-finished.json");ui:bind(nil);main.popups={}
end
print("Saved simulation UI: three widths, save/reopen/rerun passed")
