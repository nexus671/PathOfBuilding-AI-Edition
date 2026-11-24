local ui=require("Modules.PlanningUI")
local filters=require("Modules.LootFilters")
local shared=require("Modules.LootFilterSharedStyles")
local appearance=require("Modules.LootFilterAppearanceSettings")
local visual=require("Modules.LootFilterVisuals")
local M={}
local names={Colour="Any colour",AlertSound="Any numbered alert",CustomSound="Any custom sound",SetTextColor="Text colour",SetBorderColor="Border colour",SetBackgroundColor="Background colour",PlayAlertSound="Alert sound",PlayAlertSoundPositional="Positional alert",CustomAlertSound="Custom sound",CustomAlertSoundOptional="Optional custom sound"}
local function isColour(key) return key=="Colour" or key=="SetTextColor" or key=="SetBorderColor" or key=="SetBackgroundColor" end
function M.previewStyles(profile,row,target)
	local key=row.key=="Colour" and "SetTextColor" or row.key=="AlertSound" and (row.types and row.types.PlayAlertSoundPositional and not row.types.PlayAlertSound and "PlayAlertSoundPositional" or "PlayAlertSound") or row.key=="CustomSound" and (row.types and row.types.CustomAlertSoundOptional and not row.types.CustomAlertSound and "CustomAlertSoundOptional" or "CustomAlertSound") or row.key
	local rows={"Show"}
	if isColour(key) then
		local colours={SetTextColor="255 235 175 255",SetBorderColor="105 195 245 255",SetBackgroundColor="20 30 45 255"}
		local rgba=assert(appearance.fromHex(row.value),"Invalid source colour");local value=table.concat(rgba," ")
		local used=false;if row.key=="Colour" and row.types then for _,style in ipairs({"SetTextColor","SetBorderColor","SetBackgroundColor"}) do if row.types[style] then colours[style]=value;used=true end end end
		if not used then colours[key]=value end
		for _,style in ipairs({"SetTextColor","SetBorderColor","SetBackgroundColor"}) do rows[#rows+1]=" "..style.." "..colours[style] end
		rows[#rows+1]=" SetFontSize 32"
	else
		local value=(key=="CustomAlertSound" or key=="CustomAlertSoundOptional") and ('"'..row.value..'"') or row.value
		rows[#rows+1]=" "..key.." "..value.." 100"
	end
	local replacements=copyTable(profile.sharedStyles or {});local found
	for i,entry in ipairs(replacements) do if entry.key==row.key and entry.from==row.value then replacements[i]={key=row.key,from=row.value,to=target};found=true;break end end
	if not found then replacements[#replacements+1]={key=row.key,from=row.value,to=target} end
	local raw=shared.apply(table.concat(rows,"\n"),replacements)
	raw=require("Modules.LootFilterDecorators").apply(raw,profile.appearance)
	return require("Modules.LootFilterParser").parse(raw).rules[1].styles
end
local function edit(profile,row,onKeep)
	local c={};local w,h=math.min(640,main.screenW-40),math.min(360,main.screenH-60)
	local existing;for _,entry in ipairs(profile.sharedStyles or {}) do if entry.key==row.key and entry.from==row.value then existing=entry end end
	ui.description(c,"help",16,28,w-32,62,{names[row.key].." | "..row.count.." declared occurrences", "Whole-filter appearance still applies after these replacements. Unresolved imports are not changed."},14)
	ui.label(c,"sourceLabel",16,102,"Current value",14);ui.description(c,"source",16,122,w-32,30,{row.value},14)
	ui.label(c,"targetLabel",16,160,isColour(row.key) and "Replacement RGBA hex" or "Replacement sound",14)
	c.target=new("EditControl"):EditControl(ui.anchor,{16,182,w-148,28},existing and existing.to or row.value,nil,nil,1000)
	if isColour(row.key) then c.pick=new("ButtonControl"):ButtonControl(ui.anchor,{w-120,182,104,28},"Pick",function()
		local initial=appearance.fromHex(c.target.buf) or appearance.fromHex(row.value)
		require("Classes.ColourPickerControl").Open(initial,function(colour) c.target:SetText(appearance.hex(colour),true) end,{title="Replacement colour",minimumAlpha=(row.key=="Colour" or row.key=="SetTextColor") and profile.mode=="Ruthless" and 80 or 0})
	end)
	elseif row.key=="CustomSound" or row.key=="CustomAlertSound" or row.key=="CustomAlertSoundOptional" then
		c.pick=new("ButtonControl"):ButtonControl(ui.anchor,{w-120,182,104,28},"Browse",function() require("Classes.LootFilterFileBrowser").Open(c.target.buf,function(path) c.target:SetText(path,true) end) end)
	end
	local function candidate()
		return {key=row.key,from=row.value,to=c.target.buf}
	end
	local function valid()
		if not pcall(shared.validate,{candidate()}) then return false end
		if (row.key=="Colour" or row.key=="SetTextColor") and profile.mode=="Ruthless" then local rgba=appearance.fromHex(c.target.buf);return rgba and rgba[4]>=80 end
		return true
	end
	if isColour(row.key) then
		c.preview=new("Control"):Control(ui.anchor,{16,222,w-32,54})
		function c.preview:Draw() local x,y=self:GetPos();local width=self:GetSize();local styles=valid() and M.previewStyles(profile,row,c.target.buf) or {};visual.floor(x,y,width,54);visual.chip(x,y,width,54,{BaseType="Example item"},{action="Show",styles=styles}) end
	else
		c.previewSound=new("ButtonControl"):ButtonControl(ui.anchor,{16,226,160,28},"Preview sound",function() local _,message=require("Modules.LootFilterAudio").play(M.previewStyles(profile,row,c.target.buf));main:OpenMessagePopup("Sound preview",message) end);c.previewSound.enabled=valid
	end
	c.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-48,160,28},"Keep replacement",function()
		local replacement=shared.validate({candidate()})[1];local next=copyTable(profile);next.sharedStyles=next.sharedStyles or {};local found
		for i,entry in ipairs(next.sharedStyles) do if entry.key==row.key and entry.from==row.value then next.sharedStyles[i]=replacement;found=true;break end end
		if not found then next.sharedStyles[#next.sharedStyles+1]=replacement end
		filters.validate({schemaVersion=1,activeId=next.id,profiles={next}});onKeep(next);main:ClosePopup()
	end)
	c.keep.enabled=valid;c.keep.tooltipText=function() return valid() and "Keep this replacement in the working filter." or "Enter a valid replacement value." end
	c.remove=new("ButtonControl"):ButtonControl(ui.anchor,{188,h-48,160,28},"Remove replacement",function()
		local next=copyTable(profile);for i=#next.sharedStyles,1,-1 do local entry=next.sharedStyles[i];if entry.key==row.key and entry.from==row.value then table.remove(next.sharedStyles,i) end end
		onKeep(next);main:ClosePopup()
	end);c.remove.enabled=existing~=nil
	c.close=new("ButtonControl"):ButtonControl(ui.anchor,{w-156,h-48,140,28},"Cancel",function() main:ClosePopup() end)
	ui.style(c,{keep=true});main:OpenPopup(w,h,"Shared style",c,nil,"target","close")
end
function M.Open(profile,onKeep)
	local probe=copyTable(profile);probe.sharedStyles=nil;probe.appearance=nil
	local raw=filters.compile(probe);local rows=shared.list(raw);local indexed={};local entries={}
	for _,row in ipairs(rows) do indexed[row.key.."\0"..row.value]=row end
	for _,entry in ipairs(profile.sharedStyles or {}) do local id=entry.key.."\0"..entry.from;if not indexed[id] then local row={key=entry.key,value=entry.from,count=0};rows[#rows+1]=row;indexed[id]=row end end
	for _,row in ipairs(rows) do
		local target;for _,entry in ipairs(profile.sharedStyles or {}) do if entry.key==row.key and entry.from==row.value then target=entry.to end end
		entries[#entries+1]={id=row.key.."/"..row.value,label=names[row.key].." | "..row.value.." | "..row.count,category=names[row.key],details={names[row.key],row.count.." declared occurrences before whole-filter overrides.",target and ("Replacement: "..target) or "No replacement saved.","Specific style replacements take priority over shared groups.","Replacements are simultaneous and preserve rule order.","Unresolved imported files cannot be changed."},row=row}
	end
	require("Classes.PlanningBrowserControl").Open("Shared colours and sounds",entries,{action="Edit replacement",closeOnChoose=false,choose=function(entry) main:ClosePopup();edit(profile,entry.row,onKeep) end})
end
return M
