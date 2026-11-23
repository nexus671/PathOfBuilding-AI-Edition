local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local preview=require("Modules.CraftingBenchRarityPreview");local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
local magic=preview.preview(raw,"MAGIC",42);local rare=preview.preview(raw,"RARE",42,magic.state)
assert(magic.conditional and rare.conditional and magic.state.rarity=="MAGIC" and rare.state.rarity=="RARE")
assert(not magic.probability and not rare.price and preview.preview(raw,"MAGIC",42).itemText==magic.itemText)
assert(not pcall(preview.preview,raw,"UNIQUE",42,nil,"Goldrim"))
local refs=preview.uniqueCandidates(raw);local found=false;for _,entry in ipairs(refs.candidates) do if entry.title=="Ezomyte Peak" then found=true end end;assert(found)
local unique=preview.preview(raw,"UNIQUE",42,nil,"Ezomyte Peak");assert(unique.conditional and unique.itemText:find("Ezomyte Peak",1,true))
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local project={id="bench-example",title="Bench example",slot="Helmet",startingItem=raw,goals={},steps={}}
 local c=require("Classes.CraftingSimulatorControl").Open(build,project);c.page:SelByValue("Craft settings");c.page.selFunc();assert(c.benchRarity:IsShown());c.benchRarity:Click()
 local popup=main.popups[1].controls;assert(not popup.copy:IsEnabled());popup.generate:Click();assert(popup.copy:IsEnabled() and #popup.exampleMods.list>0)
 popup.outcome:SelByValue("UNIQUE","val");popup.outcome.selFunc();assert(not popup.copy:IsEnabled());popup.unique:SelByValue("Ezomyte Peak","val");popup.unique.selFunc();popup.generate:Click();assert(popup.copy:IsEnabled())
 if output then ui:frame():write(output.."/"..size[1].."-bench-rarity-example.json") end
 ui:restore();main.popups={}
end
print("BENCH_RARITY_PREVIEW_OK")
