-- Edit optional stack thresholds on a private profile copy before keeping it.
local ui=require("Modules.PlanningUI")
local editing=require("Modules.LootFilterEditing")
local parser=require("Modules.LootFilterParser")
local visual=require("Modules.LootFilterVisuals")
local library=require("Modules.LootFilterLibrary")
local M={}
function M.Open(profile,id,keep)
	local draft=copyTable(profile);local tier
	for _,entry in ipairs(draft.tiers or {}) do if entry.id==id then tier=entry end end
	assert(tier,"Choose a tier")
	local controls={};local selected;local refresh
	local function button(key,x,y,width,title,callback)
		controls[key]=new("ButtonControl"):ButtonControl(ui.anchor,{x,y,width,26},title,function()
			local ok,err=pcall(callback);if not ok then ui.errorPopup("Stack styles",err) end
		end)
	end
	ui.label(controls,"intro",16,34,"Choose visibility and appearance for larger stacks in this tier.",16)
	ui.label(controls,"note",16,58,"Item and other conditions stay with this tier; personal rules still take priority.",12)
	local choices={};for _,entry in ipairs(draft.tiers) do if entry.id~=id then choices[#choices+1]={label=entry.title..(entry.enabled==false and " (disabled)" or ""),val=entry.id} end end
	controls.stackSize=new("EditControl"):EditControl(ui.anchor,{16,92,120,26},"5","Stack size",nil,10)
	controls.stackStyle=new("DropDownControl"):DropDownControl(ui.anchor,{148,92,300,26},choices)
	local function applyStyle(all)
		local minimum=tonumber(controls.stackSize.buf);local style=assert(controls.stackStyle:GetSelValueByKey("val"),"Create another tier first")
		local ids={};for _,entry in ipairs(draft.tiers) do if entry.id~=style and (all or entry.id==id) then ids[#ids+1]=entry.id end end
		local next=copyTable(draft);next.tiers=editing.setStackStyle(next.tiers,ids,minimum,style)
		draft=next;for _,entry in ipairs(draft.tiers) do if entry.id==id then tier=entry end end;selected=nil;refresh()
		controls.note.label=all and ("Applied to "..#ids.." tiers. Keep changes to save.") or "Stack style added. Keep changes to save."
	end
	button("stackAdd",460,92,164,"Add / replace",function() applyStyle(false) end)
	local previewCache={}
	local function previewBlock(target)
		if previewCache[target.id] then return previewCache[target.id] end
		local source=#tier.items>0 and editing.withItems(tier.text,tier.items) or tier.text
		local ok,raw=pcall(require("Modules.LootFilterStackTiers").rule,source,target.text,2)
		if ok then
			raw=require("Modules.LootFilterCategoryStyles").apply(raw,draft.categoryStyles)
			raw=require("Modules.LootFilterSharedStyles").apply(raw,draft.sharedStyles)
			raw=require("Modules.LootFilterDecorators").apply(raw,draft.appearance)
		else raw=target.text end
		local result={block=parser.parse(raw).rules[1],fallback=not ok};previewCache[target.id]=result;return result
	end
	controls.stackPreview=new("Control"):Control(ui.anchor,{16,132,608,60})
	function controls.stackPreview:Draw()
		local x,y=self:GetPos();local width,height=self:GetSize();visual.floor(x,y,width,height)
		local selectedId=controls.stackStyle:GetSelValueByKey("val");local target
		for _,entry in ipairs(draft.tiers) do if entry.id==selectedId then target=entry;break end end
		if target then
			local item=library.sample({text=tier.text});item.BaseType=tier.items[1] or "Example stack"
			local preview=previewBlock(target);local block=preview.block
			visual.text(x+8,y+8,12,preview.fallback and "Style preview" or "Tier preview","^xB7C5D4")
			visual.text(x+width-60,y+8,12,block.action=="Hide" and "Hidden" or block.action=="Minimal" and "Minimal" or "Shown","^xB7C5D4")
			visual.chip(x+80,y+8,width-160,height-12,item,{action=block.action,styles=block.styles})
		end
	end
	controls.stackList=new("TextListControl"):TextListControl(ui.anchor,{16,204,608,92},nil,{})
	refresh=function()
		local names={};for _,entry in ipairs(draft.tiers) do names[entry.id]=entry.title end
		local rules=copyTable(tier.stackRules or {});table.sort(rules,function(a,b) return a.minimum>b.minimum end)
		local rows={};for _,rule in ipairs(rules) do rows[#rows+1]={height=30,textSize=15,"^7"..rule.minimum.."+ items  |  "..(names[rule.styleTierId] or "Missing tier"),minimum=rule.minimum} end
		controls.stackList.list=#rows>0 and rows or ui.rows({"No stack styles. Items use this tier's normal visibility and appearance."},580,14)
	end
	ui.selectable(controls.stackList,function(row) return row.minimum end,function(row) selected=row.minimum end)
	button("stackRemove",16,312,145,"Remove selected",function()
		assert(selected,"Choose a stack style to remove")
		for i=#(tier.stackRules or {}),1,-1 do if tier.stackRules[i].minimum==selected then table.remove(tier.stackRules,i) end end
		selected=nil;refresh()
	end)
	controls.stackRemove.enabled=function() return selected~=nil end
	button("stackAll",169,312,145,"Apply to all",function() applyStyle(true) end)
	controls.stackAll.tooltipText="Apply this threshold to every custom tier except the selected style tier. Existing rules at this threshold are replaced."
	controls.stackAll.enabled=function() return #choices>0 end
	button("stackKeep",322,312,145,"Keep changes",function() draft.tiers=editing.validateTiers(draft.tiers);main:ClosePopup();keep(draft) end)
	button("stackCancel",475,312,149,"Cancel",function() main:ClosePopup() end)
	refresh();ui.style(controls,{stackKeep=true});visual.layers(controls,{stackPreview=true});main:OpenPopup(640,356,"Stack styles",controls,nil,nil,"stackCancel")
end
return M
