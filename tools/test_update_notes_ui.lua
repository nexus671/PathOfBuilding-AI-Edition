local output=arg[1];arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local notes=require("Modules.UpdateNotes");local uiModule=require("Modules.HeadlessUI")
local target,hash=notes.target("../manifest.xml")
assert(target and (target:match("%-ai%.preview%d+$") or target:match("%-ai%.%d+%.%d+%.%d+$")) and notes.readVerified("../changelog.txt",hash),"Current manifest does not verify its release notes")
local file=assert(io.open("../changelog.txt","rb"));local current=file:read("*a");file:close();local unix=current:gsub("\r\n","\n");local windows=unix:gsub("\n","\r\n")
assert(current:find("VERSION["..target.."][",1,true)==1,"Current version is missing from release notes")
assert(notes.matches(unix,hash) and notes.matches(windows,hash),"Release notes must verify with both checkout newline styles")
assert(not notes.matches("stale notes",hash),"Stale notes passed verification")
local text="VERSION[2.68.1-ai.preview1139][2026/11/22]\nLatest change.\nVERSION[2.68.1-ai.preview1138][2026/11/22]\nEarlier change.\nVERSION[2.68.1-ai.preview1137][2026/11/22]\nAlready installed.\n"
assert(table.concat(notes.describe(text,"2.68.1-ai.preview1137","2.68.1-ai.preview1139")," "):find("Earlier change.",1,true))
assert(table.concat(notes.describe(text,"2.68.1-ai.preview1130","2.68.1-ai.preview1139")," "):find("Some earlier preview notes are unavailable",1,true))
assert(table.concat(notes.describe(nil,"2.68.1-ai.preview1137","2.68.1-ai.preview1139")," "):find("unavailable",1,true))
for _,size in ipairs({{1280,720},{1024,768},{960,640}}) do
 newBuild();main.popups={};local ui=uiModule.install({width=size[1],height=size[2]});ui:bind(build)
 local oldTarget,oldRead,oldVersion=notes.target,notes.readVerified,launch.versionNumber
 notes.target=function() return "2.68.1-ai.preview1139",string.rep("a",40) end
 notes.readVerified=function(path) if path=="Update/changelog.txt" then return text end end
 launch.versionNumber="2.68.1-ai.preview1137";main:OpenUpdatePopup()
 local rows={};for _,row in ipairs(main.popups[1].controls.changeLog.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
 local shown=table.concat(rows," ");assert(shown:find("Latest change.",1,true) and shown:find("Earlier change.",1,true) and not shown:find("Already installed.",1,true),"The update dialog showed incorrect notes")
 if output then ui:frame():write(output.."/"..size[1].."-update-notes.json") end
 ui:click("cancel");notes.target,notes.readVerified,launch.versionNumber=oldTarget,oldRead,oldVersion;ui:restore()
end
print("UPDATE_NOTES_UI_OK")
