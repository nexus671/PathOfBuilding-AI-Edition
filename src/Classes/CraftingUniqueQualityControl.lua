-- Session preview for supported unique item crafts.
local ui=require("Modules.PlanningUI")
local unique=require("Modules.CraftingUniqueQuality")
local M={}
function M.Open(build,project,layout,snapshot)
	local draft=copyTable(project)
	local saved=build.planningUniqueQualityDrafts and build.planningUniqueQualityDrafts[draft.id]
	if not snapshot and saved and saved.project.startingItem==draft.startingItem and saved.project.slot==draft.slot then snapshot=saved end
	local restored=snapshot~=nil
	local raw=snapshot and snapshot.itemText or draft.startingItem
	local history=snapshot and copyTable(snapshot.history or {}) or {}
	local item,info=unique.inspect(raw)
	local original=unique.inspect(draft.startingItem)
	assert(item.title==original.title and item.baseName==original.baseName,"Unique preview does not match the starting item")
	local w,h=layout and layout.width or math.min(880,main.screenW-40),layout and layout.height or math.min(650,main.screenH-60)
	local c={};local cardX=310;local cardWidth=w-cardX-16
	ui.label(c,"heading",16,18,"Unique crafting",22)
	ui.description(c,"intro",16,56,270,100,{"Preview quality or link existing sockets.","Quality currency adds 1%, up to 20%.","Keep the target, then save the build."},15)
	local show=require("Classes.JourneyItemControl").new(c,"item",cardX,56,cardWidth,h-116,"WORKING ITEM")
	local function button(key,y,label,run)
		c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,y,270,32},label,function()
			local ok,err=pcall(run);if not ok then main:OpenMessagePopup("Unique crafting",ui.errorText(err)) end
		end))
	end
	local function snapshotPreview() return {kind="uniqueQuality",project=copyTable(draft),itemText=raw,history=copyTable(history)} end
	local linkReason
	local function refresh(persist)
		item,info=unique.inspect(raw);show(item)
		linkReason=unique.linkReason(raw)
		c.status.label="^7Quality: "..info.quality.."% | "..(info.available and "Ready" or "20% cap reached")
		c.apply.label="Use "..info.resource
		if raw~=draft.startingItem and raw~=draft.targetItem then ui.draft(build,"uniqueQuality",draft.id)
		else ui.discard(build,"uniqueQuality",draft.id) end
		if persist then require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},not ui.hasDraft(build,"uniqueQuality",draft.id)) end
	end
	ui.label(c,"status",16,174,"",14)
	button("apply",206,"Use quality currency",function() local result=unique.apply(raw);history[#history+1]=raw;raw=result.itemText;refresh(true) end)
	c.apply.enabled=function() return info.available end
	button("link",250,"Bestiary: link sockets",function() local result=unique.link(raw);history[#history+1]=raw;raw=result.itemText;refresh(true) end)
	c.link.enabled=function() return not linkReason end
	c.link.tooltipText=function()
		return linkReason or "Links existing sockets using a Black Morrigan and a Craicic Sand Spitter."
	end
	button("undo",294,"Undo",function() assert(#history>0,"No action to undo");raw=table.remove(history);refresh(true) end)
	c.undo.enabled=function() return #history>0 end
	button("keep",338,"Keep as target",function() draft.targetItem=raw;draft=build.savers.CraftingProjects:Upsert(draft);ui.discard(build,"uniqueQuality",draft.id);require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},true);c.notice.label="^7Target kept. Save the build." end)
	c.keep.enabled=function() return raw~=draft.targetItem end
	local checkedTarget,matchingTarget
	local function targetAvailable()
		if not draft.targetItem or draft.targetItem==raw then return false end
		if checkedTarget~=draft.targetItem then
			checkedTarget=draft.targetItem
			local ok,target=pcall(unique.inspect,checkedTarget)
			matchingTarget=ok and target.title==original.title and target.baseName==original.baseName
		end
		return matchingTarget
	end
	button("loadTarget",382,"Load saved target",function()
		assert(targetAvailable(),"The saved target is not an eligible matching unique item")
		history[#history+1]=raw;raw=draft.targetItem;refresh(true);c.notice.label="^7Saved target loaded."
	end)
	c.loadTarget.enabled=targetAvailable
	c.loadTarget.tooltipText="Load the project's matching unique target into this preview. Undo returns to the previous item."
	ui.label(c,"notice",16,422,restored and "^7Session preview restored." or "",14)
	local artPath=require("Modules.CraftingWorkbench").icon("quality",nil,{item=item})
	local art=artPath and NewImageHandle();if art then art:Load(artPath) end
	local currency=new("Control"):Control(ui.anchor,{16,454,42,42});c.currency=currency
	function currency:Draw() if art then local x,y=self:GetPos();SetDrawColor(1,1,1);DrawImage(art,x,y,42,42) end end
	ui.description(c,"currencyNote",68,456,218,48,{"Preview only", "No currency is spent."},14)
	button("close",h-50,layout and "Back to projects" or "Close",function()
		build.planningUniqueQualityDrafts=build.planningUniqueQualityDrafts or {};build.planningUniqueQualityDrafts[draft.id]=snapshotPreview()
		if ui.hasDraft(build,"uniqueQuality",draft.id) then require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},true) end
		if layout then layout.openProjects() else main:ClosePopup() end
	end)
	for _,control in pairs(c) do control.layoutAudit="unique-quality" end
	ui.style(c,{apply=true},{item=true});refresh()
	if layout then
		layout.snapshot=snapshotPreview
		layout.mount(w,h,"Unique crafting",c)
	else main:OpenPopup(w,h,"Unique crafting",c,nil,nil,"close") end
	return c
end
return M
