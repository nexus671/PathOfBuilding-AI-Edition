local ui=require("Modules.PlanningUI")
local visual=require("Modules.LootFilterVisuals")
local options=require("Modules.LootFilterAppearanceSettings")
local M={}
function M.Open(original,sample,onKeep)
	local c={};local w,h=760,548;local sounds={"Keep current","Silent","Numbered alert","Positional alert","Custom sound","Optional custom sound"};local volumeChanged=false
	local numbered=original.PlayAlertSound or original.PlayAlertSoundPositional
	local current=original.CustomAlertSound or original.CustomAlertSoundOptional or numbered
	local isCustom=current and (current==original.CustomAlertSound or current==original.CustomAlertSoundOptional)
	local volume=tonumber(current and current[2]) or (isCustom and 100 or 50)
	local function label(key,x,y,title) ui.label(c,key,x,y,title,14) end
	local function drop(key,x,y,entries) c[key]=new("DropDownControl"):DropDownControl(ui.anchor,{x,y,352,28},entries);return c[key] end
	label("soundLabel",16,140,"Alert type");drop("soundKind",16,164,sounds)
	label("iconLabel",392,140,"Minimap shape");local shapes={"Keep current","None"};for _,shape in ipairs(options.shapes) do shapes[#shapes+1]=shape end
	drop("iconShape",392,164,shapes);if original.MinimapIcon then c.iconShape:SelByValue(tonumber(original.MinimapIcon[1])==-1 and "None" or original.MinimapIcon[3] or "Keep current") end
	label("alertLabel",16,208,"Numbered alert identity");local ids={};for i=1,16 do ids[#ids+1]={label="Alert "..i,val=i} end
	drop("alertId",16,232,ids);c.alertId:SelByValue(tonumber(numbered and numbered[1]) or 1,"val")
	c.alertId.enabled=function() return c.soundKind.selIndex==3 or c.soundKind.selIndex==4 end
	label("iconColorLabel",392,208,"Minimap colour");drop("iconColor",392,232,options.colors);c.iconColor:SelByValue(original.MinimapIcon and original.MinimapIcon[2] or "Cyan")
	label("volumeLabel",16,276,"",14);c.volumeLabel.label=function() return "^7Alert volume: "..volume end
	c.volume=new("SliderControl"):SliderControl(ui.anchor,{16,304,352,24},function(value) volume=math.floor(value*300+0.5);volumeChanged=true end);c.volume.val=volume/300
	label("iconSizeLabel",392,276,"Minimap size");drop("iconSize",392,300,{{label="Large",val=0},{label="Medium",val=1},{label="Small",val=2}});c.iconSize:SelByValue(tonumber(original.MinimapIcon and original.MinimapIcon[1]) or 1,"val")
	for _,key in ipairs({"iconColor","iconSize"}) do c[key].enabled=function() return c.iconShape.selIndex>2 end end
	label("customLabel",16,348,"Custom files (separate with semicolons)")
	c.customPath=new("EditControl"):EditControl(ui.anchor,{16,372,352,28},original.CustomAlertSound and original.CustomAlertSound[1] or original.CustomAlertSoundOptional and original.CustomAlertSoundOptional[1] or "",nil,nil,500);c.customPath.placeholder="sound.wav"
	c.customPath.enabled=function() return c.soundKind.selIndex>=5 end
	local function browseSound(append)
		local path=c.customPath.buf:match("([^;]+)$") or ""
		if not (path:match("^%a:[/\\]") or path:sub(1,2)=="\\\\" or path:sub(1,1)=="/") then
			path=(main.userPath or "./"):gsub("\\","/");if path:sub(-1)~="/" then path=path.."/" end
		end
		require("Classes.LootFilterFileBrowser").Open(path,function(selected)
			if selected:find('[;"\r\n]') then ui.errorPopup("Sound file","The chosen path cannot contain a semicolon, quote or newline.");return end
			local previous=c.customPath.buf;local value=append and previous:match("%S") and previous..";"..selected or selected
			if #value>500 then ui.errorPopup("Sound file","The sound file list is too long. Shorten it before adding another file.");return end
			c.customPath:SetText(value,true)
		end,{title=append and "Add a sound file" or "Choose a sound file",itemLabel="Sound",category="Sounds",accept=function(name)
			return ({wav=true,mp3=true,ogg=true,flac=true,m4a=true,aac=true})[(name:match("%.([^%.]+)$") or ""):lower()]==true
		end})
	end
	c.browseSound=new("ButtonControl"):ButtonControl(ui.anchor,{16,406,168,28},"Browse",function() browseSound(false) end)
	c.addSound=new("ButtonControl"):ButtonControl(ui.anchor,{200,406,168,28},"Add file",function() browseSound(true) end)
	c.browseSound.enabled=c.customPath.enabled;c.addSound.enabled=c.customPath.enabled
	c.browseSound.tooltipText="Replace the sound list with a selected file."
	c.addSound.tooltipText="Add a file to the list. The game selects one file at random."
	label("beamLabel",392,348,"Drop beam")
	local beams={"Keep current","None"};for _,color in ipairs(options.colors) do beams[#beams+1]=color end
	drop("beam",392,372,beams);c.beam:SelByValue(original.PlayEffect and original.PlayEffect[1] or "Keep current")
	label("beamDurationLabel",392,420,"Beam duration");drop("beamDuration",392,444,{"Permanent","Temporary"});c.beamDuration:SelByValue(original.PlayEffect and original.PlayEffect[2]=="Temp" and "Temporary" or "Permanent");c.beamDuration.enabled=function() return c.beam.selIndex>2 end
	local function customActive() return c.soundKind.selIndex>=5 or c.soundKind.selIndex==1 and isCustom and current[1]~="None" end
	label("previewFileLabel",16,440,"Custom file to preview");c.previewFileLabel.shown=customActive
	drop("previewFile",16,460,{});c.previewFile.width=220;c.previewFile.shown=customActive;c.previewFile.enabled=function() return #c.previewFile.list>0 end
	c.previewFile.tooltipText="Preview one local WAV; the exported list still lets the game choose a file."
	local function updatePreviewFiles()
		local list={};for index,path in ipairs(require("Modules.LootFilterAudio").customPaths(c.customPath.buf)) do list[#list+1]={label=path,val=index} end
		local selected=c.previewFile.selIndex;c.previewFile:SetList(list);c.previewFile.selIndex=math.max(1,math.min(selected,#list))
	end
	c.customPath.changeFunc=updatePreviewFiles;updatePreviewFiles()
	c.manageFiles=new("ButtonControl"):ButtonControl(ui.anchor,{248,460,120,28},"Manage",function()
		local files=require("Modules.LootFilterAudio").customPaths(c.customPath.buf);local selected=math.min(c.previewFile.selIndex,#files);if selected==0 then selected=nil end
		local controls={};local refresh
		ui.label(controls,"intro",16,28,"Reorder or remove files. The game chooses one from the kept list.",14)
		controls.files=new("TextListControl"):TextListControl(ui.anchor,{16,58,608,190},nil,{})
		local details=ui.description(controls,"details",16,258,608,40,{},13)
		refresh=function()
			local rows={};for i,path in ipairs(files) do rows[#rows+1]={height=28,textSize=14,"^7"..ui.fit(path,566,14),index=i,selected=i==selected} end
			controls.files.list=#rows>0 and rows or ui.rows({"No files remain."},580,14);controls.files.selectedKey=selected
			if selected then local scroll=controls.files.controls.scrollBar;local top=(selected-1)*28;local height=controls.files.height-4;if top<scroll.offset then scroll.offset=top elseif top+28>scroll.offset+height then scroll.offset=top+28-height end end
			details.list=ui.rows({selected and files[selected] or "Select a file to reorder or remove it."},590,13)
		end
		ui.selectable(controls.files,function(row) return row.index end,function(row) selected=row.index;refresh() end)
		local function button(key,x,width,title,callback) controls[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,310,width,28},title,callback) end
		button("up",16,140,"Move up",function() files[selected],files[selected-1]=files[selected-1],files[selected];selected=selected-1;refresh() end)
		button("down",164,140,"Move down",function() files[selected],files[selected+1]=files[selected+1],files[selected];selected=selected+1;refresh() end)
		button("remove",312,140,"Remove",function() table.remove(files,selected);selected=#files>0 and math.min(selected,#files) or nil;refresh() end)
		controls.up.enabled=function() return selected~=nil and selected>1 end;controls.down.enabled=function() return selected~=nil and selected<#files end;controls.remove.enabled=function() return selected~=nil end
		button("keep",16,180,"Use list",function() c.customPath:SetText(table.concat(files,";"),true);if selected then c.previewFile.selIndex=selected end;main:ClosePopup() end)
		controls.keep.y=352;button("cancel",484,140,"Cancel",function() main:ClosePopup() end);controls.cancel.y=352
		refresh();ui.style(controls,{keep=true});main:OpenPopup(640,398,"Manage custom sounds",controls,nil,nil,"cancel")
	end)
	c.manageFiles.shown=customActive;c.manageFiles.enabled=function() return c.soundKind.selIndex>=5 and #c.previewFile.list>0 end
	c.manageFiles.tooltipText=function() return c.soundKind.selIndex<5 and "Choose Custom sound or Optional custom sound to edit the list." or #c.previewFile.list==0 and "Add a sound file first." or "Reorder or remove files before keeping the filter style." end
	local help=ui.description(c,"help",16,440,352,55,{"Numbered alerts use reference tones; the game plays its own sounds."},13);help.shown=function() return not customActive() end
	local function styles(strict)
		local next=copyTable(original);local mode=c.soundKind.selIndex
		if mode==6 then next.CustomAlertSound=nil;next.CustomAlertSoundOptional=nil
		elseif mode>1 then for _,key in ipairs({"PlayAlertSound","PlayAlertSoundPositional","CustomAlertSound","CustomAlertSoundOptional"}) do next[key]=nil end end
		if mode==2 then next.PlayAlertSound={"None"};next.CustomAlertSound={"None"}
		elseif mode==3 or mode==4 then next[mode==3 and "PlayAlertSound" or "PlayAlertSoundPositional"]={tostring(c.alertId:GetSelValueByKey("val")),tostring(volume)}
		elseif mode>=5 then
			local path=c.customPath.buf;local valid=path:match("%S") and not path:find('["\r\n]');if strict then assert(valid,"Enter a sound path without quotes or newlines") end
			if valid then next[mode==5 and "CustomAlertSound" or "CustomAlertSoundOptional"]={path,tostring(volume)} end
		elseif mode==1 and volumeChanged then for _,key in ipairs({"PlayAlertSound","PlayAlertSoundPositional","CustomAlertSound","CustomAlertSoundOptional"}) do if next[key] and next[key][1]~="None" then next[key][2]=tostring(volume) end end end
		if c.iconShape.selIndex==2 then next.MinimapIcon={"-1"} elseif c.iconShape.selIndex>2 then next.MinimapIcon={tostring(c.iconSize:GetSelValueByKey("val")),c.iconColor:GetSelValue(),c.iconShape:GetSelValue()} end
		if c.beam.selIndex==2 then next.PlayEffect={"None"} elseif c.beam.selIndex>2 then next.PlayEffect={c.beam:GetSelValue()};if c.beamDuration.selIndex==2 then next.PlayEffect[2]="Temp" end end
		return next
	end
	c.preview=new("Control"):Control(ui.anchor,{16,28,w-32,92});function c.preview:Draw() local x,y=self:GetPos();visual.floor(x,y,self.width,self.height);visual.chip(x,y,self.width,self.height,sample,{action="Show",styles=styles()}) end
	c.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-42,220,28},"Use sound and effects",function() onKeep(styles(true));main:ClosePopup() end)
	c.keep.enabled=function() return c.soundKind.selIndex<5 or #require("Modules.LootFilterAudio").customPaths(c.customPath.buf)>0 and not c.customPath.buf:find('["\r\n]') end
	c.keep.tooltipText=function() return not c.keep:IsEnabled() and "Add a sound file without quotes or newlines, or choose another alert type." or "Keep these sound and effect settings." end
	c.test=new("ButtonControl"):ButtonControl(ui.anchor,{252,h-42,220,28},"Preview sound",function() local index=customActive() and #c.previewFile.list>0 and c.previewFile:GetSelValueByKey("val") or nil;local _,message=require("Modules.LootFilterAudio").play(styles(),index);main:OpenMessagePopup("Sound preview",message) end)
	c.close=new("ButtonControl"):ButtonControl(ui.anchor,{w-156,h-42,140,28},"Cancel",function() main:ClosePopup() end)
	ui.style(c,{keep=true});visual.layers(c,{preview=true});main:OpenPopup(w,h,"Sound, minimap icon and beam",c,nil,nil,"close");return c
end
return M
