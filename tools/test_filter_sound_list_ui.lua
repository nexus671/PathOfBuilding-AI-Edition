-- Exercise building and exporting a list of custom alert sounds.
local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local uiModule=require("Modules.HeadlessUI");local effects=require("Classes.LootFilterEffectsControl")
local browser=require("Classes.LootFilterFileBrowser");local library=require("Modules.LootFilterLibrary");local parser=require("Modules.LootFilterParser")
local audio=require("Modules.LootFilterAudio")
local function uncertain(styles,fragment)
 local id,why=audio.alert(styles);assert(not id and why:find(fragment,1,true),"Ambiguous sound was described as certain")
 local played,message=audio.play(styles);assert(not played and message:find(fragment,1,true),"Ambiguous sound played without an explanation")
end
local both=parser.simulate(parser.parse('Show\n CustomAlertSound "first.wav"\n Continue\nShow\n CustomAlertSoundOptional "second.wav"'),{})
uncertain(both.styles,"Both custom alert modes")
uncertain({CustomAlertSound={"None"},PlayAlertSound={"4"}},"disabled custom alert")
assert(select(1,audio.alert({PlayAlertSound={"4"}}))==4,"Ordinary numbered alert changed")
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=uiModule.install({width=size[1],height=size[2]});ui:bind(build)
 local kept;effects.Open({}, {BaseType="Chaos Orb"},function(value) kept=value end);ui:choose("soundKind","Custom sound")
 local original=browser.Open;local selected="C:/Sounds/first.wav";local initial
 browser.Open=function(path,choose,options) initial=path;assert(options.accept("sound.wav") and not options.accept("notes.txt"));choose(selected) end
 ui:click("addSound");assert(main.popups[1].controls.customPath.buf==selected,"Adding to an empty list failed")
 selected="C:/Sounds/second.wav";ui:click("addSound");assert(initial=="C:/Sounds/first.wav","Picker did not start near the previous file")
 assert(main.popups[1].controls.customPath.buf=="C:/Sounds/first.wav;C:/Sounds/second.wav","Adding replaced the existing path")
 ui:choose("previewFile",2,"val");ui:click("manageFiles");ui:click("up")
 if output then ui:frame():write(output.."/"..size[1].."-filter-sound-manager.json") end
 ui:click("keep");assert(main.popups[1].controls.customPath.buf=="C:/Sounds/second.wav;C:/Sounds/first.wav","Moving a file did not keep its order")
 ui:click("manageFiles");ui:click("remove");ui:click("cancel");assert(main.popups[1].controls.customPath.buf=="C:/Sounds/second.wav;C:/Sounds/first.wav","Cancelling changed the sound list")
 ui:click("manageFiles");ui:click("down");ui:click("keep");assert(main.popups[1].controls.customPath.buf=="C:/Sounds/first.wav;C:/Sounds/second.wav","Moving a file back failed")
 ui:choose("previewFile",2,"val");local savedPlay=audio.play;local chosen
 audio.play=function(styles,index) chosen=index;assert(styles.CustomAlertSound[1]=="C:/Sounds/first.wav;C:/Sounds/second.wav");return true,"Preview played." end
 ui:click("test");assert(chosen==2,"Preview did not use the chosen file");main:ClosePopup();audio.play=savedPlay
 if output then ui:frame():write(output.."/"..size[1].."-filter-sound-list.json") end
 ui:click("keep");assert(kept.CustomAlertSound[1]=="C:/Sounds/first.wav;C:/Sounds/second.wav")
 local saved=library.appearance({id="sound",title="Sound",text="Show\n BaseType == \"Chaos Orb\""},kept)
 local parsed=parser.parse(saved.text);assert(#parsed.diagnostics==0 and parsed.rules[1].styles.CustomAlertSound[1]==kept.CustomAlertSound[1],"Sound list did not survive filter export and import")
 effects.Open(kept,{BaseType="Chaos Orb"},function(value) kept=value end);ui:choose("soundKind","Custom sound");ui:choose("previewFile",2,"val");ui:click("manageFiles");ui:click("remove");ui:click("keep");assert(main.popups[1].controls.customPath.buf=="C:/Sounds/first.wav","Removing a selected file failed");ui:click("close");assert(kept.CustomAlertSound[1]=="C:/Sounds/first.wav;C:/Sounds/second.wav","Cancelling the effects editor changed its saved list")
 effects.Open(kept,{BaseType="Chaos Orb"},function(value) kept=value end);ui:choose("soundKind","Custom sound");selected="C:/Sounds/replacement.wav";ui:click("browseSound")
 assert(main.popups[1].controls.customPath.buf==selected,"Browse did not replace the existing list")
 ui:click("keep");assert(kept.CustomAlertSound[1]==selected)
 effects.Open({PlayAlertSound={"4","50"},CustomAlertSoundOptional={"C:/Sounds/first.wav","100"}},{BaseType="Chaos Orb"},function(value) kept=value end)
 ui:choose("soundKind","Optional custom sound");selected="C:/Sounds/second.wav";ui:click("addSound");ui:click("keep")
 assert(kept.PlayAlertSound[1]=="4" and kept.PlayAlertSound[2]=="50" and kept.CustomAlertSoundOptional[1]=="C:/Sounds/first.wav;C:/Sounds/second.wav","Optional sound lost its numbered fallback")
 effects.Open(kept,{BaseType="Chaos Orb"},function() end);assert(main.popups[1].controls.previewFile:IsShown());ui:choose("previewFile",2,"val");savedPlay=audio.play;chosen=nil
 audio.play=function(styles,index) chosen=index;assert(styles.PlayAlertSound[1]=="4" and styles.CustomAlertSoundOptional[1]=="C:/Sounds/first.wav;C:/Sounds/second.wav");return true,"Preview played." end
 ui:click("test");assert(chosen==2,"Saved optional list preview did not use the chosen file");main:ClosePopup();audio.play=savedPlay;ui:click("close")
 local many={};for i=1,10 do many[i]="C:/s/"..i..".wav" end;effects.Open({CustomAlertSound={table.concat(many,";"),"100"}},{BaseType="Chaos Orb"},function() end);ui:choose("soundKind","Custom sound");ui:choose("previewFile",10,"val");ui:click("manageFiles");assert(main.popups[1].controls.files.controls.scrollBar.offset>0,"Selected file was not scrolled into view");ui:click("cancel");ui:click("close")
 effects.Open({CustomAlertSound={"C:/Sounds/only.wav","100"}},{BaseType="Chaos Orb"},function() end);ui:choose("soundKind","Custom sound");ui:click("manageFiles");ui:click("remove");ui:click("keep");local empty=main.popups[1].controls;assert(not empty.keep:IsEnabled() and empty.keep.tooltipText():find("Add a sound file",1,true));ui:choose("soundKind","Silent");assert(empty.keep:IsEnabled());ui:click("close")
 browser.Open=original;ui:restore()
end
-- Playing a preview must not discard the selected item's filter result.
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=uiModule.install({width=size[1],height=size[2]});build.viewMode="CONFIG";ui:bind(build)
 ui:click("aiBuild");ui:click("nav_filters");ui:click("create2");ui:click("viewSimulate");ui:click("drop2")
 local function details() local lines={};for _,row in ipairs(build.planningWorkspace.controls.selection.list) do lines[#lines+1]=StripEscapes(row[1] or "") end;return table.concat(lines," ") end
 local before=details();local original=audio.play
 audio.play=function() return true,"Reference preview played." end;ui:click("sound")
 assert(details():find(before,1,true) and details():find("Reference preview played.",1,true),"Sound preview discarded the selected filter result")
 if output then ui:frame():write(output.."/"..size[1].."-filter-sound-result.json") end
 audio.play=function() return false,"Preview unavailable." end;ui:click("sound")
 assert(details():find(before,1,true) and #main.popups>0,"Sound failure did not preserve the result and explain the problem")
 if output then ui:frame():write(output.."/"..size[1].."-filter-sound-failure.json") end
 audio.play=original;ui:restore()
end
print("FILTER_SOUND_LIST_UI_OK")
