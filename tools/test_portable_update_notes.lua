-- Run only against an isolated portable extraction with staged update files.
local installed,output=arg[1],arg[2]
assert(installed and installed:match("%-ai%.preview%d+$"),"Supply the simulated installed preview version")
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local notes=require("Modules.UpdateNotes");local target,hash=notes.target("Update/manifest.xml")
local text=notes.readVerified("Update/changelog.txt",hash)
assert(target and text,"Stage a matching manifest and changelog in the isolated package's Update folder")
local ui=require("Modules.HeadlessUI").install({width=960,height=640,fontRoot="SimpleGraphic/Fonts"})
newBuild();ui:bind(build);launch.versionNumber=installed;main:OpenUpdatePopup()
local rows={};for _,row in ipairs(main.popups[1].controls.changeLog.list) do rows[#rows+1]=StripEscapes(row[1] or "") end
local shown=table.concat(rows," ")
assert(shown:find("Downloaded: "..target,1,true) and shown:find("Version "..target,1,true),"The packaged popup did not show the staged version and its notes")
if output then ui:frame():write(output) end
ui:restore();print("PORTABLE_UPDATE_NOTES_UI_OK")
