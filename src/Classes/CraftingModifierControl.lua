local ui=require("Modules.PlanningUI")
local modifiers=require("Modules.CraftingModifiers")
local M={}
function M.Open(model,state,options)
	local c={};local w,h=math.min(1080,main.screenW-40),math.min(680,main.screenH-60);local tableW=math.floor((w-48)*0.64);local detailX=tableW+32;local detailW=w-detailX-16
	local result=modifiers.inspect(model,state);local selected;local rows;local page=1;local pageSize=100
	local function button(key,x,y,width,label,run) c[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,28},label,run) end
	c.search=new("EditControl"):EditControl(ui.anchor,{16,28,tableW,28},"","Find a modifier, group or tag",nil,160)
	c.kind=new("DropDownControl"):DropDownControl(ui.anchor,{16,68,tableW/2-6,28},{"All affixes","Prefix","Suffix","Corrupted","Exarch","Eater","Synthesis","Enchant"})
	c.source=new("DropDownControl"):DropDownControl(ui.anchor,{28+tableW/2-6,68,tableW/2-6,28},{"All sources","Natural","Influence","Bench","Essence","Special"})
	c.availability=new("DropDownControl"):DropDownControl(ui.anchor,{detailX,28,detailW,28},{"All modifiers","Eligible draw","Blocked / special"})
	c.sort=new("DropDownControl"):DropDownControl(ui.anchor,{detailX,68,detailW,28},{"Eligible first","Chance","Tier","Item level","Name"})
	local col={8,math.floor(tableW*0.48),math.floor(tableW*0.57),math.floor(tableW*0.67),math.floor(tableW*0.81)}
	for i,title in ipairs({"Modifier","Tier","iLvl","Weight","Draw %"}) do ui.label(c,"column"..i,16+col[i],112,title,12) end
	local columns={};for _,x in ipairs(col) do columns[#columns+1]={x=x} end
	c.modifiers=new("TextListControl"):TextListControl(ui.anchor,{16,138,tableW,h-230},columns,{})
	c.details=new("TextListControl"):TextListControl(ui.anchor,{detailX,112,detailW,h-204},nil,{})
	local function show(row)
		selected=row;local lines={row and row.text or "Choose a modifier",result.note}
		if row then
			lines={row.text,row.type.." | "..row.source,"Required item level: "..row.level,row.tier and "Group tier: "..row.tier or "Special modifier: no natural tier rank","Groups: "..table.concat(row.groups,", "),"Tags: "..table.concat(row.tags,", "),"Current draw weight: "..row.weight,"Total draw weight: "..result.totalWeight,row.chance and "Conditional draw chance: "..ui.percent(row.chance) or "No ordinary affix draw is available"}
			for _,reason in ipairs(row.reasons) do lines[#lines+1]=reason end;lines[#lines+1]=result.note
		end
		c.details.list=ui.rows(lines,detailW-28,14)
	end
	local function refresh()
		rows=modifiers.filter(result,c.search.buf,c.kind:GetSelValue(),c.source:GetSelValue(),c.availability:GetSelValue(),c.sort:GetSelValue());local list={};local keep
		local pages=math.max(1,math.ceil(#rows/pageSize));page=math.min(page,pages);local first=(page-1)*pageSize+1
		for i=first,math.min(#rows,first+pageSize-1) do local row=rows[i];if selected and selected.id==row.id then keep=row end
			local color=row.eligible and "^xD5DEE8" or "^x95A4B7"
			list[#list+1]={height=46,textSize=14,color..ui.fit(row.text,col[2]-20,14),"^7"..(row.tier and "T"..row.tier or "-"),"^7"..row.level,"^7"..row.weight,"^7"..(row.chance and ui.percent(row.chance,3):gsub("%%$","") or "-"),subtitle=ui.fit(row.type.." | "..row.source.." | "..(row.eligible and "Eligible draw" or row.reasons[1] or "Blocked"),tableW-36,13),entry=row}
		end
		c.modifiers.list=#list>0 and list or ui.rows({"No modifiers match. Clear a filter or shorten the search."},tableW-28,14)
		show(keep or rows[first]);c.modifiers.selectedKey=selected and selected.id or nil
		for _,line in ipairs(list) do line.selected=selected and line.entry.id==selected.id or false end
		c.count.label="^7"..#rows.." matching modifiers | Page "..page.." / "..pages
	end
	ui.selectable(c.modifiers,function(row) return row.entry and row.entry.id end,function(row) show(row.entry) end)
	local function changed() page=1;selected=nil;c.modifiers.controls.scrollBar.offset=0;refresh() end
	for _,key in ipairs({"kind","source","availability","sort"}) do c[key].selFunc=changed end;c.search.changeFunc=changed
	ui.label(c,"count",16,h-72,"",12)
	local function turn(delta) page=page+delta;selected=nil;c.modifiers.controls.scrollBar.offset=0;refresh() end
	button("previousPage",detailX,h-72,100,"Previous",function() turn(-1) end);c.previousPage.enabled=function() return page>1 end
	button("nextPage",detailX+108,h-72,100,"Next",function() turn(1) end);c.nextPage.enabled=function() return page*pageSize<#rows end
	local actionCount=1+(options.alternative and 1 or 0)+(options.present and 1 or 0)
	local closeWidth=math.min(140,math.max(96,math.floor(w*0.16)))
	local actionWidth=math.min(200,math.floor((w-32-closeWidth-8*actionCount)/actionCount))
	local actionX=16
	button("choose",actionX,h-42,actionWidth,options.action or "Require modifier",function() if selected then options.choose(selected.id);main:ClosePopup() end end)
	actionX=actionX+actionWidth+8
	local function chooseReason()
		if not selected then return "Select a modifier first." end
		return options.chooseReason and options.chooseReason(selected.id)
	end
	c.choose.enabled=function() return not chooseReason() end
	c.choose.tooltipText=function() return chooseReason() or "Use this modifier as a target." end
	if options.alternative then
		button("alternative",actionX,h-42,actionWidth,"Add alternative",function() if selected then options.alternative(selected.id);main:ClosePopup() end end)
		actionX=actionX+actionWidth+8
		local function alternativeReason()
			if not selected then return "Select a modifier first." end
			if options.canAlternative and not options.canAlternative() then return "Add a target group first." end
			return options.alternativeReason and options.alternativeReason(selected.id)
		end
		c.alternative.enabled=function() return not alternativeReason() end
		c.alternative.tooltipText=function() return alternativeReason() or "Add this modifier as an alternative to the target group." end
	end
	if options.present then
		button("present",actionX,h-42,actionWidth,"Set as present",function() if selected then options.present(selected.id);main:ClosePopup() end end)
		local function presentReason()
			if not selected then return "Select a modifier first." end
			if state.destroyed then return "Reset the destroyed item before staging a modifier." end
			if state.veil then return "Finish the unveil before staging a modifier." end
			if selected.eligible then return nil end
			if not selected.dropOnly then return "This modifier cannot be staged on the current item. See its details for restrictions." end
			local candidate=copyTable(state);if candidate.rarity=="NORMAL" then candidate.rarity="RARE" end
			candidate.affixes[#candidate.affixes+1]={id=selected.id,range=0.5,crafted=false}
			if not pcall(require("Modules.CraftingSimulator").validateState,model,candidate) then return "This drop-only modifier cannot be staged on the current item." end
		end
		c.present.enabled=function() return not presentReason() end
		c.present.tooltipText=function() return presentReason() or "Stage this modifier on a hypothetical rare item. This sets a new recipe start and clears the working action sequence. Drop-only availability is not verified." end
	end
	button("close",w-16-closeWidth,h-42,closeWidth,"Close",function() main:ClosePopup() end)
	ui.style(c,{choose=true});refresh();main:OpenPopup(w,h,"Modifier tiers and weights",c,nil,"search","close");return c
end
return M
