-- cspell:ignore RGBW
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
	local colourRollCounter=snapshot and snapshot.colourRollCounter or 0
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
	ui.description(c,"intro",16,56,270,68,{(item.type=="Flask" or item.type=="Tincture") and "Preview item quality." or "Preview quality and socket crafts.",item.corrupted and ((item.type=="Flask" or item.type=="Tincture") and "Tainted quality is unavailable." or "Tainted quality rolls are estimated.") or "Quality currency adds 1%, up to 20%.","Keep the target, then save the build."},15)
	local show=require("Classes.JourneyItemControl").new(c,"item",cardX,56,cardWidth,h-116,"WORKING ITEM",{expanded=true})
	local function button(key,y,label,run)
		c[key]=ui.styleButton(new("ButtonControl"):ButtonControl(ui.anchor,{16,y,270,32},label,function()
			local ok,err=pcall(run);if not ok then main:OpenMessagePopup("Unique crafting",ui.errorText(err)) end
		end))
	end
	local function snapshotPreview() return {kind="uniqueQuality",project=copyTable(draft),itemText=raw,history=copyTable(history),actions=copyTable(actions),redo=copyTable(redo),colourRollCounter=colourRollCounter,savedTrace=savedTrace,savedGuideHash=savedGuideHash,savedGuideLength=savedGuideLength} end
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
			local socketCount=tonumber(action:match("^socket_count_bench:([2-6])$"))
			if action=="quality" then qualityCount=qualityCount+1
			elseif socketCount then
				flush();steps[#steps+1]={action=unique.guideAction("socket_count_bench",socketCount,info.resource,item.corrupted),uniqueCraft={method="socket_count_bench",count=socketCount},done=false}
			elseif action=="beast_max_links" or action=="omen_connections" or action=="omen_jeweller" or action=="fusing" or action=="tainted_fusing" or action=="jeweller" or action=="tainted_jeweller" or action=="tainted_quality" or action=="divine" or action=="chromatic" or action=="tainted_chromatic" or action=="omen_trichromatism" or action=="socket_white_bench" or action=="socket_bench" then
				local before=unique.inspect(history[i]);flush();steps[#steps+1]={action=unique.guideAction(action,1,info.resource,item.corrupted,#before.sockets),uniqueCraft={method=action,count=1},done=false}
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
	local linkReason,benchLinkReason,whiteReason,omenJewellerReason,colourReason,taintedQualityReason,divineReason,updateCurrency,updateIcons
	local function refresh(persist)
		guideCache=nil;reviewCache=nil;traceCache=nil
		item,info=unique.inspect(raw);show(item)
		linkReason=unique.linkReason(raw)
		benchLinkReason=unique.linkReason(raw,"socket_bench")
		whiteReason=unique.whiteReason(raw)
		omenJewellerReason=unique.omenReason(raw)
		colourReason=unique.colourReason(raw,item.corrupted and "tainted_chromatic" or "chromatic")
		taintedQualityReason=item.corrupted and unique.taintedQualityReason(raw) or nil
		divineReason=not item.corrupted and unique.divineReason(raw) or nil
		c.status.label="^7Quality: "..info.quality.."% | "..(item.corrupted and "Corrupted" or info.available and "Ready" or "20% cap reached")
		c.apply.label=item.corrupted and (item.type=="Flask" or item.type=="Tincture") and "Quality unavailable" or item.corrupted and "Roll quality" or "Add quality"
		c.apply.width=(not item.corrupted or not taintedQualityReason) and 130 or 270
		if updateCurrency then updateCurrency() end
		if updateIcons then updateIcons() end
		if raw~=draft.startingItem and raw~=draft.targetItem then ui.draft(build,"uniqueQuality",draft.id)
		else ui.discard(build,"uniqueQuality",draft.id) end
		if persist then require("Modules.PlanningRecovery").save(build,"uniqueQuality",{plan=snapshotPreview()},not ui.hasDraft(build,"uniqueQuality",draft.id)) end
	end
	ui.label(c,"status",16,174,"",14)
	button("socketCount",130,"Socket crafts",function()
		local controls={};local width,height=520,210;local options={}
		local limit=require("Modules.CraftingSimulator").socketLimit({item=item})
		for count=2,limit do options[#options+1]={label=count.." sockets",val=count} end
		assert(#options>0,"This base cannot use socket-count recipes")
		ui.description(controls,"help",16,28,width-32,42,{"Choose the number of sockets. Added sockets are white and unlinked in this preview."},14)
		controls.count=new("DropDownControl"):DropDownControl(ui.anchor,{16,82,180,28},options)
		local function chosen() return controls.count:GetSelValueByKey("val") end
		ui.label(controls,"cost",16,122,"",14);controls.cost.label=function()
			local cost=require("Modules.CraftingSimulator").components({method="socket_bench",count=chosen()},{sockets=item.sockets,corrupted=item.corrupted});local amount=cost["Metadata/Items/Currency/CurrencyRerollSocketNumbers"] or 0
			return "^7Cost: "..amount.." Jeweller's Orb"..(amount==1 and "" or "s")..(item.corrupted and " + "..amount.." Vaal Orb"..(amount==1 and "" or "s") or "")
		end
		controls.apply=new("ButtonControl"):ButtonControl(ui.anchor,{16,height-48,128,28},"Preview sockets",function()
			local count=chosen();local result=unique.socketCount(raw,count);history[#history+1]=raw;actions[#actions+1]="socket_count_bench:"..count;redo={};raw=result.itemText;main:ClosePopup();refresh(true)
		end)
		controls.apply.enabled=function() return not unique.socketCountReason(raw,chosen()) end
		controls.apply.tooltipText=function() return unique.socketCountReason(raw,chosen()) or "Preview this bench craft without spending currency." end
		controls.colours=new("ButtonControl"):ButtonControl(ui.anchor,{152,height-48,75,28},"Colours",function()
			main:ClosePopup();local options={}
			for _,entry in ipairs({{label="Chromatic Orb",val="chromatic"},{label="Tainted Chromatic Orb",val="tainted_chromatic"},{label="Omen of Trichromatism",val="omen_trichromatism"}}) do options[#options+1]=entry end
			local colour={};local cw,ch=480,384
			ui.description(colour,"help",16,25,cw-32,54,{"Preview one sampled colour roll.","Colour and placement probabilities are estimates."},14)
			colour.method=new("DropDownControl"):DropDownControl(ui.anchor,{16,90,cw-32,28},options)
			if item.corrupted then colour.method:SelByValue("tainted_chromatic","val") end
			local function method() return colour.method:GetSelValueByKey("val") end
			local checked,cached
			local function reason() local selected=method();if checked~=selected then checked=selected;cached=unique.colourReason(raw,selected) end;return cached end
			ui.label(colour,"availability",16,132,"",14);colour.availability.label=function() return "^7"..ui.fit(reason() or "Ready to preview; no currency is spent.",cw-32,14) end
			ui.label(colour,"targetLabel",16,164,"Desired colours (R, G, B, W)",14)
			ui.label(colour,"placementLabel",240,164,"Placement",14)
			colour.target=new("EditControl"):EditControl(ui.anchor,{16,185,208,26},"","e.g. RGB",nil,6)
			colour.placement=new("DropDownControl"):DropDownControl(ui.anchor,{240,185,cw-256,26},{"Anywhere on item","In one linked group"})
			ui.label(colour,"attemptsLabel",16,244,"Attempt limit (1-2000)",14)
			colour.attempts=new("EditControl"):EditControl(ui.anchor,{16,265,cw-32,26},"100","Max attempts",nil,4)
			local function linked() return colour.placement:GetSelValue()=="In one linked group" end
			local function stopText(target,linkedColours) return "At least "..target..(linkedColours and " sockets in one linked group" or " sockets in any order") end
			local function replaceableColourStep()
				local recipe=draft.nativeRecipe
				if not recipe or #recipe.steps~=1 or not recipe.requirements then return nil end
				local target=recipe.requirements.socketColours;local action=recipe.steps[1].method
				if type(target)~="string" or not (action=="chromatic" or action=="tainted_chromatic" or action=="omen_trichromatism") then return nil end
				local expected=unique.guideAction(action,1,info.resource,item.corrupted,#item.sockets);local found
				for index,step in ipairs(draft.steps) do
					if step.uniqueCraft and step.uniqueCraft.method==action and step.uniqueCraft.count==1 and not step.done and (not step.onFailure or step.onFailure=="" or step.onFailure=="Stop after "..(recipe.steps[1].maxAttempts or 100).." attempts.") and step.action==expected and step.stopWhen==stopText(target,recipe.requirements.linkedColours) then
						if found then return nil end;found=index
					end
				end
				return found
			end
			local function targetReason()
				if reason() then return reason() end
				if raw~=draft.startingItem or #history>0 then return "Return to the starting item before saving a direct colour plan." end
				if #draft.steps>=40 and not replaceableColourStep() then return "The guide has room for up to 40 steps." end
				local attempts=tonumber(colour.attempts.buf);if not attempts or attempts~=math.floor(attempts) or attempts<1 or attempts>2000 then return "Enter an attempt limit from 1 to 2000." end
				return unique.colourTargetReason(item,method(),colour.target.buf:upper(),linked())
			end
			ui.label(colour,"targetHelp",16,222,"",14);colour.targetHelp.label=function() local why,met=targetReason();return "^7"..ui.fit(why or (met and "Already met; the plan will use no currency." or "Ready to save a colour plan."),cw-32,14) end
			colour.apply=new("ButtonControl"):ButtonControl(ui.anchor,{16,ch-48,140,28},"Preview roll",function()
				local choice=method();colourRollCounter=colourRollCounter%2147483646+1;local seed=require("Modules.CalcEncounter").seed(104729,colourRollCounter,79)
				local result=unique.colour(raw,choice,seed);history[#history+1]=raw;actions[#actions+1]=choice;redo={};raw=result.itemText;main:ClosePopup();refresh(true)
			end)
			colour.apply.enabled=function() return not reason() end
			colour.apply.tooltipText=function() return reason() or "Preview one sampled socket-colour outcome." end
			colour.plan=new("ButtonControl"):ButtonControl(ui.anchor,{168,ch-48,150,28},"Save colour plan",function()
				local why=targetReason();assert(not why,why);local choice=method();local target=colour.target.buf:upper();local together=linked();local attempts=tonumber(colour.attempts.buf)
				local requirements={socketColours=target,linkedColours=together}
				local recipe={steps={{method=choice,maxAttempts=attempts,untilRequirements=copyTable(requirements)}},targets={},requirements=requirements}
				require("Modules.CraftingSimulator").validateRecipe(recipe)
				local replaceIndex=replaceableColourStep()
				local function keepPlan()
					local updated=copyTable(draft);updated.nativeRecipe=recipe
					local step={action=unique.guideAction(choice,1,info.resource,item.corrupted,#item.sockets),stopWhen=stopText(target,together),onFailure="Stop after "..attempts.." attempts.",uniqueCraft={method=choice,count=1},done=false}
					if replaceIndex then updated.steps[replaceIndex]=step else updated.steps[#updated.steps+1]=step end
					draft=build.savers.CraftingProjects:Upsert(updated);refresh(true);c.notice.label="^7Colour plan kept. Save the build.";main:ClosePopup()
				end
				if draft.nativeRecipe then main:OpenConfirmPopup("Replace crafting recipe",replaceIndex and "Replace the saved recipe and its unchanged colour guide step?\nOther guide steps will be kept." or "Replace the saved recipe with this colour plan?\nExisting guide steps will be kept.","Replace",keepPlan) else keepPlan() end
			end)
			colour.plan.enabled=function() return not targetReason() end
			colour.plan.tooltipText=function() return targetReason() or "Save a bounded repeat-until-colours recipe and guide step." end
			colour.close=new("ButtonControl"):ButtonControl(ui.anchor,{cw-132,ch-48,116,28},"Cancel",function() main:ClosePopup() end)
			ui.style(colour,{apply=true});for _,control in pairs(colour) do control.layoutAudit="unique-socket-colours" end
			main:OpenPopup(cw,ch,"Socket colours",colour,nil,nil,"close")
		end)
		controls.links=new("ButtonControl"):ButtonControl(ui.anchor,{235,height-48,75,28},"Links",function()
			main:ClosePopup();local link={};local lw,lh=480,384
			ui.description(link,"help",16,25,lw-32,54,{"Preview one sampled link roll.","Link probabilities and tainted outcomes are estimates."},14)
			link.method=new("DropDownControl"):DropDownControl(ui.anchor,{16,90,lw-32,28},{{label="Orb of Fusing",val="fusing"},{label="Tainted Orb of Fusing",val="tainted_fusing"}})
			if item.corrupted then link.method:SelByValue("tainted_fusing","val") end
			local function method() return link.method:GetSelValueByKey("val") end
			local checked,cached;local function reason() local selected=method();if checked~=selected then checked=selected;cached=unique.randomLinkReason(raw,selected) end;return cached end
			ui.label(link,"availability",16,132,"",14);link.availability.label=function() return "^7"..ui.fit(reason() or "Ready to preview; no currency is spent.",lw-32,14) end
			ui.label(link,"targetLabel",16,164,"Minimum linked sockets",14)
			link.target=new("EditControl"):EditControl(ui.anchor,{16,185,lw-32,26},"","e.g. 4",nil,1)
			ui.label(link,"attemptsLabel",16,244,"Attempt limit (1-2000)",14)
			link.attempts=new("EditControl"):EditControl(ui.anchor,{16,265,lw-32,26},"100","Max attempts",nil,4)
			local function replaceableLinkStep()
				local recipe=draft.nativeRecipe;if not recipe or #recipe.steps~=1 or not recipe.requirements then return nil end
				local target=recipe.requirements.links;local action=recipe.steps[1].method
				if type(target)~="number" or not (action=="fusing" or action=="tainted_fusing") then return nil end
				local expected=unique.guideAction(action,1,info.resource,item.corrupted,#item.sockets);local found
				for index,step in ipairs(draft.steps) do
					if step.uniqueCraft and step.uniqueCraft.method==action and step.uniqueCraft.count==1 and not step.done and (not step.onFailure or step.onFailure=="" or step.onFailure=="Stop after "..(recipe.steps[1].maxAttempts or 100).." attempts.") and step.action==expected and step.stopWhen=="At least "..target.." linked sockets" then
						if found then return nil end;found=index
					end
				end
				return found
			end
			local function targetReason()
				if raw~=draft.startingItem or #history>0 then return "Return to the starting item before saving a direct link plan." end
				if #draft.steps>=40 and not replaceableLinkStep() then return "The guide has room for up to 40 steps." end
				local attempts=tonumber(link.attempts.buf);if not attempts or attempts~=math.floor(attempts) or attempts<1 or attempts>2000 then return "Enter an attempt limit from 1 to 2000." end
				local value=tonumber(link.target.buf)
				if not value or value~=math.floor(value) or value<2 or value>#item.sockets then return "Enter a link target from 2 to the item's socket count." end
				local groups,best={},0;for _,socket in ipairs(item.sockets) do groups[socket.group]=(groups[socket.group] or 0)+1;best=math.max(best,groups[socket.group]) end
				local why=reason();local met=best>=value
				if why and not (met and why=="The item is already fully linked") then return why end
				if met then return nil,true end
			end
			ui.label(link,"targetHelp",16,222,"",14);link.targetHelp.label=function() local why,met=targetReason();return "^7"..ui.fit(why or (met and "Already met; the plan will use no currency." or "Ready to save a link plan."),lw-32,14) end
			link.apply=new("ButtonControl"):ButtonControl(ui.anchor,{16,lh-48,140,28},"Preview roll",function()
				local choice=method();colourRollCounter=colourRollCounter%2147483646+1;local seed=require("Modules.CalcEncounter").seed(104729,colourRollCounter,79)
				local result=unique.randomLinks(raw,choice,seed);history[#history+1]=raw;actions[#actions+1]=choice;redo={};raw=result.itemText;main:ClosePopup();refresh(true)
			end)
			link.apply.enabled=function() return not reason() end;link.apply.tooltipText=function() return reason() or "Preview one sampled socket-link outcome." end
			link.plan=new("ButtonControl"):ButtonControl(ui.anchor,{168,lh-48,150,28},"Save link plan",function()
				local why=targetReason();assert(not why,why);local choice=method();local target=tonumber(link.target.buf);local attempts=tonumber(link.attempts.buf)
				local requirements={links=target};local recipe={steps={{method=choice,maxAttempts=attempts,untilRequirements=copyTable(requirements)}},targets={},requirements=requirements}
				require("Modules.CraftingSimulator").validateRecipe(recipe);local replaceIndex=replaceableLinkStep()
				local function keepPlan()
					local updated=copyTable(draft);updated.nativeRecipe=recipe
					local step={action=unique.guideAction(choice,1,info.resource,item.corrupted,#item.sockets),stopWhen="At least "..target.." linked sockets",onFailure="Stop after "..attempts.." attempts.",uniqueCraft={method=choice,count=1},done=false}
					if replaceIndex then updated.steps[replaceIndex]=step else updated.steps[#updated.steps+1]=step end
					draft=build.savers.CraftingProjects:Upsert(updated);refresh(true);c.notice.label="^7Link plan kept. Save the build.";main:ClosePopup()
				end
				if draft.nativeRecipe then main:OpenConfirmPopup("Replace crafting recipe",replaceIndex and "Replace the saved recipe and its unchanged link guide step?\nOther guide steps will be kept." or "Replace the saved recipe with this link plan?\nExisting guide steps will be kept.","Replace",keepPlan) else keepPlan() end
			end)
			link.plan.enabled=function() return not targetReason() end;link.plan.tooltipText=function() return targetReason() or "Save a bounded repeat-until-linked recipe and guide step." end
			link.close=new("ButtonControl"):ButtonControl(ui.anchor,{lw-132,lh-48,116,28},"Cancel",function() main:ClosePopup() end)
			ui.style(link,{apply=true});for _,control in pairs(link) do control.layoutAudit="unique-socket-links" end
			main:OpenPopup(lw,lh,"Socket links",link,nil,nil,"close")
		end)
		controls.roll=new("ButtonControl"):ButtonControl(ui.anchor,{318,height-48,84,28},"Roll",function()
			main:ClosePopup();local roll={};local rw,rh=480,340
			ui.description(roll,"help",16,25,rw-32,50,{"Preview a sampled socket-count roll.","Socket odds and placement are estimates."},14)
			roll.method=new("DropDownControl"):DropDownControl(ui.anchor,{16,80,rw-32,28},{{label="Jeweller's Orb",val="jeweller"},{label="Tainted Jeweller's Orb",val="tainted_jeweller"}})
			if item.corrupted then roll.method:SelByValue("tainted_jeweller","val") end
			local function method() return roll.method:GetSelValueByKey("val") end
			local checked,cached;local function reason() local choice=method();if choice~=checked then checked=choice;cached=unique.randomSocketReason(raw,choice) end;return cached end
			ui.label(roll,"availability",16,120,"",14);roll.availability.label=function() return "^7"..ui.fit(reason() or "Ready to preview; no currency is spent.",rw-32,14) end
			ui.label(roll,"targetLabel",16,154,"Desired socket count",14)
			roll.target=new("EditControl"):EditControl(ui.anchor,{16,176,200,26},"","e.g. 4",nil,1)
			ui.label(roll,"attemptsLabel",240,154,"Attempt limit (1-2000)",14)
			roll.attempts=new("EditControl"):EditControl(ui.anchor,{240,176,rw-256,26},"100","Max attempts",nil,4)
			local function replaceableSocketStep()
				local recipe=draft.nativeRecipe;if not recipe or #recipe.steps~=1 or not recipe.requirements then return nil end
				local target=recipe.requirements.exactSockets;local action=recipe.steps[1].method
				if type(target)~="number" or not (action=="jeweller" or action=="tainted_jeweller") then return nil end
				local expected=unique.guideAction(action,1,info.resource,item.corrupted,#item.sockets);local found
				for index,step in ipairs(draft.steps) do
					if step.uniqueCraft and step.uniqueCraft.method==action and step.uniqueCraft.count==1 and not step.done and (not step.onFailure or step.onFailure=="" or step.onFailure=="Stop after "..(recipe.steps[1].maxAttempts or 100).." attempts.") and step.action==expected and step.stopWhen=="Exactly "..target.." sockets" then
						if found then return nil end;found=index
					end
				end
				return found
			end
			local function planReason()
				if raw~=draft.startingItem or #history>0 then return "Return to the starting item before saving a direct socket plan." end
				if #draft.steps>=40 and not replaceableSocketStep() then return "The guide has room for up to 40 steps." end
				local attempts=tonumber(roll.attempts.buf);if not attempts or attempts~=math.floor(attempts) or attempts<1 or attempts>2000 then return "Enter an attempt limit from 1 to 2000." end
				local target=tonumber(roll.target.buf);if not target or target~=math.floor(target) or target<1 or target>unique.omenCount(item) then return "Enter a socket count within the natural limit." end
				local why=reason();local met=#item.sockets==target
				if why and not (met and why=="The item already has its maximum natural socket count.") then return why end
				if met then return nil,true end
			end
			ui.label(roll,"targetHelp",16,222,"",14);roll.targetHelp.label=function()
				local why,met=planReason();local target=tonumber(roll.target.buf)
				local note=met and "Already met; the plan will use no currency." or method()=="jeweller" and target and target<unique.omenCount(item) and "Maximum sockets stop rerolls; use the bench to reset." or "Ready to save a socket plan."
				return "^7"..ui.fit(why or note,rw-32,14)
			end
			roll.apply=new("ButtonControl"):ButtonControl(ui.anchor,{16,rh-48,140,28},"Preview roll",function()
				local choice=method();colourRollCounter=colourRollCounter%2147483646+1;local seed=require("Modules.CalcEncounter").seed(104729,colourRollCounter,79)
				local result=unique.randomSockets(raw,choice,seed);history[#history+1]=raw;actions[#actions+1]=choice;redo={};raw=result.itemText;main:ClosePopup();refresh(true)
			end)
			roll.apply.enabled=function() return not reason() end;roll.apply.tooltipText=function() return reason() or "Preview one sampled socket-count outcome." end
			roll.plan=new("ButtonControl"):ButtonControl(ui.anchor,{168,rh-48,150,28},"Save socket plan",function()
				local why=planReason();assert(not why,why);local choice=method();local target=tonumber(roll.target.buf);local attempts=tonumber(roll.attempts.buf)
				local requirements={exactSockets=target};local recipe={steps={{method=choice,maxAttempts=attempts,untilRequirements=copyTable(requirements)}},targets={},requirements=requirements}
				require("Modules.CraftingSimulator").validateRecipe(recipe);local replaceIndex=replaceableSocketStep()
				local function keepPlan()
					local updated=copyTable(draft);updated.nativeRecipe=recipe
					local step={action=unique.guideAction(choice,1,info.resource,item.corrupted,#item.sockets),stopWhen="Exactly "..target.." sockets",onFailure="Stop after "..attempts.." attempts.",uniqueCraft={method=choice,count=1},done=false}
					if replaceIndex then updated.steps[replaceIndex]=step else updated.steps[#updated.steps+1]=step end
					draft=build.savers.CraftingProjects:Upsert(updated);refresh(true);c.notice.label="^7Socket plan kept. Save the build.";main:ClosePopup()
				end
				if draft.nativeRecipe then main:OpenConfirmPopup("Replace crafting recipe",replaceIndex and "Replace the saved recipe and its unchanged socket guide step?\nOther guide steps will be kept." or "Replace the saved recipe with this socket plan?\nExisting guide steps will be kept.","Replace",keepPlan) else keepPlan() end
			end)
			roll.plan.enabled=function() return not planReason() end;roll.plan.tooltipText=function() return planReason() or "Save a bounded repeat-until-sockets recipe and guide step." end
			roll.close=new("ButtonControl"):ButtonControl(ui.anchor,{rw-132,rh-48,116,28},"Cancel",function() main:ClosePopup() end)
			ui.style(roll,{apply=true});for _,control in pairs(roll) do control.layoutAudit="unique-socket-roll" end
			main:OpenPopup(rw,rh,"Roll sockets",roll,nil,nil,"close")
		end)
		controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{410,height-48,94,28},"Cancel",function() main:ClosePopup() end)
		ui.style(controls,{apply=true});for _,control in pairs(controls) do control.layoutAudit="unique-socket-count" end
		main:OpenPopup(width,height,"Socket count",controls,nil,nil,"close")
	end)
	local checkedSocketRaw,cachedSocketAvailability,cachedSocketReason
	local function socketCountAvailability()
		if checkedSocketRaw==raw then return cachedSocketAvailability,cachedSocketReason end
		checkedSocketRaw=raw
		local limit=require("Modules.CraftingSimulator").socketLimit({item=item});local reason
		for count=2,limit do local why=unique.socketCountReason(raw,count);if not why then cachedSocketAvailability,cachedSocketReason=true,nil;return true end;reason=reason or why end
		cachedSocketAvailability,cachedSocketReason=false,reason or "This base cannot use socket-count recipes.";return cachedSocketAvailability,cachedSocketReason
	end
	c.socketCount.width=130
	button("omenJeweller",130,"Omen + Jeweller",function() local result=unique.socketCount(raw,unique.omenCount(item),"omen_jeweller");history[#history+1]=raw;actions[#actions+1]="omen_jeweller";redo={};raw=result.itemText;refresh(true) end)
	c.omenJeweller.x=156;c.omenJeweller.width=130;c.omenJeweller.enabled=function() return not omenJewellerReason end
	c.omenJeweller.tooltipText=function() return omenJewellerReason or "Adds white sockets up to the natural limit using an Omen of the Jeweller and a Jeweller's Orb." end
	c.socketCount.enabled=function() local allowed=socketCountAvailability();return allowed or not colourReason end
	c.socketCount.tooltipText=function() local allowed,reason=socketCountAvailability();return allowed and "Preview socket-count or socket-colour crafts." or not colourReason and "Preview socket-colour crafts." or reason end
	button("apply",198,"Use quality currency",function()
		local action=item.corrupted and "tainted_quality" or "quality";local result
		if action=="tainted_quality" then colourRollCounter=colourRollCounter%2147483646+1;result=unique.taintedQuality(raw,require("Modules.CalcEncounter").seed(104729,colourRollCounter,79)) else result=unique.apply(raw) end
		history[#history+1]=raw;actions[#actions+1]=action;redo={};raw=result.itemText;refresh(true)
	end)
	c.apply.enabled=function() return item.corrupted and not unique.taintedQualityReason(raw) or not item.corrupted and info.available end
	c.apply.tooltipText=function() return item.corrupted and (taintedQualityReason or "Sample a tainted quality roll. The 1-20% range and odds are estimates.") or info.available and "Use "..info.resource.." to add 1% quality." or "Ordinary quality currency cannot exceed 20%." end
	button("qualityPlan",198,"Plan quality",function()
		local controls={};local qw,qh=480,310
		ui.description(controls,"help",16,25,qw-32,50,{"Save a target without rolling the item.","Tainted quality probabilities are estimates."},14)
		ui.label(controls,"targetLabel",16,90,"Minimum quality (1-20%)",14)
		controls.target=new("EditControl"):EditControl(ui.anchor,{16,112,200,26},"","e.g. 20",nil,2)
		ui.label(controls,"attemptsLabel",240,90,"Attempt limit (1-2000)",14)
		controls.attempts=new("EditControl"):EditControl(ui.anchor,{240,112,qw-256,26},"100","Max attempts",nil,4)
		local function replaceable()
			local recipe=draft.nativeRecipe;if not recipe or #recipe.steps~=1 or not recipe.requirements then return nil end
			local target=recipe.requirements.minQuality;local step=recipe.steps[1]
			if type(target)~="number" or step.method~="tainted_quality" then return nil end
			local expected=unique.guideAction("tainted_quality",1,info.resource,item.corrupted,#item.sockets);local found
			for index,guide in ipairs(draft.steps) do
				if guide.uniqueCraft and guide.uniqueCraft.method=="tainted_quality" and guide.uniqueCraft.count==1 and not guide.done and (not guide.onFailure or guide.onFailure=="" or guide.onFailure=="Stop after "..(step.maxAttempts or 100).." attempts.") and guide.action==expected and guide.stopWhen=="At least "..target.."% quality" then
					if found then return nil end;found=index
				end
			end
			return found
		end
		local function reason()
			if taintedQualityReason then return taintedQualityReason end
			if raw~=draft.startingItem or #history>0 then return "Return to the starting item before saving a quality plan." end
			if #draft.steps>=40 and not replaceable() then return "The guide has room for up to 40 steps." end
			local target=tonumber(controls.target.buf);if not target or target~=math.floor(target) or target<1 or target>20 then return "Enter a quality target from 1 to 20." end
			local attempts=tonumber(controls.attempts.buf);if not attempts or attempts~=math.floor(attempts) or attempts<1 or attempts>2000 then return "Enter an attempt limit from 1 to 2000." end
			if info.quality>=target then return nil,true end
		end
		ui.label(controls,"targetHelp",16,160,"",14);controls.targetHelp.label=function() local why,met=reason();return "^7"..ui.fit(why or (met and "Already met; the plan will use no currency." or "Ready to save a quality plan."),qw-32,14) end
		controls.plan=new("ButtonControl"):ButtonControl(ui.anchor,{16,qh-48,150,28},"Save quality plan",function()
			local why=reason();assert(not why,why);local target=tonumber(controls.target.buf);local attempts=tonumber(controls.attempts.buf);local requirements={minQuality=target}
			local recipe={steps={{method="tainted_quality",maxAttempts=attempts,untilRequirements=copyTable(requirements)}},targets={},requirements=requirements};require("Modules.CraftingSimulator").validateRecipe(recipe)
			local replaceIndex=replaceable()
			local function keepPlan()
				local updated=copyTable(draft);updated.nativeRecipe=recipe
				local step={action=unique.guideAction("tainted_quality",1,info.resource,item.corrupted,#item.sockets),stopWhen="At least "..target.."% quality",onFailure="Stop after "..attempts.." attempts.",uniqueCraft={method="tainted_quality",count=1},done=false}
				if replaceIndex then updated.steps[replaceIndex]=step else updated.steps[#updated.steps+1]=step end
				draft=build.savers.CraftingProjects:Upsert(updated);refresh(true);c.notice.label="^7Quality plan kept. Save the build.";main:ClosePopup()
			end
			if draft.nativeRecipe then main:OpenConfirmPopup("Replace crafting recipe",replaceIndex and "Replace the saved recipe and its unchanged quality guide step?\nOther guide steps will be kept." or "Replace the saved recipe with this quality plan?\nExisting guide steps will be kept.","Replace",keepPlan) else keepPlan() end
		end)
		controls.plan.enabled=function() return not reason() end;controls.plan.tooltipText=function() return reason() or "Save a bounded repeat-until-quality recipe and guide step." end
		controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{qw-132,qh-48,116,28},"Cancel",function() main:ClosePopup() end)
		ui.style(controls,{plan=true});for _,control in pairs(controls) do control.layoutAudit="unique-quality-plan" end
		main:OpenPopup(qw,qh,"Tainted quality target",controls,nil,nil,"close")
	end)
	c.qualityPlan.x=156;c.qualityPlan.width=130;c.qualityPlan.shown=function() return item.corrupted and not taintedQualityReason end
	button("divine",198,"Divine Orb",function()
		local controls={};local dw,dh=500,340
		ui.description(controls,"help",16,25,dw-32,50,{"Preview a roll or plan a stat or modifier target.","Modifier-value probabilities are estimates."},14)
		local stats=require("Modules.CraftingItemStats");local values=stats.itemValues(item);local options,selection={},{}
		for _,field in ipairs(stats.fields) do if values[field[1]] and values[field[1]]>0 then options[#options+1]={label=field[2],val=field[1]};selection[field[1]]={kind="stat",label=field[2],current=values[field[1]]} end end
		for index,row in ipairs(unique.divineOptions(raw) or {}) do local key="modifier:"..index;options[#options+1]={label=ui.fit("Roll: "..row.line,210,14),val=key};selection[key]={kind="modifier",line=row.line,min=row.min,max=row.max,current=row.current} end
		if #options==0 then options[1]={label="No supported target",val=""} end
		ui.label(controls,"statLabel",16,90,"Stat or modifier roll",14)
		controls.stat=new("DropDownControl"):DropDownControl(ui.anchor,{16,112,220,26},options)
		controls.target=new("EditControl"):EditControl(ui.anchor,{252,112,dw-268,26},"","Minimum",nil,10)
		ui.label(controls,"attemptsLabel",16,155,"Attempt limit (1-2000)",14)
		controls.attempts=new("EditControl"):EditControl(ui.anchor,{16,177,dw-32,26},"100","Max attempts",nil,4)
		local function stat() return controls.stat:GetSelValueByKey("val") end
		local function replaceable()
			local recipe=draft.nativeRecipe;if not recipe or #recipe.steps~=1 or recipe.steps[1].method~="divine" or not recipe.requirements then return nil end
			local stop
			if recipe.requirements.uniqueModifier then local goal=recipe.requirements.uniqueModifier;stop="Roll at least "..goal.minValue.." on "..goal.line
			elseif type(recipe.requirements.nativeStats)=="table" then
				local key,target=next(recipe.requirements.nativeStats);if not key or next(recipe.requirements.nativeStats,key)~=nil then return nil end
				local label;for _,field in ipairs(stats.fields) do if field[1]==key then label=field[2];break end end;if not label then return nil end;stop="At least "..target.." "..label
			else return nil end
			local expected=unique.guideAction("divine",1,info.resource,item.corrupted,#item.sockets);local found
			for index,guide in ipairs(draft.steps) do
				if guide.uniqueCraft and guide.uniqueCraft.method=="divine" and guide.uniqueCraft.count==1 and not guide.done and (not guide.onFailure or guide.onFailure=="" or guide.onFailure=="Stop after "..(recipe.steps[1].maxAttempts or 100).." attempts.") and guide.action==expected and guide.stopWhen==stop then
					if found then return nil end;found=index
				end
			end
			return found
		end
		local function reason()
			if divineReason then return divineReason end
			if raw~=draft.startingItem or #history>0 then return "Return to the starting item before saving a Divine plan." end
			if #draft.steps>=40 and not replaceable() then return "The guide has room for up to 40 steps." end
			local selected=selection[stat()];if not selected then return "No supported target is available." end
			local target=tonumber(controls.target.buf);if not target or target~=target or target< -100000 or target>10000000 or selected.kind=="stat" and target<0 then return "Enter a valid minimum target." end
			if selected.kind=="modifier" and (target~=math.floor(target) or target<selected.min or target>selected.max) then return "Enter a roll from "..selected.min.." to "..selected.max.."." end
			local attempts=tonumber(controls.attempts.buf);if not attempts or attempts~=math.floor(attempts) or attempts<1 or attempts>2000 then return "Enter an attempt limit from 1 to 2000." end
			if selected.current>=target then return nil,true end
		end
		ui.label(controls,"targetHelp",16,222,"",14);controls.targetHelp.label=function() local why,met=reason();return "^7"..ui.fit(why or (met and "Already met; the plan will use no currency." or "Ready to save a target plan."),dw-32,14) end
		ui.label(controls,"selectedInfo",16,250,"",14);controls.selectedInfo.label=function()
			local selected=selection[stat()];if not selected or selected.kind~="modifier" then return "" end
			return "^7"..ui.fit(selected.line.." | current roll: "..selected.current,dw-32,14)
		end
		controls.apply=new("ButtonControl"):ButtonControl(ui.anchor,{16,dh-48,140,28},"Preview roll",function()
			colourRollCounter=colourRollCounter%2147483646+1;local seed=require("Modules.CalcEncounter").seed(104729,colourRollCounter,79)
			local result=unique.divine(raw,seed);history[#history+1]=raw;actions[#actions+1]="divine";redo={};raw=result.itemText;main:ClosePopup();refresh(true)
		end)
		controls.plan=new("ButtonControl"):ButtonControl(ui.anchor,{168,dh-48,150,28},"Save Divine plan",function()
			local why=reason();assert(not why,why);local key=stat();local target=tonumber(controls.target.buf);local attempts=tonumber(controls.attempts.buf)
			local selected=selection[key];local requirements=selected.kind=="modifier" and {uniqueModifier={line=selected.line,minValue=target}} or {nativeStats={[key]=target}}
			local stop=selected.kind=="modifier" and ("Roll at least "..target.." on "..selected.line) or ("At least "..target.." "..selected.label)
			local recipe={rarity="UNIQUE",steps={{method="divine",maxAttempts=attempts,untilRequirements=copyTable(requirements)}},targets={},requirements=requirements};require("Modules.CraftingSimulator").validateRecipe(recipe);local replaceIndex=replaceable()
			local function keepPlan()
				local updated=copyTable(draft);updated.nativeRecipe=recipe;local step={action=unique.guideAction("divine",1,info.resource,item.corrupted,#item.sockets),stopWhen=stop,onFailure="Stop after "..attempts.." attempts.",uniqueCraft={method="divine",count=1},done=false}
				if replaceIndex then updated.steps[replaceIndex]=step else updated.steps[#updated.steps+1]=step end
				draft=build.savers.CraftingProjects:Upsert(updated);refresh(true);c.notice.label="^7Divine plan kept. Save the build.";main:ClosePopup()
			end
			if draft.nativeRecipe then main:OpenConfirmPopup("Replace crafting recipe",replaceIndex and "Replace the saved recipe and its unchanged Divine guide step?\nOther guide steps will be kept." or "Replace the saved recipe with this Divine plan?\nExisting guide steps will be kept.","Replace",keepPlan) else keepPlan() end
		end)
		controls.plan.enabled=function() return not reason() end;controls.plan.tooltipText=function() return reason() or "Save a bounded repeat-until-target recipe and guide step." end
		controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{dw-132,dh-48,116,28},"Cancel",function() main:ClosePopup() end)
		ui.style(controls,{apply=true});for _,control in pairs(controls) do control.layoutAudit="unique-divine-target" end
		main:OpenPopup(dw,dh,"Divine Orb",controls,nil,nil,"close")
	end)
	c.divine.x=156;c.divine.width=130;c.divine.shown=function() return not item.corrupted end;c.divine.enabled=function() return not divineReason end
	c.divine.tooltipText=function() return divineReason or "Preview a Divine Orb roll. Modifier-value probabilities are estimated." end
	button("link",236,"Bestiary link",function() local result=unique.link(raw);history[#history+1]=raw;actions[#actions+1]="beast_max_links";redo={};raw=result.itemText;refresh(true) end)
	c.link.width=130
	c.link.enabled=function() return not linkReason end
	c.link.tooltipText=function()
		return linkReason or "Links existing sockets using a Black Morrigan and a Craicic Sand Spitter."
	end
	button("omen",236,"Omen + Fusing",function() local result=unique.link(raw,"omen_connections");history[#history+1]=raw;actions[#actions+1]="omen_connections";redo={};raw=result.itemText;refresh(true) end)
	c.omen.x=156;c.omen.width=130;c.omen.enabled=function() return not linkReason end
	c.omen.tooltipText=function() return linkReason or "Links existing sockets using an Omen of Connections and an Orb of Fusing." end
	button("benchLink",274,"Bench: link",function() local result=unique.link(raw,"socket_bench");history[#history+1]=raw;actions[#actions+1]="socket_bench";redo={};raw=result.itemText;refresh(true) end)
	c.benchLink.width=130;c.benchLink.enabled=function() return not benchLinkReason end
	c.benchLink.tooltipText=function()
		if benchLinkReason then return benchLinkReason end
		local cost=require("Modules.CraftingSimulator").components({method="socket_bench",count=#item.sockets,linked=true},{sockets=item.sockets,corrupted=item.corrupted})
		local amount=cost["Metadata/Items/Currency/CurrencyRerollSocketLinks"] or 0
		return "Links existing sockets for "..amount.." Orb"..(amount==1 and "" or "s").." of Fusing"..(item.corrupted and " and "..amount.." Vaal Orb"..(amount==1 and "" or "s").."." or ".")
	end
	button("white",274,"Bench: white",function() local result=unique.white(raw);history[#history+1]=raw;actions[#actions+1]="socket_white_bench";redo={};raw=result.itemText;refresh(true) end)
	c.white.x=156;c.white.width=130
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
		local colourSeen=false
		for _,action in ipairs(actions) do
			local colour=action=="chromatic" or action=="tainted_chromatic" or action=="omen_trichromatism" or action=="fusing" or action=="tainted_fusing" or action=="jeweller" or action=="tainted_jeweller" or action=="tainted_quality"
			if colour then if colourSeen then return false end;colourSeen=true
			elseif colourSeen and action~="quality" then return false
			elseif action~="quality" and action~="beast_max_links" and action~="omen_connections" and action~="omen_jeweller" and action~="socket_white_bench" and action~="socket_bench" and not action:match("^socket_count_bench:[2-6]$") then return false end
		end
		return true
	end
	local function createRecipe()
		assert(canCreateRecipe(),"A complete supported preview from the starting item is needed")
		local steps,requirements={},{};local i=1;local sampled=false
		while i<=#actions do
			local action=actions[i]
			local socketCount=tonumber(action:match("^socket_count_bench:([2-6])$"))
			if action=="quality" then
				local first=i;while i<=#actions and actions[i]=="quality" do i=i+1 end
				local _,after=unique.inspect(history[i] or raw);local count=i-first
				steps[#steps+1]={method="quality",maxAttempts=count,untilRequirements={minQuality=after.quality}}
				requirements.minQuality=info.quality
			elseif socketCount then
				steps[#steps+1]={method="socket_bench",count=socketCount};requirements.exactSockets=#item.sockets;i=i+1
			elseif action=="tainted_quality" then
				requirements.minQuality=info.quality;steps[#steps+1]={method=action,maxAttempts=100,untilRequirements={minQuality=info.quality}};sampled=true;i=i+1
			elseif action=="jeweller" or action=="tainted_jeweller" then
				requirements.exactSockets=#item.sockets;steps[#steps+1]={method=action,maxAttempts=100,untilRequirements={exactSockets=#item.sockets}};sampled=true;i=i+1
			elseif action=="fusing" or action=="tainted_fusing" then
				local counts,best={},0;for _,socket in ipairs(item.sockets) do counts[socket.group]=(counts[socket.group] or 0)+1;best=math.max(best,counts[socket.group]) end
				requirements.links=best;steps[#steps+1]={method=action,maxAttempts=100,untilRequirements={links=best}};sampled=true;i=i+1
			elseif action=="chromatic" or action=="tainted_chromatic" or action=="omen_trichromatism" then
				local colours={};for _,socket in ipairs(item.sockets) do colours[#colours+1]=socket.color end
				local target=table.concat(colours);requirements.socketColours=target
				steps[#steps+1]={method=action,maxAttempts=100,untilRequirements={socketColours=target}};sampled=true;i=i+1
			else
				local before=unique.inspect(history[i]);steps[#steps+1]=action=="socket_bench" and {method=action,count=#before.sockets,linked=true} or {method=action};i=i+1
				if action=="omen_jeweller" then requirements.exactSockets=#item.sockets
				elseif action=="socket_white_bench" then requirements.socketColours=string.rep("W",#item.sockets)
				else local best=0;for _,socket in ipairs(item.sockets) do local count=0;for _,other in ipairs(item.sockets) do if other.group==socket.group then count=count+1 end end;best=math.max(best,count) end;requirements.links=best end
			end
		end
		assert(#steps<=20,"This preview needs more than 20 recipe steps")
		local recipe={steps=steps,targets={},requirements=requirements}
		if sampled then
			assert(unique.matches(raw,requirements),"The preview does not meet its recipe goals")
		else
			local result=require("Modules.CraftingSimulator").simulate(draft.startingItem,recipe,{trials=1,maxActions=100})
			assert(result.sampleSuccess and result.sampleItem==raw,"The recipe did not reproduce this preview; review the actions")
		end
		return recipe
	end
	button("recipe",388,"Check recipe",function()
		if not draft.nativeRecipe then
			local updated=copyTable(draft);updated.nativeRecipe=createRecipe();draft=build.savers.CraftingProjects:Upsert(updated)
			refresh(true);c.notice.label="^7Recipe saved. Save the build.";return
		end
		local stochastic=false;for _,step in ipairs(draft.nativeRecipe.steps) do if step.method=="tainted_quality" or step.method=="jeweller" or step.method=="tainted_jeweller" or step.method=="chromatic" or step.method=="tainted_chromatic" or step.method=="omen_trichromatism" or step.method=="fusing" or step.method=="tainted_fusing" then stochastic=true end end
		local budget=100
		if stochastic then local sum=0;for _,step in ipairs(draft.nativeRecipe.steps) do sum=sum+(step.maxAttempts or 1) end;budget=math.min(2000,math.max(100,sum)) end
		local trials=stochastic and math.max(1,math.min(20,math.floor(10000/budget))) or 1
		local capturedRaw=draft.startingItem;local capturedRecipe=copyTable(draft.nativeRecipe);local capturedPrice=draft.priceBook and copyTable(draft.priceBook);local capturedTree=build.spec.treeVersion
		local function run(checkpoint)
			return require("Modules.CraftingSimulator").simulate(capturedRaw,capturedRecipe,{trials=trials,maxActions=budget,retainSuccesses=stochastic and 1 or 0,priceBook=capturedPrice,treeVersion=capturedTree,checkpoint=checkpoint})
		end
		local function showResult(result)
		local kept=result.retainedSuccesses and result.retainedSuccesses[1];local outputItem=kept and kept.itemText or result.sampleItem;local outputSuccess=kept~=nil or result.sampleSuccess
		local rw,rh=math.min(760,main.screenW-40),math.min(520,main.screenH-60);local view={}
		ui.label(view,"heading",16,24,"Saved recipe result",20)
		local lines={result.sampled and string.format("%d trials: %.1f%% success (%.1f-%.1f%% interval).",result.trials,result.successChance,result.confidenceLow,result.confidenceHigh) or result.sampleSuccess and "Goal reached in the deterministic model." or "Goal not reached in the deterministic model.",
			"Starts from the saved starting item; the current preview is unchanged.",
			string.format("Mean actions: %.1f attempted, %.1f executed (limit %d).",result.meanActions,result.meanExecutedActions,budget),
			result.meanCost and string.format("Estimated cost: %.2f %s",result.meanCost,result.costCurrency) or "Cost unavailable: add prices for all used resources."}
		for _,entry in ipairs(result.resourceUsage or {}) do lines[#lines+1]=result.sampled and string.format("%s: %.2f per trial",entry.name,entry.meanPerTrial) or entry.name..": "..entry.amount end
		for _,warning in ipairs(result.warnings or {}) do lines[#lines+1]="Model note: "..warning.message end
		for message,count in pairs(result.transitionErrors or {}) do lines[#lines+1]="Rejected action ("..count.."): "..message end
		view.details=new("TextListControl"):TextListControl(ui.anchor,{16,62,300,rh-126},nil,ui.rows(lines,276,14))
		local render=require("Classes.JourneyItemControl").new(view,"resultItem",332,62,rw-348,rh-126,kept and "SUCCESSFUL SAMPLE" or "RESULT ITEM")
		render(require("Modules.CraftingProjects").item(outputItem))
		view.keep=new("ButtonControl"):ButtonControl(ui.anchor,{16,rh-48,160,28},"Keep as target",function()
			local function keepResult()
				local updated=copyTable(draft);updated.targetItem=outputItem
				draft=build.savers.CraftingProjects:Upsert(updated);refresh(true)
				c.notice.label="^7Recipe result kept. Save the build.";main:ClosePopup()
			end
			if draft.targetItem and draft.targetItem:match("%S") and draft.targetItem~=outputItem then
				main:OpenConfirmPopup("Replace crafting target","Replace the saved target with this modeled recipe result?\nUse build Save to persist the change.","Replace",keepResult)
			else keepResult() end
		end)
		view.keep.enabled=outputSuccess
		view.keep.tooltipText=outputSuccess and "Keep this modeled result as the guide's target." or "The recipe did not reach its goal."
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
		end
		if not stochastic then showResult(run());return end
		local tasks=require("Modules.CraftingTasks");local progress={};local pw,ph=420,168
		ui.label(progress,"heading",16,24,"Checking recipe",20)
		ui.label(progress,"status",16,70,"Preparing sampled trials...",14)
		progress.cancel=new("ButtonControl"):ButtonControl(ui.anchor,{16,ph-48,160,28},"Cancel",function() if tasks.job and tasks.job.owner==progress then tasks.cancel("Calculation cancelled.") end end)
		ui.style(progress);for _,control in pairs(progress) do control.layoutAudit="unique-recipe-progress" end
		local function closeProgress()
			if main.popups[1] and main.popups[1].controls==progress then main:ClosePopup();return true end
		end
		local job=tasks.start(build,run,function(result) if closeProgress() then showResult(result) end end,function(message)
			if closeProgress() and message~="Calculation cancelled." and message~="The active build changed" then main:OpenMessagePopup("Unique crafting",ui.errorText(message)) end
		end,function(state) progress.status.label=string.format("Trial %d / %d | %d successes",state.trial or 0,state.trials or trials,state.successes or 0) end,"Unique recipe simulation slice")
		job.owner=progress;main:OpenPopup(pw,ph,"Checking recipe",progress,nil,nil,"cancel")
	end)
	c.recipe.x=156;c.recipe.width=130;c.recipe.label=function() return draft.nativeRecipe and "Check recipe" or "Save recipe" end
	c.recipe.enabled=function() return draft.nativeRecipe~=nil or canCreateRecipe() end
	c.recipe.tooltipText=function() return draft.nativeRecipe and "Check the saved native recipe from its starting item. No changes are made." or canCreateRecipe() and "Save this complete preview as a recipe; then check its result and cost." or "Preview supported actions from the starting item. For sampled socket crafts, use one sampled action followed only by quality actions." end
	ui.label(c,"notice",16,426,restored and "^7Session preview restored." or "",14)
	local art,artCache=nil,{}
	local function icon(method)
		local path=require("Modules.CraftingWorkbench").icon(method,nil,{item=item})
		if path and not artCache[path] then local handle=NewImageHandle();handle:Load(path);artCache[path]=handle end
		return path and artCache[path] or nil
	end
	updateIcons=function()
		c.apply.planningIcon=icon("quality")
		c.omenJeweller.planningIcon=icon("omen_jeweller");c.omen.planningIcon=icon("omen_connections");c.benchLink.planningIcon=icon("fusing");c.white.planningIcon=icon("socket_white_bench");c.socketCount.planningIcon=icon("jeweller")
	end
	local currency=new("Control"):Control(ui.anchor,{16,454,42,42});c.currency=currency
	function currency:Draw() if art then local x,y=self:GetPos();SetDrawColor(1,1,1);DrawImage(art,x,y,42,42) end end
	ui.description(c,"currencyNote",68,456,218,48,{"Preview only", "No currency is spent."},14)
	updateCurrency=function()
		local method=actions[#actions];local lines
		local countMethod=method and tonumber(method:match("^socket_count_bench:([2-6])$"))
		if method=="socket_white_bench" then
			method="socket_white_bench";lines={"Bench: 1 Orb of Scouring",item.corrupted and "+ 1 Vaal Orb | Preview" or "Preview only"}
		elseif countMethod then local components=require("Modules.CraftingSimulator").components({method="socket_bench",count=countMethod},{sockets=item.sockets,corrupted=item.corrupted});local amount=components["Metadata/Items/Currency/CurrencyRerollSocketNumbers"] or 0;method="jeweller";lines={"Bench: "..amount.." Jeweller's Orb"..(amount==1 and "" or "s"),item.corrupted and ("+ "..amount.." Vaal Orb"..(amount==1 and "" or "s").." | Preview") or "Preview only"}
		elseif method=="socket_bench" then local components=require("Modules.CraftingSimulator").components({method=method,count=#item.sockets,linked=true},{sockets=item.sockets,corrupted=item.corrupted});local count=components["Metadata/Items/Currency/CurrencyRerollSocketLinks"] or 0;lines={"Bench: "..count.." Orb"..(count==1 and "" or "s").." of Fusing",item.corrupted and ("+ "..count.." Vaal Orb"..(count==1 and "" or "s").." | Preview") or "Preview only"}
		elseif method=="fusing" then lines={"1 Orb of Fusing","Sampled preview"}
		elseif method=="divine" then lines={"1 Divine Orb","Sampled preview"}
		elseif method=="tainted_quality" then lines={"1 Tainted "..info.resource,"Sampled preview"}
		elseif method=="jeweller" then lines={"1 Jeweller's Orb","Sampled preview"}
		elseif method=="tainted_jeweller" then lines={"1 Tainted Jeweller's Orb","Sampled preview"}
		elseif method=="tainted_fusing" then lines={"1 Tainted Orb of Fusing","Sampled preview"}
		elseif method=="omen_connections" then lines={"Omen + Orb of Fusing","1 of each | Preview"}
		elseif method=="omen_jeweller" then lines={"Omen + Jeweller's Orb","1 of each | Preview"}
		elseif method=="omen_trichromatism" then lines={"Omen + Chromatic Orb","Sampled preview"}
		elseif method=="chromatic" then lines={"1 Chromatic Orb","Sampled preview"}
		elseif method=="tainted_chromatic" then lines={"1 Tainted Chromatic Orb","Sampled preview"}
		elseif method=="beast_max_links" then lines={"Black Morrigan + Sand Spitter","Preview only"}
		elseif method=="quality" then lines={"1 "..info.resource,"Preview only"}
		else method="quality";lines={"Preview only","No currency is spent."} end
		art=icon(method=="socket_bench" and "fusing" or method);c.currencyNote.list=ui.rows(lines,218,14)
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
	if item.type=="Flask" or item.type=="Tincture" then
		for _,key in ipairs({"socketCount","omenJeweller","link","omen","benchLink","white"}) do c[key].shown=false end
		c.status.y=130;c.apply.y=150;c.divine.y=150;c.undo.y=188;c.redo.y=188;c.keep.y=226;c.guide.y=226
		c.loadTarget.y=264;c.recipe.y=264;c.notice.y=302;c.currency.y=330;c.currencyNote.y=332;c.reviewGuide.y=330
	end
	for _,control in pairs(c) do control.layoutAudit="unique-quality" end
	ui.style(c,{apply=true},{item=true});refresh()
	if layout then
		layout.snapshot=snapshotPreview
		layout.mount(w,h,"Unique crafting",c)
	else main:OpenPopup(w,h,"Unique crafting",c,nil,nil,"close") end
	return c
end
return M
