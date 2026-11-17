-- Edit optional stack thresholds on a private profile copy before keeping it.
local ui=require("Modules.PlanningUI")
local editing=require("Modules.LootFilterEditing")
local M={}
function M.Open(profile,id,keep)
	local draft=copyTable(profile);local tier
	for _,entry in ipairs(draft.tiers or {}) do if entry.id==id then tier=entry end end
	assert(tier,"Choose a tier")
	local controls={};local selected;local refresh
	local function button(key,x,y,width,title,callback)
		controls[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,26},title,function()
			local ok,err=pcall(callback);if not ok then main:OpenMessagePopup("Stack styles",ui.errorText(err)) end
		end)
	end
	ui.label(controls,"intro",16,34,"Choose visibility and appearance for larger stacks in this tier.",16)
	ui.label(controls,"note",16,58,"Item and other conditions stay with this tier; personal rules still take priority.",12)
	local choices={};for _,entry in ipairs(draft.tiers) do if entry.id~=id then choices[#choices+1]={label=entry.title..(entry.enabled==false and " (disabled)" or ""),val=entry.id} end end
	controls.stackSize=new("EditControl"):EditControl(ui.anchor,{16,92,120,26},"5","Stack size",nil,10)
	controls.stackStyle=new("DropDownControl"):DropDownControl(ui.anchor,{148,92,300,26},choices)
	button("stackAdd",460,92,164,"Add / replace",function()
		local minimum=tonumber(controls.stackSize.buf);local style=assert(controls.stackStyle:GetSelValueByKey("val"),"Create another tier first")
		local next=copyTable(draft);local current;for _,entry in ipairs(next.tiers) do if entry.id==id then current=entry end end
		current.stackRules=current.stackRules or {};local replaced=false
		for _,rule in ipairs(current.stackRules) do if rule.minimum==minimum then rule.styleTierId=style;replaced=true end end
		if not replaced then current.stackRules[#current.stackRules+1]={minimum=minimum,styleTierId=style} end
		next.tiers=editing.validateTiers(next.tiers);draft=next;for _,entry in ipairs(draft.tiers) do if entry.id==id then tier=entry end end;selected=nil;refresh()
	end)
	controls.stackList=new("TextListControl"):TextListControl(ui.anchor,{16,132,608,116},nil,{})
	refresh=function()
		local names={};for _,entry in ipairs(draft.tiers) do names[entry.id]=entry.title end
		local rules=copyTable(tier.stackRules or {});table.sort(rules,function(a,b) return a.minimum>b.minimum end)
		local rows={};for _,rule in ipairs(rules) do rows[#rows+1]={height=30,textSize=15,"^7"..rule.minimum.."+ items  |  "..(names[rule.styleTierId] or "Missing tier"),minimum=rule.minimum} end
		controls.stackList.list=#rows>0 and rows or ui.rows({"No stack styles. Items use this tier's normal visibility and appearance."},580,14)
	end
	ui.selectable(controls.stackList,function(row) return row.minimum end,function(row) selected=row.minimum end)
	button("stackRemove",16,266,164,"Remove selected",function()
		assert(selected,"Choose a stack style to remove")
		for i=#(tier.stackRules or {}),1,-1 do if tier.stackRules[i].minimum==selected then table.remove(tier.stackRules,i) end end
		selected=nil;refresh()
	end)
	controls.stackRemove.enabled=function() return selected~=nil end
	button("stackKeep",300,266,160,"Keep changes",function() draft.tiers=editing.validateTiers(draft.tiers);main:ClosePopup();keep(draft) end)
	button("stackCancel",464,266,160,"Cancel",function() main:ClosePopup() end)
	refresh();main:OpenPopup(640,310,"Stack styles",controls,nil,nil,"stackCancel")
end
return M
