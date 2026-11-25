-- cspell:ignore encumbrance
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=UI.install({width=size[1],height=size[2]});ui:bind(build)
 build.planningWorkspace=require("Modules.PlanningWorkspace").new(build);require("Classes.PlanningToolsControl").Open(build);ui:text("search","gem quality planner");assert(main.popups[1].controls.choose:IsEnabled());ui:click("choose")
 ui.clipboard="Item Class: Active Skill Gems\nRarity: Gem\nArc\n--------\nLevel: 20\nQuality: +12%";ui:click("paste")
 local c=main.popups[1].controls;local text="";for _,line in ipairs(c.result.list) do text=text..StripEscapes(line[1] or "").." " end
 assert(text:find("8 Gemcutter",1,true),"Gem quality count missing: "..text)
 ui:click("outcomes");ui:text("search","Lapidary");local details="";for _,line in ipairs(main.popups[1].controls.details.list) do details=details..StripEscapes(line[1] or "").." " end
 assert(details:find("can destroy",1,true) and details:find("23%%"),"Lens limits missing: "..details)
 ui:frame();if output then ui:write(output.."/"..size[1].."-gem-corruption.json") end;ui:click("close")
 ui:click("soul");ui:text("search","Soul Core of Intellect");local coreText="";for _,line in ipairs(main.popups[1].controls.details.list) do coreText=coreText..StripEscapes(line[1] or "").." " end
 assert(coreText:find("eligibility is unverified",1,true),"Soul Core eligibility limit missing: "..coreText)
 ui:text("search","Encumbrance");local soulText="";for _,line in ipairs(main.popups[1].controls.details.list) do soulText=soulText..StripEscapes(line[1] or "").." " end
 assert(soulText:find("200%%"),"Soul Core downside reference missing: "..soulText)
 ui:frame();if output then ui:write(output.."/"..size[1].."-gem-soul-cores.json") end;ui:click("close")
 ui:click("keep");assert(#build.savers.BuildJourney.data.milestones==1,"Gem plan was not added to Journey")
 ui:frame();if output then ui:write(output.."/"..size[1].."-gem-quality.json") end
 ui:click("close");require("Classes.GemQualityPlanControl").Open(build)
 ui.clipboard="Item Class: Support Skill Gems\nRarity: Gem\nAdded Fire Damage Support\n--------\nLevel: 20\nQuality: +4%";ui:click("paste");ui:click("routes");ui:text("search","Vendor and level again");ui:click("choose")
 local vendorText="";for _,line in ipairs(main.popups[1].controls.result.list) do vendorText=vendorText..StripEscapes(line[1] or "").." " end
 assert(vendorText:find("level 1",1,true) and vendorText:find("leveled again",1,true),"Vendor reset was not shown: "..vendorText)
 ui:frame();if output then ui:write(output.."/"..size[1].."-gem-vendor.json") end
 ui:click("keep");local milestone=build.savers.BuildJourney.data.milestones[2];assert(milestone and milestone.notes:find("level it again",1,true),"Vendor route was not saved")
 ui:click("close");ui:restore()
end
print("GEM_QUALITY_UI_OK")
