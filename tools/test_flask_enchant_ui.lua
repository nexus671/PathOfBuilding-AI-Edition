-- Exercise both utility-flask currencies and target selection without a window.
local directory=assert(arg[1],"Supply an output directory")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local p={id="flask-enchants-ui",title="Utility flask",slot="Flask 1",startingItem="Rarity: NORMAL\nQuicksilver Flask\nItem Level: 86",goals={},steps={}}
 require("Classes.CraftingSimulatorControl").Open(build,p)
 ui:click("settings");ui:text("paletteSearch","Enkindling Orb");ui:frame():write(directory.."/"..size[1].."-flask-enchant-palette.json");ui:click("paletteUse");ui:click("apply")
 ui:frame():write(directory.."/"..size[1].."-flask-enchant-result.json")
 ui:choose("page","Target conditions");ui:click("targetConditions");ui:choose("harvestEnchant","FlaskEnchantmentSealIncreasedEffect_","val");ui:text("minAbyssSockets","68")
 ui:frame():write(directory.."/"..size[1].."-flask-enchant-target.json");ui:click("keep")
 ui:frame():write(directory.."/"..size[1].."-flask-enchant-target-summary.json")
 ui:choose("page","Emulate item");ui:click("settings");ui:text("paletteSearch","Instilling Orb");ui:click("paletteUse");ui:click("apply")
 ui:frame():write(directory.."/"..size[1].."-flask-enchant-instilling.json")
 ui:restore();main.popups={}
end
print("FLASK_ENCHANT_UI_OK",15)
