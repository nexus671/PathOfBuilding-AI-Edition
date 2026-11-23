local ui=require("Modules.PlanningUI")
local impact=require("Modules.LootFilterImpact")
local visual=require("Modules.LootFilterVisuals")
local M={}
function M.Open(before,after,samples,inspect)
	local c={};local w,h=math.min(960,main.screenW-40),math.min(660,main.screenH-60)
	local prepared=impact.prepare(before,after);local offset=0;local current,selected
	ui.description(c,"help",16,26,w-32,42,{"Compare saved and draft results for the same examples. Unknown results need review.","Style differences are filter commands; the game may render them differently."},14)
	c.list=new("TextListControl"):TextListControl(ui.anchor,{16,86,math.floor(w*0.48)-24,h-206},nil,{})
	local right=math.floor(w*0.48)+8;local rightWidth=math.floor(w*0.52)-24
	c.preview=new("Control"):Control(ui.anchor,{right,86,rightWidth,78})
	function c.preview:Draw()
		local x,y=self:GetPos();local width,height=self:GetSize();visual.floor(x,y,width,height,"Dark")
		visual.text(x+8,y+4,13,"Saved","^xA6B3C6");visual.text(x+width/2+8,y+4,13,"Draft","^xA6B3C6")
		if selected then local item=samples[selected.index+1];visual.chip(x,y+20,width/2,height-20,item,selected.before,false);visual.chip(x+width/2,y+20,width/2,height-20,item,selected.after,false) end
	end
	c.details=new("TextListControl"):TextListControl(ui.anchor,{right,174,rightWidth,h-294},nil,{})
	ui.label(c,"page",16,h-104,"",14)
	local function show(row)
		selected=row;local lines
		if row then
			local function description(label,value)
				local text=label..": "..value.action..(value.line and " | line "..value.line or "")
				if value.ruleTitle then text=text.." | "..value.ruleTitle end;return text
			end
			lines={visual.sampleName(samples[row.index+1]),row.category,description("Saved",row.before),description("Draft",row.after)}
			for _,change in ipairs(row.changedStyles) do lines[#lines+1]=change.name..": "..change.before.." -> "..change.after end
			if row.stylesTruncated then lines[#lines+1]="Additional changed style commands were omitted." end
			for _,reason in ipairs(row.before.reasons) do lines[#lines+1]="Saved: "..reason end
			for _,reason in ipairs(row.after.reasons) do lines[#lines+1]="Draft: "..reason end
		else lines={"No examples in this page."} end
		c.details.list=ui.rows(lines,math.floor(w*0.52)-54,14);c.details.controls.scrollBar.offset=0
	end
	local function refresh()
		current=impact.page(prepared,samples,offset,50,nil,true);local rows={}
		for _,row in ipairs(current.results) do
			local label=visual.sampleName(samples[row.index+1]).." | "..row.category.." | "..row.before.action.." -> "..row.after.action
			for _,line in ipairs(ui.rows({label},math.floor(w*0.48)-54,14)) do line.entry=row;rows[#rows+1]=line end
		end
		if #rows==0 then rows=ui.rows({"No examples to compare."},math.floor(w*0.48)-54,14) end
		c.list.list=rows;c.list.controls.scrollBar.offset=0;show(current.results[1])
		c.page.label="^7Examples "..(#current.results>0 and offset+1 or 0).."-"..(offset+#current.results).." of "..current.total
	end
	c.list.onClick=function(hit) if hit and hit.line and hit.line.entry then show(hit.line.entry) end end
	c.previous=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-68,120,28},"Previous",function() offset=math.max(0,offset-50);refresh() end)
	c.next=new("ButtonControl"):ButtonControl(ui.anchor,{144,h-68,120,28},"Next",function() offset=current.nextOffset or offset;refresh() end)
	c.previous.enabled=function() return offset>0 end;c.next.enabled=function() return current and current.nextOffset~=nil end
	c.inspect=new("ButtonControl"):ButtonControl(ui.anchor,{w-324,h-68,160,28},"Inspect item",function() local sample=samples[selected.index+1];main:ClosePopup();inspect(sample) end)
	c.inspect.enabled=function() return selected~=nil end
	c.close=new("ButtonControl"):ButtonControl(ui.anchor,{w-156,h-68,140,28},"Close",function() main:ClosePopup() end)
	ui.style(c,{inspect=true});for _,control in pairs(c) do control.layoutAudit="filter-impact-review" end
	refresh();main:OpenPopup(w,h,"Compare saved and draft",c,nil,nil,"close");return c
end
return M
