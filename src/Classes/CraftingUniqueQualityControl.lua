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
	local redo=snapshot and copyTable(snapshot.redo or {}) or {}
	for i=1,#history do actions[i]=actions[i] or "unknown" end
	local savedTrace=snapshot and snapshot.savedTrace
	local savedGuideHash=snapshot and snapshot.savedGuideHash
	local savedGuideLength=snapshot and snapshot.savedGuideLength
	local item,info=unique.inspect(raw)
	local original=unique.inspect(draft.startingItem)
	assert(item.title==original.title and item.baseName==original.baseName and (not not item.corrupted)==(not not original.corrupted),"Unique preview does not match the starting item")
	local w,h=layout and layout.width or math.min(880,main.screenW-40),layout and layout.height or math.min(650,main.screenH-60)
	local c={};local cardX=310;local cardWidth=w-cardX-16
	ui.label(c,"heading",16,18,"Unique crafting",22)
	ui.description(c,"intro",16,56,270,100,{"Preview quality and socket crafts.","Quality currency adds 1%, up to 20%.","Keep the target, then save the build."},15)
	local show=require("Classes.JourneyItemControl").new(c,"item",cardX,56,cardWidth,h-116,"WORKING ITEM")
	local function button(key,y,label,run)
		c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,y,270,32},label,function()
			local ok,err=pcall(run);if not ok then main:OpenMessagePopup("Unique crafting",ui.errorText(err)) end
		end))
	end
	local function snapshotPreview() return {kind="uniqueQuality",project=copyTable(draft),itemText=raw,history=copyTable(history),actions=copyTable(actions),redo=copyTable(redo),savedTrace=savedTrace,savedGuideHash=savedGuideHash,savedGuideLength=savedGuideLength} end
	local function guidePrefixHash(steps,count)
		if not count or count>#steps then return nil end
		local pieces={}
		for i=1,count do
			for _,key in ipairs({"action","stopWhen","onFailure"}) do
				local value=steps[i][key] or "";pieces[#pieces+1]=#value..":"..value
			end
		end
		return require("sha1")(table.concat(pieces,"|"))
	end
	local guideCache,reviewCache,traceCache
	local function savedTraceIndex()
		if traceCache~=nil then return traceCache or nil end
		traceCache=false
		if not savedTrace or #history==0 or history[1]~=draft.startingItem then return nil end
		for i=1,#actions do
			local boundary=history[i+1] or raw
			if require("sha1")(table.concat(actions,"|",1,i).."\n"..boundary)==savedTrace then traceCache=i;return i end
		end
	end
	local function guideNeedsReview()
		if reviewCache==nil then reviewCache=savedTrace and (not savedGuideHash or guidePrefixHash(draft.steps,savedGuideLength)~=savedGuideHash) or false end
		return reviewCache
	end
	local function calculateGuideSteps()
		if #history==0 or history[1]~=draft.startingItem then return nil,"A complete preview from the starting item is needed." end
		local first=1
		if savedTrace then
			if guideNeedsReview() then
				return nil,"The saved guide changed or cannot be verified; review it before adding more steps."
			end
			local matched=savedTraceIndex()
			if not matched then return nil,"The preview no longer follows the steps already saved in the guide." end
			first=matched+1
			if first>#actions then return nil,"These preview steps are already in the guide." end
		end
		local steps={};local qualityCount=0
		local function flush()
			if qualityCount>0 then steps[#steps+1]={action=unique.guideAction("quality",qualityCount,info.resource),uniqueCraft={method="quality",count=qualityCount},done=false};qualityCount=0 end
		end
		for i=first,#actions do
			local action=actions[i]
			if action=="quality" then qualityCount=qualityCount+1
			elseif action=="beast_max_links" or action=="omen_connections" or action=="socket_white_bench" then
				flush();steps[#steps+1]={action=unique.guideAction(action,1,info.resource,item.corrupted),uniqueCraft={method=action,count=1},done=false}
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
	local linkReason,whiteReason,updateCurrency,updateIcons
	local function refresh(persist)
		guideCache=nil;reviewCache=nil;traceCache=nil
		item,info=unique.inspect(raw);show(item)
		linkReason=unique.linkReason(raw)
		whiteReason=unique.whiteReason(raw)
		c.status.label="^7Quality: "..info.quality.."% | "..(item.corrupted and "Corrupted" or info.available and "Ready" or "20% cap reached")
		c.apply.label="Use "..info.resource
		if updateCurrency then updateCurrency() end
		if updateIcons then updateIcons() end
		if raw~=draft.startingItem and raw~=draft.targetItem then ui.draft(build,"uniqueQuality",draft.id)
		else ui.discard(build,"uniqueQuality",draft.id) end
		if persist then require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},not ui.hasDraft(build,"uniqueQuality",draft.id)) end
	end
	ui.label(c,"status",16,174,"",14)
	button("apply",198,"Use quality currency",function() local result=unique.apply(raw);history[#history+1]=raw;actions[#actions+1]="quality";redo={};raw=result.itemText;refresh(true) end)
	c.apply.enabled=function() return info.available end
	c.apply.tooltipText=function() return item.corrupted and "Ordinary quality currency cannot modify a corrupted item." or info.available and "Adds 1% quality." or "Ordinary quality currency cannot exceed 20%." end
	button("link",236,"Bestiary link",function() local result=unique.link(raw);history[#history+1]=raw;actions[#actions+1]="beast_max_links";redo={};raw=result.itemText;refresh(true) end)
	c.link.width=130
	c.link.enabled=function() return not linkReason end
	c.link.tooltipText=function()
		return linkReason or "Links existing sockets using a Black Morrigan and a Craicic Sand Spitter."
	end
	button("omen",236,"Omen + Fusing",function() local result=unique.link(raw,"omen_connections");history[#history+1]=raw;actions[#actions+1]="omen_connections";redo={};raw=result.itemText;refresh(true) end)
	c.omen.x=156;c.omen.width=130;c.omen.enabled=function() return not linkReason end
	c.omen.tooltipText=function() return linkReason or "Links existing sockets using an Omen of Connections and an Orb of Fusing." end
	button("white",274,"Bench: white sockets",function() local result=unique.white(raw);history[#history+1]=raw;actions[#actions+1]="socket_white_bench";redo={};raw=result.itemText;refresh(true) end)
	c.white.enabled=function() return not whiteReason end
	c.white.tooltipText=function() return whiteReason or (item.corrupted and "Uses one Orb of Scouring and one Vaal Orb." or "Uses one Orb of Scouring.") end
	button("undo",312,"Undo",function() assert(#history>0,"No action to undo");redo[#redo+1]={itemText=raw,action=table.remove(actions)};raw=table.remove(history);refresh(true) end)
	c.undo.width=130
	c.undo.enabled=function() return #history>0 end
	button("redo",312,"Redo",function() assert(#redo>0,"No action to redo");local next=table.remove(redo);history[#history+1]=raw;actions[#actions+1]=next.action;raw=next.itemText;refresh(true) end)
	c.redo.x=156;c.redo.width=130;c.redo.enabled=function() return #redo>0 end
	button("keep",350,"Keep target",function() draft.targetItem=raw;draft=build.savers.CraftingProjects:Upsert(draft);ui.discard(build,"uniqueQuality",draft.id);require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},true);c.notice.label="^7Target kept. Save the build." end)
	c.keep.width=130
	c.keep.enabled=function() return raw~=draft.targetItem end
	button("guide",350,"Keep + guide",function()
		local steps,reason,signature=guideSteps();assert(steps,reason)
		local updated=copyTable(draft);updated.targetItem=raw;for _,step in ipairs(steps) do updated.steps[#updated.steps+1]=step end
		draft=build.savers.CraftingProjects:Upsert(updated);savedTrace=signature;savedGuideLength=#draft.steps;savedGuideHash=guidePrefixHash(draft.steps,savedGuideLength);guideCache=nil;reviewCache=nil;traceCache=nil;ui.discard(build,"uniqueQuality",draft.id)
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
			matchingTarget=ok and target.title==original.title and target.baseName==original.baseName and (not not target.corrupted)==(not not original.corrupted)
		end
		return matchingTarget
	end
	button("loadTarget",388,"Load saved target",function()
		assert(targetAvailable(),"The saved target is not an eligible matching unique item")
		history[#history+1]=raw;actions[#actions+1]="load";redo={};raw=draft.targetItem;refresh(true);c.notice.label="^7Saved target loaded."
	end)
	c.loadTarget.width=130
	c.loadTarget.enabled=targetAvailable
	c.loadTarget.tooltipText="Load the project's matching unique target into this preview. Undo returns to the previous item."
	local function canCreateRecipe()
		if #actions==0 or #actions~=#history or history[1]~=draft.startingItem or #actions>100 then return false end
		for _,action in ipairs(actions) do if action~="quality" and action~="beast_max_links" and action~="omen_connections" and action~="socket_white_bench" then return false end end
		return true
	end
	local function createRecipe()
		assert(canCreateRecipe(),"A complete supported preview from the starting item is needed")
		local steps,requirements={},{};local i=1
		while i<=#actions do
			local action=actions[i]
			if action=="quality" then
				local first=i;while i<=#actions and actions[i]=="quality" do i=i+1 end
				local _,after=unique.inspect(history[i] or raw);local count=i-first
				steps[#steps+1]={method="quality",maxAttempts=count,untilRequirements={minQuality=after.quality}}
				requirements.minQuality=info.quality
			else
				steps[#steps+1]={method=action};i=i+1
				if action=="socket_white_bench" then requirements.socketColours=string.rep("W",#item.sockets)
				else requirements.links=#item.sockets end
			end
		end
		assert(#steps<=20,"This preview needs more than 20 recipe steps")
		local recipe={steps=steps,targets={},requirements=requirements}
		local result=require("Modules.CraftingSimulator").simulate(draft.startingItem,recipe,{trials=1,maxActions=100})
		assert(result.sampleSuccess and result.sampleItem==raw,"The recipe did not reproduce this preview; review the actions")
		return recipe
	end
	button("recipe",388,"Check recipe",function()
		if not draft.nativeRecipe then
			local updated=copyTable(draft);updated.nativeRecipe=createRecipe();draft=build.savers.CraftingProjects:Upsert(updated)
			refresh(true);c.notice.label="^7Recipe saved. Save the build.";return
		end
		local result=require("Modules.CraftingSimulator").simulate(draft.startingItem,draft.nativeRecipe,{trials=1,maxActions=100,priceBook=draft.priceBook,treeVersion=build.spec.treeVersion})
		local rw,rh=math.min(760,main.screenW-40),math.min(520,main.screenH-60);local view={}
		ui.label(view,"heading",16,24,"Saved recipe result",20)
		local lines={result.sampleSuccess and "Goal reached in the deterministic model." or "Goal not reached in the deterministic model.",
			"Starts from the saved starting item; the current preview is unchanged.",
			string.format("Actions: %d attempted, %d executed (limit 100).",result.meanActions,result.meanExecutedActions),
			result.meanCost and string.format("Estimated cost: %.2f %s",result.meanCost,result.costCurrency) or "Cost unavailable: add prices for all used resources."}
		for _,entry in ipairs(result.resourceUsage or {}) do lines[#lines+1]=entry.name..": "..entry.amount end
		for _,warning in ipairs(result.warnings or {}) do lines[#lines+1]="Model note: "..warning.message end
		for message,count in pairs(result.transitionErrors or {}) do lines[#lines+1]="Rejected action ("..count.."): "..message end
		view.details=new("TextListControl"):TextListControl(ui.anchor,{16,62,300,rh-126},nil,ui.rows(lines,276,14))
		local render=require("Classes.JourneyItemControl").new(view,"resultItem",332,62,rw-348,rh-126,"RESULT ITEM")
		render(require("Modules.CraftingProjects").item(result.sampleItem))
		view.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,rh-48,160,28},"Keep as target",function()
			local function keepResult()
				local updated=copyTable(draft);updated.targetItem=result.sampleItem
				draft=build.savers.CraftingProjects:Upsert(updated);refresh(true)
				c.notice.label="^7Recipe result kept. Save the build.";main:ClosePopup()
			end
			if draft.targetItem and draft.targetItem:match("%S") and draft.targetItem~=result.sampleItem then
				main:OpenConfirmPopup("Replace crafting target","Replace the saved target with this modeled recipe result?\nUse build Save to persist the change.","Replace",keepResult)
			else keepResult() end
		end)
		view.keep.enabled=result.sampleSuccess
		view.keep.tooltipText=result.sampleSuccess and "Keep this modeled result as the guide's target." or "The recipe did not reach its goal."
		view.update=new("ButtonControl"):ButtonControl(ui.anchor,{192,rh-48,160,28},"Update recipe",function()
			local ok,recipe=pcall(createRecipe)
			if not ok then main:OpenMessagePopup("Unique crafting",ui.errorText(recipe));return end
			main:OpenConfirmPopup("Update saved recipe","Replace the saved recipe with the current preview actions?\nUse build Save to persist the change.","Replace",function()
				local updated=copyTable(draft);updated.nativeRecipe=recipe;draft=build.savers.CraftingProjects:Upsert(updated)
				refresh(true);c.notice.label="^7Recipe updated. Save the build.";main:ClosePopup()
			end)
		end)
		view.update.enabled=canCreateRecipe()
		view.update.tooltipText=canCreateRecipe() and "Replace the saved recipe with the complete current preview after confirmation." or "A complete supported preview from the starting item is needed."
		view.close=new("ButtonControl"):ButtonControl(ui.anchor,{rw-132,rh-48,116,28},"Back",function() main:ClosePopup() end)
		ui.style(view);for _,control in pairs(view) do control.layoutAudit="unique-recipe-result" end
		main:OpenPopup(rw,rh,"Saved unique recipe",view,nil,nil,"close")
	end)
	c.recipe.x=156;c.recipe.width=130;c.recipe.label=function() return draft.nativeRecipe and "Check recipe" or "Save recipe" end
	c.recipe.enabled=function() return draft.nativeRecipe~=nil or canCreateRecipe() end
	c.recipe.tooltipText=function() return draft.nativeRecipe and "Check the saved native recipe from its starting item. No changes are made." or canCreateRecipe() and "Save this complete preview as a recipe; then check its result and cost." or "Preview supported actions from the starting item to create a recipe." end
	ui.label(c,"notice",16,426,restored and "^7Session preview restored." or "",14)
	local art,artCache=nil,{}
	local function icon(method)
		local path=require("Modules.CraftingWorkbench").icon(method,nil,{item=item})
		if path and not artCache[path] then local handle=NewImageHandle();handle:Load(path);artCache[path]=handle end
		return path and artCache[path] or nil
	end
	updateIcons=function()
		c.apply.planningIcon=icon("quality")
		c.omen.planningIcon=icon("omen_connections");c.white.planningIcon=icon("socket_white_bench")
	end
	local currency=new("Control"):Control(ui.anchor,{16,454,42,42});c.currency=currency
	function currency:Draw() if art then local x,y=self:GetPos();SetDrawColor(1,1,1);DrawImage(art,x,y,42,42) end end
	ui.description(c,"currencyNote",68,456,218,48,{"Preview only", "No currency is spent."},14)
	updateCurrency=function()
		local method=actions[#actions];local lines
		if method=="socket_white_bench" or item.corrupted and (not method or method=="load" or method=="unknown") then
			method="socket_white_bench";lines={"Bench: 1 Orb of Scouring",item.corrupted and "+ 1 Vaal Orb | Preview" or "Preview only"}
		elseif method=="omen_connections" then lines={"Omen + Orb of Fusing","1 of each | Preview"}
		elseif method=="beast_max_links" then lines={"Black Morrigan + Sand Spitter","Preview only"}
		elseif method=="quality" then lines={"1 "..info.resource,"Preview only"}
		else method="quality";lines={"Preview only","No currency is spent."} end
		art=icon(method);c.currencyNote.list=ui.rows(lines,218,14)
	end
	c.currency.shown=function() return not guideNeedsReview() end
	c.currencyNote.shown=c.currency.shown
	button("reviewGuide",454,"Review saved guide",function()
		assert(guideNeedsReview() and savedTraceIndex(),"Return to the saved preview before reviewing the guide")
		local reviewedHash=guidePrefixHash(draft.steps,#draft.steps)
		local details={}
		if #draft.steps==0 then details[#details+1]="The guide has no steps." end
		for i,step in ipairs(draft.steps) do
			details[#details+1]=i..". "..step.action
			if step.stopWhen and step.stopWhen~="" then details[#details+1]="Stop: "..step.stopWhen end
			if step.onFailure and step.onFailure~="" then details[#details+1]="If unsuccessful: "..step.onFailure end
		end
		local review={};local rw,rh=math.min(680,main.screenW-40),math.min(460,main.screenH-60)
		ui.label(review,"heading",16,24,ui.fit(draft.title,rw-32,20),20)
		ui.description(review,"intro",16,56,rw-32,48,{"Review the current steps and confirm they describe the saved actions.","No new steps are added until you keep the guide."},14)
		review.details=new("TextListControl"):TextListControl(ui.anchor,{16,112,rw-32,rh-176},nil,ui.rows(details,rw-56,15))
		review.choose=new("ButtonControl"):ButtonControl(ui.anchor,{16,rh-48,180,28},"Confirm guide",function()
			assert(guideNeedsReview() and savedTraceIndex() and guidePrefixHash(draft.steps,#draft.steps)==reviewedHash,"The guide or preview changed; review it again")
			savedGuideLength=#draft.steps;savedGuideHash=reviewedHash;guideCache=nil;reviewCache=nil;traceCache=nil
			require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},true)
			c.notice.label="^7Guide reviewed. Continue the preview.";main:ClosePopup()
		end)
		review.close=new("ButtonControl"):ButtonControl(ui.anchor,{rw-132,rh-48,116,28},"Cancel",function() main:ClosePopup() end)
		ui.style(review,{choose=true});for _,control in pairs(review) do control.layoutAudit="unique-guide-review" end
		main:OpenPopup(rw,rh,"Review saved guide",review,nil,nil,"close")
	end)
	c.reviewGuide.shown=guideNeedsReview
	c.reviewGuide.enabled=function() return savedTraceIndex()~=nil end
	c.reviewGuide.tooltipText=function() return savedTraceIndex() and "Review the existing written steps before adding more preview actions." or "Return to the saved preview before reviewing this guide." end
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
