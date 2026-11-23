-- Simulate another process creating a filter after the export preflight.
arg={};dofile("HeadlessWrapper.lua");main.disableDevAutoSave=true
local UI=require("Modules.HeadlessUI")
local filters=require("Modules.LootFilters")
local names=require("Modules.LootFilterFileNames")
local original=io.open
for _,kind in ipairs({"single","batch","zip","sound"}) do
	newBuild();main.popups={};local ui=UI.install({width=960,height=640});ui:bind(build)
	local temporary=os.tmpname();os.remove(temporary)
	local folder=temporary:match("^(.*)[/\\]") or ".";local stem=assert(temporary:match("([^/\\]+)$"))
	local filename=stem..".filter";local profile=filters.profile("race","Race")
	local target=folder.."/"..(kind=="single" and filename or kind=="zip" and stem.."-strictnesses.zip" or kind=="sound" and stem.."-sounds.zip" or names.variant(profile,filename,2))
	local paths={target};if kind=="batch" then for i=0,6 do paths[#paths+1]=folder.."/"..names.variant(profile,filename,i) end end
	for _,path in ipairs(paths) do local file=original(path,"rb");assert(not file,"Temporary export path already exists") end
	require("Classes.LootFilterControl").Export(profile,"Show\n BaseType == \"Iron Hat\"")
	ui:text("directory",folder);ui:text("filename",filename)
	if kind=="sound" then ui:click("soundZip") end
	local triggered=false
	io.open=function(path,mode)
		if not triggered and path==target and mode=="rb" then
			triggered=true;local file=assert(original(path,"wbx"));assert(file:write("preserve me"));assert(file:close());return nil,"File appeared after preflight"
		end
		return original(path,mode)
	end
	local ok,err=pcall(function() ui:click(kind=="single" and "write" or kind=="batch" and "writeAll" or kind=="sound" and "save" or "writeZip") end)
	io.open=original
	local file=original(target,"rb");local contents=file and file:read("*a");if file then file:close() end
	local third=kind=="batch" and original(folder.."/"..names.variant(profile,filename,3),"rb");if third then third:close() end
	local popup=main.popups[1];local messages={};if popup and popup.controls.message then for _,row in ipairs(popup.controls.message.list) do messages[#messages+1]=StripEscapes(row[1] or "") end end
	local message=table.concat(messages," ")
	for _,path in ipairs(paths) do os.remove(path) end
	assert(ok,err);assert(triggered,"Race fixture did not run");assert(contents=="preserve me","Export replaced the file created after preflight")
	assert(popup and popup.title=="Loot filter" and message:find("Could not",1,true),"The export failure was not explained")
	if kind=="batch" then assert(not third,"Batch continued after an exclusive-create failure");assert(message:find("Files already completed: 2",1,true),"Batch did not report completed files") end
end
print("FILTER_EXPORT_RACE_UI_OK")
