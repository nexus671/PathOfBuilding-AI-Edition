-- Record an observed Gwennen pair in a project's written guide.
local ui=require("Modules.PlanningUI")
local reference=require("Modules.CraftingGwennenReference")
local M={}
function M.Open(keep,simulate,initial,checkPair)
	local width=math.min(780,main.screenW-40);local height=440
	local controls={};local entries=reference.search("",100).offers;local byId={};local choices={{label="Select an observed outcome",val=0}}
	table.sort(entries,function(a,b) return a.description<b.description end)
	for _,entry in ipairs(entries) do byId[entry.id]=entry;choices[#choices+1]={label=entry.description,val=entry.id} end
	ui.description(controls,"intro",16,28,width-32,42,{"Enter one pair shown in game. The coin chooses one outcome; both can affect or destroy the item."},16)
	ui.label(controls,"firstLabel",16,82,"First outcome",16)
	controls.first=new("DropDownControl"):DropDownControl(ui.anchor,{16,104,width-32,26},choices)
	ui.label(controls,"secondLabel",16,172,"Second outcome",16)
	controls.second=new("DropDownControl"):DropDownControl(ui.anchor,{16,194,width-32,26},choices)
	ui.label(controls,"costLabel",16,262,"Observed artifact price (optional; for example, 20 Grand Broken Circle Artifacts)",16)
	controls.cost=new("EditControl"):EditControl(ui.anchor,{16,284,width-32,26},"",nil,nil,150)
	local function note(key,control,y)
		local display=ui.description(controls,key,16,y,width-32,32,{},14)
		local function refresh()
			local entry=byId[control:GetSelValueByKey("val")]
			display.list=ui.rows({entry and entry.note or ""},width-32,14)
		end
		control.selFunc=refresh;refresh()
	end
	note("firstNote",controls.first,134);note("secondNote",controls.second,224)
	if initial then
		controls.first:SelByValue(initial.firstOutcome,"val");controls.second:SelByValue(initial.secondOutcome,"val")
		controls.first.selFunc();controls.second.selFunc()
		if initial.artifactCost then
			local parts={};for _,tier in ipairs({"lesser","greater","grand","exceptional"}) do
				local amount=initial.artifactCost[tier];if amount and amount>0 then parts[#parts+1]=amount.." "..tier:gsub("^%l",string.upper).." Broken Circle Artifacts" end
			end
			controls.cost:SetText(#parts>0 and table.concat(parts," + ") or "0 Lesser Broken Circle Artifacts")
		end
	end
	local supportedCount=require("Modules.CraftingGwennen").supportedCount()
	local defaultNote=supportedCount.." outcomes have an experimental model. Coin odds and crafting interactions are assumptions. Verify the pair and price in game."
	local limits=ui.description(controls,"limits",16,322,width-32,50,{defaultNote},14)
	local function refreshReadiness()
		local first=controls.first:GetSelValueByKey("val");local second=controls.second:GetSelValueByKey("val")
		local supported=require("Modules.CraftingGwennen").supports
		local message
		if checkPair and supported(first) and supported(second) then
			local ok,reason=checkPair(first,second)
			if not ok then
				reason=ui.errorText(reason)
				local detail=reason:match("^A modeled Gwennen outcome cannot apply:%s*(.+)$")
				if detail then reason=ui.errorText(detail) end
				message="Example preview cannot run on the current item: "..reason.." You can still plan this pair for a later step."
			end
		end
		limits.list=ui.rows({message or defaultNote},width-32,14)
	end
	for _,control in ipairs({controls.first,controls.second}) do local refresh=control.selFunc;control.selFunc=function(...) refresh(...);refreshReadiness() end end
	refreshReadiness()
	controls.keep=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,height-48,220,28},"Add pair to guide",function()
		local first=assert(byId[controls.first:GetSelValueByKey("val")],"Select the first observed outcome")
		local second=assert(byId[controls.second:GetSelValueByKey("val")],"Select the second observed outcome")
		local cost=controls.cost.buf:match("^%s*(.-)%s*$")
		assert(not cost:find("[%c]"),"Invalid artifact price")
		keep(first,second,cost)
		main:ClosePopup()
	end),"primary")
	controls.keep.enabled=function() return byId[controls.first:GetSelValueByKey("val")]~=nil and byId[controls.second:GetSelValueByKey("val")]~=nil end
	if simulate then
		controls.simulate=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{252,height-48,220,28},"Use modeled pair",function()
			local first=byId[controls.first:GetSelValueByKey("val")];local second=byId[controls.second:GetSelValueByKey("val")]
			local cost=controls.cost.buf:match("^%s*(.-)%s*$")
			simulate(first,second,cost);main:ClosePopup()
		end))
		controls.simulate.enabled=function()
			local supported=require("Modules.CraftingGwennen").supports
			return supported(controls.first:GetSelValueByKey("val")) and supported(controls.second:GetSelValueByKey("val"))
		end
		controls.simulate.tooltipText="Available for "..supportedCount.." experimental outcomes. Unknown or unrecognized artifact prices remain unpriced."
	end
	controls.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{width-132,height-48,116,28},"Cancel",function() main:ClosePopup() end))
	ui.style(controls,{keep=true});for _,control in pairs(controls) do control.layoutAudit="gwennen-pair" end
	main:OpenPopup(width,height,"Gwennen: observed pair",controls,nil,nil,"close")
	return controls
end
return M
