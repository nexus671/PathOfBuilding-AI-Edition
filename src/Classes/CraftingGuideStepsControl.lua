-- Search and update a saved guide without changing its written instructions.
local ui=require("Modules.PlanningUI")
local M={}
function M.Open(build,projectId,onChanged)
	local store=build.savers.CraftingProjects;local c={};local selected;local page=1;local pages=1;local pageSize=100
	local w,h=math.min(920,main.screenW-40),math.min(680,main.screenH-60)
	local side=math.floor(w*0.58);local detailW=w-side-32
	local function project()
		for _,entry in ipairs(store.projects) do if entry.id==projectId then return entry end end
		error("This crafting project is no longer available.")
	end
	local function button(key,x,y,width,label,callback)
		c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,28},label,callback))
	end
	c.search=new("EditControl"):EditControl(ui.anchor,{16,28,side-32,28},"","Search steps",nil,1000)
	c.status=new("DropDownControl"):DropDownControl(ui.anchor,{side,28,detailW,28},{"All steps","To do","Done"})
	ui.label(c,"count",16,68,"",14)
	c.results=new("TextListControl"):TextListControl(ui.anchor,{16,92,side-32,h-190},nil,{})
	c.details=new("TextListControl"):TextListControl(ui.anchor,{side,92,detailW,h-208},nil,{})
	local refresh
	local function detail()
		local step=selected and project().steps[selected]
		local lines=step and {"Step "..selected.." | "..(step.done and "Done" or "To do"),step.action} or {"Select a step to see its instructions."}
		if step and step.stopWhen and step.stopWhen~="" then lines[#lines+1]="Stop when: "..step.stopWhen end
		if step and step.onFailure and step.onFailure~="" then lines[#lines+1]="On failure: "..step.onFailure end
		c.details.list=ui.rows(lines,detailW-20,14)
	end
	ui.selectable(c.results,function(row) return row.index end,function(row) selected=row.index;detail() end)
	local actionWidth=math.floor((detailW-16)/3)
	button("toggle",side,h-102,actionWidth,"Mark done",function()
		local changed=copyTable(project());local step=assert(changed.steps[selected],"Select a step first.")
		step.done=not step.done;local ok,err=pcall(store.Upsert,store,changed)
		if not ok then main:OpenMessagePopup("Crafting guide",ui.errorText(err));return end
		if onChanged then onChanged() end;refresh(false)
	end)
	c.toggle.enabled=function() return selected~=nil and project().steps[selected]~=nil end
	c.toggle.label=function() local step=selected and project().steps[selected];return step and step.done and "Mark to do" or "Mark done" end
	button("edit",side+actionWidth+8,h-102,actionWidth,"Edit step",function()
		local index=assert(selected,"Select a step first.");local expected=copyTable(assert(project().steps[index],"Step is no longer available."))
		local edit={};local ew,eh=math.min(760,main.screenW-40),math.min(520,main.screenH-60)
		local function field(key,y,label,value,limit)
			ui.label(edit,key.."Label",16,y,label,14)
			edit[key]=new("EditControl"):EditControl(ui.anchor,{16,y+22,ew-32,58},value or "",nil,"^%C\t\n",limit,nil,16)
		end
		field("action",28,"Instruction",expected.action,1000);field("stop",130,"Stop when (optional)",expected.stopWhen,500);field("failure",232,"On failure (optional)",expected.onFailure,500)
		ui.description(edit,"note",16,334,ew-32,44,{"Keep the instruction on one line. Progress is retained. Changing a modeled instruction removes its guide link; the saved recipe remains."},14)
		local function commit(detach)
			local ok,err=pcall(function()
				local changed=copyTable(project());assert(changed.steps[index] and tableDeepEquals(changed.steps[index],expected),"This step changed. Select it again before editing it.")
				assert(edit.action.buf:match("%S"),"Enter an instruction.");assert(not edit.action.buf:find("[\r\n]"),"Keep the instruction on one line.")
				local step=changed.steps[index];step.action=edit.action.buf;step.stopWhen=edit.stop.buf;step.onFailure=edit.failure.buf;if detach then step.uniqueCraft=nil end
				store:Upsert(changed)
			end)
			if not ok then main:OpenMessagePopup("Crafting guide",ui.errorText(err));return end
			main:ClosePopup();if onChanged then onChanged() end;refresh(false)
		end
		edit.saveStep=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,eh-48,160,28},"Keep step",function()
			if expected.uniqueCraft and edit.action.buf~=expected.action then
				main:OpenConfirmPopup("Change modeled step","Changing this instruction removes its modeled guide link. Continue?","Change",function() commit(true) end)
			else commit(false) end
		end),"primary")
		edit.close=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{ew-132,eh-48,116,28},"Cancel",function() main:ClosePopup() end))
		ui.style(edit,{saveStep=true});for _,control in pairs(edit) do control.layoutAudit="crafting-guide-edit" end
		main:OpenPopup(ew,eh,"Edit crafting step",edit,nil,"action","close")
	end)
	c.edit.enabled=c.toggle.enabled
	button("remove",side+2*(actionWidth+8),h-102,actionWidth,"Remove step",function()
		local index=assert(selected,"Select a step first.");local expected=copyTable(assert(project().steps[index],"Step is no longer available."))
		main:OpenConfirmPopup("Remove crafting step","Remove step "..index.." and its notes and progress?","Remove",function()
			local ok,err=pcall(function()
				local changed=copyTable(project());assert(changed.steps[index] and tableDeepEquals(changed.steps[index],expected),"This step changed. Select it again before removing it.")
				table.remove(changed.steps,index);store:Upsert(changed);selected=nil;if onChanged then onChanged() end;refresh(false)
			end)
			if not ok then main:OpenMessagePopup("Crafting guide",ui.errorText(err)) end
		end)
	end)
	c.remove.enabled=c.toggle.enabled
	button("previous",16,h-88,100,"Previous",function() page=math.max(1,page-1);refresh(true) end)
	button("next",128,h-88,100,"Next",function() page=math.min(pages,page+1);refresh(true) end)
	c.previous.enabled=function() return page>1 end;c.next.enabled=function() return page<pages end
	c.previous.shown=function() return pages>1 end;c.next.shown=c.previous.shown
	button("close",w-132,h-48,116,"Close",function() main:ClosePopup() end)
	refresh=function(reset)
		local current=project();local query=c.search.buf:lower();local filter=c.status:GetSelValue();local matches={};local done=0
		for index,step in ipairs(current.steps) do
			if step.done then done=done+1 end
			local haystack=(step.action.." "..(step.stopWhen or "").." "..(step.onFailure or "")):lower()
			if (filter=="All steps" or filter=="Done" and step.done or filter=="To do" and not step.done) and haystack:find(query,1,true) then
				matches[#matches+1]=index
			end
		end
		pages=math.max(1,math.ceil(#matches/pageSize));page=math.min(page,pages)
		local rows={};local selectedVisible=false
		for offset=(page-1)*pageSize+1,math.min(page*pageSize,#matches) do
			local index=matches[offset];local step=current.steps[index];if selected==index then selectedVisible=true end
			rows[#rows+1]={height=40,textSize=14,"^7"..ui.fit(index..". "..step.action,side-56,14),subtitle=step.done and "Done" or "To do",index=index,selected=selected==index}
		end
		if not selectedVisible then selected=nil end
		if #rows==0 then rows=ui.rows({"No matching steps."},side-56,14) end
		c.results.list=rows;if reset then c.results.controls.scrollBar:SetOffset(0) end
		c.count.label="^7"..done.." / "..#current.steps.." done | "..#matches.." matches | page "..page.." / "..pages
		detail()
	end
	c.search.changeFunc=function() page=1;refresh(true) end;c.status.selFunc=function() page=1;refresh(true) end
	refresh(true);ui.style(c,{toggle=true});for _,control in pairs(c) do control.layoutAudit="crafting-guide-steps" end
	main:OpenPopup(w,h,"Crafting guide steps",c,nil,nil,"close");return c
end
return M
