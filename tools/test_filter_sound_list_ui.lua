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
 if output then ui:frame():write(output.."/"..size[1].."-filter-sound-list.json") end
 ui:click("keep");assert(kept.CustomAlertSound[1]=="C:/Sounds/first.wav;C:/Sounds/second.wav")
 local saved=library.appearance({id="sound",title="Sound",text="Show\n BaseType == \"Chaos Orb\""},kept)
 local parsed=parser.parse(saved.text);assert(#parsed.diagnostics==0 and parsed.rules[1].styles.CustomAlertSound[1]==kept.CustomAlertSound[1],"Sound list did not survive filter export and import")
 effects.Open(kept,{BaseType="Chaos Orb"},function(value) kept=value end);ui:choose("soundKind","Custom sound");selected="C:/Sounds/replacement.wav";ui:click("browseSound")
 assert(main.popups[1].controls.customPath.buf==selected,"Browse did not replace the existing list")
 ui:click("keep");assert(kept.CustomAlertSound[1]==selected)
 effects.Open({PlayAlertSound={"4","50"},CustomAlertSoundOptional={"C:/Sounds/first.wav","100"}},{BaseType="Chaos Orb"},function(value) kept=value end)
 ui:choose("soundKind","Optional custom sound");selected="C:/Sounds/second.wav";ui:click("addSound");ui:click("keep")
 assert(kept.PlayAlertSound[1]=="4" and kept.PlayAlertSound[2]=="50" and kept.CustomAlertSoundOptional[1]=="C:/Sounds/first.wav;C:/Sounds/second.wav","Optional sound lost its numbered fallback")
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
