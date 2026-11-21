-- Exercise unique utility-flask enchanting, history and saved plans without a window.
local directory=assert(arg[1],"Supply an output directory")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local project={id="unique-flask-enchant-ui",title="Taste",slot="Flask 1",startingItem="Rarity: UNIQUE\nTaste of Hate\nSapphire Flask\nItem Level: 86\nQuality: 20\n+17% to Cold Resistance",goals={},steps={}}
 build.savers.CraftingProjects:Upsert(project);local c=require("Classes.CraftingUniqueQualityControl").Open(build,project)
 ui:frame():write(directory.."/"..size[1].."-unique-flask-enchant-start.json")
 ui:click("enkindling");local found,warning=false,false;for _,row in ipairs(c.itemMods.list) do local text=StripEscapes(row[1] or "");if text:find("Gains no Charges during Effect",1,true) then found=true end;if text:find("Not supported in PoB yet",1,true) then warning=true end end;assert(found and warning,"The item card did not show the enchantment and its calculation limitation")
 ui:frame():write(directory.."/"..size[1].."-unique-flask-enchant-result.json")
 ui:click("undo");ui:click("redo");ui:click("guide");ui:click("recipe")
 local saved=build.savers.CraftingProjects.projects[1];assert(saved.nativeRecipe.requirements.flaskEnchant,"Recipe target was not saved");assert(saved.steps[1].uniqueCraft.method=="enkindling","Guide was not saved")
 ui:frame():write(directory.."/"..size[1].."-unique-flask-enchant-saved.json")
 ui:click("instilling");ui:frame():write(directory.."/"..size[1].."-unique-flask-enchant-replaced.json")
 ui:restore();main.popups={}
end
print("UNIQUE_FLASK_ENCHANT_UI_OK",12)
