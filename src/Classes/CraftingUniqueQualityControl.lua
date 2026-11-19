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
	local actions=snapshot and copyTable(snapshot.actions or {}) or {}
	for i=1,#history do actions[i]=actions[i] or "unknown" end
	local savedTrace=snapshot and snapshot.savedTrace
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
	local function snapshotPreview() return {kind="uniqueQuality",project=copyTable(draft),itemText=raw,history=copyTable(history),actions=copyTable(actions),savedTrace=savedTrace} end
	local guideCache
	local function calculateGuideSteps()
		if #history==0 or history[1]~=draft.startingItem then return nil,"A complete preview from the starting item is needed." end
		local first=1
		if savedTrace then
			local matched
			for i=1,#actions do
				local boundary=history[i+1] or raw
				if require("sha1")(table.concat(actions,"|",1,i).."\n"..boundary)==savedTrace then matched=i;break end
			end
			if not matched then return nil,"The preview no longer follows the steps already saved in the guide." end
			first=matched+1
			if first>#actions then return nil,"These preview steps are already in the guide." end
		end
		local steps={};local qualityCount=0
		local function flush()
			if qualityCount>0 then steps[#steps+1]={action="Use "..qualityCount.." "..info.resource..(qualityCount==1 and "" or "s"),done=false};qualityCount=0 end
		end
		for i=first,#actions do
			local action=actions[i]
			if action=="quality" then qualityCount=qualityCount+1
			elseif action=="beast_max_links" or action=="omen_connections" then
				flush();steps[#steps+1]={action=action=="beast_max_links" and "Link existing sockets with a Black Morrigan and a Craicic Sand Spitter" or "Link existing sockets with an Omen of Connections and an Orb of Fusing",done=false}
			else return nil,"Loaded or older previews do not record every action." end
		end
		flush()
		if #draft.steps+#steps>40 then return nil,"The guide has room for up to 40 steps." end
		local signature=require("sha1")(table.concat(actions,"|").."\n"..raw)
		return steps,nil,signature
	end
	local function guideSteps()
		if not guideCache then local steps,reason,signature=calculateGuideSteps();guideCache={steps=steps,reason=reason,signature=signature} end
		return guideCache.steps,guideCache.reason,guideCache.signature
	end
	local linkReason
	local function refresh(persist)
		guideCache=nil
		item,info=unique.inspect(raw);show(item)
		linkReason=unique.linkReason(raw)
		c.status.label="^7Quality: "..info.quality.."% | "..(info.available and "Ready" or "20% cap reached")
		c.apply.label="Use "..info.resource
		if raw~=draft.startingItem and raw~=draft.targetItem then ui.draft(build,"uniqueQuality",draft.id)
		else ui.discard(build,"uniqueQuality",draft.id) end
		if persist then require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},not ui.hasDraft(build,"uniqueQuality",draft.id)) end
	end
	ui.label(c,"status",16,174,"",14)
	button("apply",206,"Use quality currency",function() local result=unique.apply(raw);history[#history+1]=raw;actions[#actions+1]="quality";raw=result.itemText;refresh(true) end)
	c.apply.enabled=function() return info.available end
	button("link",250,"Bestiary link",function() local result=unique.link(raw);history[#history+1]=raw;actions[#actions+1]="beast_max_links";raw=result.itemText;refresh(true) end)
	c.link.width=130
	c.link.enabled=function() return not linkReason end
	c.link.tooltipText=function()
		return linkReason or "Links existing sockets using a Black Morrigan and a Craicic Sand Spitter."
	end
	button("omen",250,"Omen + Fusing",function() local result=unique.link(raw,"omen_connections");history[#history+1]=raw;actions[#actions+1]="omen_connections";raw=result.itemText;refresh(true) end)
	c.omen.x=156;c.omen.width=130;c.omen.enabled=function() return not linkReason end
	c.omen.tooltipText=function() return linkReason or "Links existing sockets using an Omen of Connections and an Orb of Fusing." end
	button("undo",294,"Undo",function() assert(#history>0,"No action to undo");raw=table.remove(history);table.remove(actions);refresh(true) end)
	c.undo.enabled=function() return #history>0 end
	button("keep",338,"Keep target",function() draft.targetItem=raw;draft=build.savers.CraftingProjects:Upsert(draft);ui.discard(build,"uniqueQuality",draft.id);require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},true);c.notice.label="^7Target kept. Save the build." end)
	c.keep.width=130
	c.keep.enabled=function() return raw~=draft.targetItem end
	button("guide",338,"Keep + guide",function()
		local steps,reason,signature=guideSteps();assert(steps,reason)
		local updated=copyTable(draft);updated.targetItem=raw;for _,step in ipairs(steps) do updated.steps[#updated.steps+1]=step end
		draft=build.savers.CraftingProjects:Upsert(updated);savedTrace=signature;guideCache=nil;ui.discard(build,"uniqueQuality",draft.id)
		require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},true);c.notice.label="^7Target and guide kept. Save the build."
	end)
	c.guide.x=156;c.guide.width=130;c.guide.enabled=function() return guideSteps()~=nil end
	c.guide.tooltipText=function() local _,reason=guideSteps();return reason or "Keep the target and append these preview actions to the written guide." end
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
		history[#history+1]=raw;actions[#actions+1]="load";raw=draft.targetItem;refresh(true);c.notice.label="^7Saved target loaded."
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
