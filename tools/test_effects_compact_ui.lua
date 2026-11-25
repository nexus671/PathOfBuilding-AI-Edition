local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true;newBuild()
local ui=require("Modules.HeadlessUI").install({width=640,height=480});ui:bind(build)
for _,size in ipairs({{640,480},{720,600},{960,640}}) do
 ui:resize(size[1],size[2]);local kept;require("Classes.LootFilterEffectsControl").Open({}, {BaseType="Chaos Orb"},function(value) kept=value end)
 local compact=size[2]<608 or size[1]<800
 if compact then ui:click("pageSound") end;ui:choose("soundKind","Numbered alert");ui:choose("alertId",6,"val");if output then ui:frame():write(output.."/"..size[1].."-effects-sound.json") end
 if compact then ui:click("pageMap") end;ui:choose("iconShape","Star");ui:choose("iconColor","Cyan");ui:choose("beam","Red");ui:clickAt(5,5);if output then ui:frame():write(output.."/"..size[1].."-effects-map.json") end
 if compact then ui:click("pageSound");ui:choose("soundKind","Custom sound");ui:click("pageFiles");ui:text("customPath","test.wav;second.wav");if output then ui:frame():write(output.."/"..size[1].."-effects-files.json") end;ui:click("manageFiles");if output then ui:frame():write(output.."/"..size[1].."-effects-manage.json") end;ui:click("down");ui:click("keep");ui:click("pageSound") end
 ui:click("keep");assert(kept and kept.MinimapIcon and kept.PlayEffect and (compact and kept.CustomAlertSound or kept.PlayAlertSound),"Effects settings lost");if compact then assert(kept.CustomAlertSound[1]=="second.wav;test.wav","Custom sound order was not kept") end
end
print("FILTER_EFFECTS_COMPACT_OK");ui:restore()


