local output,width,height=arg[1],tonumber(arg[2]) or 640,tonumber(arg[3]) or 640;arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=width,height=height});ui:bind(build)
local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local sim=require("Modules.CraftingSimulator");local inventory=require("Modules.CraftingInventory")
local state=sim.perform(raw,{method="alchemy"},42).state
local project={id="compact-inventory",title="Inventory example",slot="Helmet",startingItem=raw,goals={},steps={}}
project.inventory={inventory.capture(project,state,"Example")};build.savers.CraftingProjects:Upsert(project)
local resumed;local c=require("Classes.CraftingInventoryControl").Open(build,{resume=function(value) resumed=value end,current=state})
local keys={"rename","remove","undoRemove","source","resume","compare","close"}
for i,key in ipairs(keys) do
 local x,y=c[key]:GetPos();local w,h=c[key]:GetSize();assert(x>=0 and x+w<=width,key.." extends beyond the window")
 for j=i+1,#keys do local other=c[keys[j]];local ox,oy=other:GetPos();local ow,oh=other:GetSize();assert(x+w<=ox or ox+ow<=x or y+h<=oy or oy+oh<=y,key.." overlaps "..keys[j]) end
end
local _,modsHeight=c.savedItemMods:GetSize();assert(modsHeight>=32,"Selected item modifiers have too little room to scroll")
if output and output~="-" then ui:frame():write(output.."/"..width.."-crafting-inventory-compact.json") end
c.itemTitle:SetText("Renamed",true);c.rename:Click();assert(build.savers.CraftingProjects.projects[1].inventory[1].title=="Renamed")
c.remove:Click();assert(c.undoRemove:IsEnabled());c.undoRemove:Click();assert(c.resume:IsEnabled());c.resume:Click();assert(resumed,"Saved item could not be resumed")
print("CRAFTING_INVENTORY_COMPACT_OK")
