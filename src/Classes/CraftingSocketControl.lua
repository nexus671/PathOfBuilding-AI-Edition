-- Set an observed or hypothetical socket layout without consuming currency.
local ui=require("Modules.PlanningUI")
local sim=require("Modules.CraftingSimulator")
local M={}
function M.Open(model,input,keep)
	local state=copyTable(input);local original=state.sockets or model.item.sockets or {}
	local max=math.max(sim.socketLimit(model,state),#original);max=math.min(max,6)
	local abyss=0;for _,socket in ipairs(original) do if socket.color=="A" then abyss=abyss+1 end end
	local colors={{label="^xEF7777Red",val="R"},{label="^x85D59CGreen",val="G"},{label="^x80B9F5Blue",val="B"},{label="^xEEEEEEWhite",val="W"}}
	if abyss>0 then colors[#colors+1]={label="Abyss",val="A"} end
	local controls={};local links={};local choices={}
	for count=0,max do choices[#choices+1]={label=tostring(count),val=count} end
	ui.description(controls,"intro",16,28,712,40,{state.socketLayoutUnknown and "The shown layout is a placeholder. Set the observed or desired sockets and links." or "Choose the observed or hypothetical sockets and links. No currency is used."},14)
	ui.label(controls,"countLabel",16,78,"Socket count",14)
	controls.count=new("DropDownControl"):DropDownControl(ui.anchor,{112,74,90,26},choices)
	controls.count:SelByValue(#original,"val")
	local function count() return controls.count:GetSelValueByKey("val") or 0 end
	for index=1,6 do
		local x=16+(index-1)*120
		ui.label(controls,"label"..index,x,119,"Socket "..index,14)
		controls["color"..index]=new("DropDownControl"):DropDownControl(ui.anchor,{x,139,108,26},colors)
		controls["color"..index]:SelByValue(original[index] and original[index].color or "W","val")
		controls["color"..index].shown=function() return index<=count() end
		controls["label"..index].shown=controls["color"..index].shown
		if index<6 then
			links[index]=original[index] and original[index+1] and original[index].group==original[index+1].group or false
			local button=new("ButtonControl"):ButtonControl(ui.anchor,{x,185,108,26},"",function() links[index]=not links[index] end)
			button.label=function() return links[index] and "Linked" or "Separate" end
			button.shown=function() return index<count() end;controls["link"..index]=ui.styleButton(button)
		end
	end
	ui.description(controls,"hint",16,223,712,40,{"Each link button connects its socket to the next. Abyss sockets cannot be linked or added here."},14)
	controls.use=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,270,200,28},"Use socket layout",function()
		local ok,result=pcall(function()
			local candidate=copyTable(state);candidate.sockets={};candidate.socketLayoutUnknown=nil;local group,abyssCount=0,0
			for index=1,count() do
				if index>1 and not links[index-1] then group=group+1 end
				local color=controls["color"..index]:GetSelValueByKey("val")
				if color=="A" then abyssCount=abyssCount+1 end
				candidate.sockets[index]={color=color,group=group}
			end
			assert(abyssCount==abyss,"Keep the existing number of Abyss sockets; change their source separately.")
			return sim.validateState(model,candidate)
		end)
		if not ok then ui.errorPopup("Socket layout",result);return end
		keep(result);main:ClosePopup()
	end),"primary")
	controls.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{612,270,116,28},"Cancel",function() main:ClosePopup() end))
	ui.style(controls,{use=true});main:OpenPopup(744,314,"Set socket layout",controls,nil,nil,"close")
	return controls
end
return M
