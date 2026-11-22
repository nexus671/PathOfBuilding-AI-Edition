local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
 local project={id="quality-odds",title="Quality odds",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe={steps={{method="quality"}},targets={},requirements={minQuality=2}}}
 local c=require("Classes.CraftingSimulatorControl").Open(build,project);c.method:SelByValue("quality","val");c.method.selFunc();ui:click("tab_settings");ui:click("exact")
 local tasks=require("Modules.CraftingTasks");for _=1,1000 do if not tasks.job then break end;tasks.tick(build) end;assert(not tasks.job,"Quality odds did not finish")
 local lines={};for _,row in ipairs(c.resultSummary.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;local text=table.concat(lines," "):gsub("%s+"," ")
 assert(text:find("game odds are unverified",1,true) and text:find("Quality: 1%",1,true) and text:find("Quality: 2%",1,true),"Exact quality outcomes were not shown: "..text)
 ui:frame();if output then ui:write(output.."/"..size[1].."-quality-calculation.json") end;ui:click("close");ui:restore()
end
print("QUALITY_CALCULATION_UI_OK")
