-- cspell:ignore Katakohi
-- Native recipe routing editor with emulator actions and future currency steps.
local sim=require("Modules.CraftingSimulator")
local Panel={}
local function button(controls,key,x,y,w,label,callback)
	controls[key]=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},label,function()
		local ok,message=pcall(callback);if not ok then main:OpenMessagePopup("Crafting recipe",require("Modules.PlanningUI").errorText(message)) end
	end)
end
local function edit(x,y,w,value,prompt,limit)
	return new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},tostring(value or ""),prompt,nil,limit)
end
function Panel.Open(recipe,currentAction,onKeep,model,options)
	options=options or {}
	local draft=copyTable(recipe or {steps={},targets={}})
	local controls={};local selected=1;local baseline
	local ui=require("Modules.PlanningUI")
	controls.info=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,0,14},"Select a step.")
	controls.graph=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,62,828,264},nil,{})
	controls.step=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,350,828,24},{})
	controls.attempts=edit(16,400,180,"1","Attempts per visit",4)
	controls.condition=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{212,400,632,24},{"After a successful action","Until final targets and properties match","Keep custom conditions"})
	controls.success=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,456,404,24},{})
	controls.failure=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{440,456,404,24},{})
	controls.routeLabel=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,436,0,14},"Success route                                                   Failure / exhausted attempts route")
	local function formValues()
		return {attempts=controls.attempts.buf,condition=controls.condition:GetSelValue(),success=controls.success:GetSelValueByKey("val"),failure=controls.failure:GetSelValueByKey("val")}
	end
	local function loadStep()
		local step=draft.steps[selected];if not step then return end
		controls.graph.selectedKey=selected
		for _,row in ipairs(controls.graph.list) do row.selected=row.step==selected end
		local scroll=controls.graph.controls.scrollBar;local _,height=controls.graph:GetSize()
		scroll:SetContentDimension(#draft.steps*92,height-4);scroll:ScrollIntoView((selected-1)*92,92)
		controls.attempts:SetText(tostring(step.maxAttempts or 1))
		controls.condition:SelByValue((step.untilTargets or step.untilRequirements) and "Keep custom conditions" or "After a successful action")
		controls.success:SelByValue(step.onSuccess or 0,"val")
		controls.failure:SelByValue(step.onFailureAction and step.onFailureAction~="route" and step.onFailureAction or step.onFailure or 0,"val")
		baseline=formValues()
	end
	local function refresh()
		local list,routes,lines={ },{{label="Next step",val=0}},{}
		for i,step in ipairs(draft.steps) do
			list[#list+1]={label=i..". "..require("Modules.CraftingWorkbench").actionLabel(step,model),val=i}
			routes[#routes+1]={label="Step "..i,val=i}
			local function route(target) return target>#draft.steps and "Finish" or "Step "..target end
			local unlock=step.method=="bench" and model and require("Modules.CraftingBenchCosts").unlock(model,step.modId)
			lines[#lines+1]={height=92,textSize=16,x=44,card=true,step=i,selected=i==selected,iconPath=require("Modules.CraftingWorkbench").icon(step.method,step,model),
				subtitle=string.format("Success -> %s | Failure -> %s",route(step.onSuccess or i+1),step.onFailureAction and step.onFailureAction~="route" and require("Classes.CraftingRecoveryControl").labels[step.onFailureAction] or route(step.onFailure or i+1)),
				detail=ui.fit((unlock and "Recipe listed in "..unlock.map.." | " or "")..((step.untilTargets or step.untilRequirements) and "Repeat until target conditions match" or "Continue after one successful action"),740,14),
				"^7"..string.format("%d. %s | up to %d attempts",i,require("Modules.CraftingWorkbench").actionLabel(step,model),step.maxAttempts or 1)}
		end
		routes[#routes+1]={label="End recipe",val=#draft.steps+1}
		controls.graph.list=lines;controls.step:SetList(list);controls.step:SelByValue(selected,"val")
		controls.success:SetList(routes)
		local failureRoutes=copyTable(routes);local recovery=require("Classes.CraftingRecoveryControl")
		for _,policy in ipairs({"stop","restart","salvage"}) do failureRoutes[#failureRoutes+1]={label=recovery.labels[policy],val=policy} end
		controls.failure:SetList(failureRoutes);loadStep()
	end
	local function saveSelected()
		if not draft.steps[selected] then return end
		local values=formValues()
		if baseline and values.attempts==baseline.attempts and values.condition==baseline.condition and values.success==baseline.success and values.failure==baseline.failure then return end
		local candidate=copyTable(draft);local step=assert(candidate.steps[selected],"Select a step")
		step.maxAttempts=assert(tonumber(controls.attempts.buf),"Enter an attempt count")
		local condition=controls.condition:GetSelValue()
		if condition == "Until final targets and properties match" then assert(#draft.targets > 0 or draft.requirements,"Choose targets or properties in the emulator first");step.untilTargets=#draft.targets > 0 and copyTable(draft.targets) or nil;step.untilRequiredGroups=step.untilTargets and draft.requiredGroups or nil;step.untilRequirements=draft.requirements and copyTable(draft.requirements) or nil
		elseif condition == "After a successful action" then step.untilTargets=nil;step.untilRequiredGroups=nil;step.untilRequirements=nil end
		local success,failure=controls.success:GetSelValueByKey("val"),controls.failure:GetSelValueByKey("val")
		step.onSuccess=success ~= 0 and success or nil
		if type(failure)=="string" then step.onFailureAction=failure
		else step.onFailureAction="route";step.onFailure=failure ~= 0 and failure or nil end
		local validation=copyTable(candidate)
		if #validation.targets==0 and not validation.requirements then validation.requirements={minQuality=0} end
		sim.validateRecipe(validation);draft=candidate;baseline=values
	end
	local function openBeastSwap(initial,onUse,label)
		local popup={};ui.description(popup,"help",16,28,488,50,{"Enter the red beast's level, or leave blank to use item level.","The beast-level interaction is not verified in the current game."},14)
		popup.level=edit(16,92,180,initial.beastLevel or "","Beast level (optional)",3)
		button(popup,"use",16,132,200,label,function()
			local action=copyTable(initial);action.beastLevel=nil
			if popup.level.buf~="" then local level=assert(tonumber(popup.level.buf),"Enter a beast level from 1 to 100");assert(level==math.floor(level) and level>=1 and level<=100,"Enter a beast level from 1 to 100");action.beastLevel=level end
			onUse(action);main:ClosePopup()
		end)
		button(popup,"cancel",388,132,116,"Cancel",function() main:ClosePopup() end)
		ui.style(popup,{use=true});main:OpenPopup(520,176,"Bestiary swap",popup,nil,"level","cancel")
	end
	local function selectStep(index)
		local ok,message=pcall(saveSelected)
		if not ok then
			controls.step:SelByValue(selected,"val");controls.graph.selectedKey=selected
			for _,row in ipairs(controls.graph.list) do row.selected=row.step==selected end
			main:OpenMessagePopup("Crafting recipe",ui.errorText(message));return
		end
		selected=index;refresh()
	end
	controls.step.selFunc=function(_,entry) selectStep(entry.val) end
	button(controls,"reviewUnlocks",232,24,200,"Review unlocks",function()
		local function show()
			local report=assert(options.reviewUnlocks,"Review is unavailable")(draft.steps,model);local entries={}
			local labels={untracked="Not tracked",tracked="Task tracked",complete="Task complete",unknown="Task status unknown",conflict="Task link changed"}
			for _,entry in ipairs(report.entries) do
				local steps={};for _,index in ipairs(entry.steps) do steps[#steps+1]=tostring(index) end
				local note=entry.taskStatus=="conflict" and "The existing task was relinked. Review it in Roadmap; it will not be replaced." or report.warning or "Only supported bench recipes are listed; later base changes need review."
				entries[#entries+1]={id=entry.modId,label=entry.title,category=labels[entry.taskStatus],entry=entry,details={labels[entry.taskStatus],"Recipe steps: "..table.concat(steps,", "),"Listed location: "..entry.unlock.map,entry.unlock.note,note}}
			end
			for _,entry in ipairs(report.unresolved) do entries[#entries+1]={id="unknown-"..entry.step,label="Step "..entry.step.." | "..entry.modId,category="Review",details={entry.reason,report.note}} end
			if #entries==0 then entries[1]={id="none",label="No listed unlocks",category="Review",details={"No supported bench unlocks were found in this recipe.",report.note}} end
			require("Classes.PlanningBrowserControl").Open("Recipe unlock checklist",entries,{action="Track unlock",closeOnChoose=false,
				canChoose=function(row) return options.trackUnlock and row.entry and row.entry.taskStatus=="untracked" end,
				choose=function(row)
					local ok,why=pcall(options.trackUnlock,{method="bench",modId=row.entry.modId},model)
					if not ok then main:OpenMessagePopup("Recipe unlock",ui.errorText(why));return end
					main:ClosePopup();show()
				end})
		end
		show()
	end)
	controls.reviewUnlocks.shown=function() return options.reviewUnlocks~=nil end
	controls.reviewUnlocks.tooltipText="Review listed recipe unlocks and Roadmap status without checking your account."
	button(controls,"trackUnlock",448,24,200,"Track unlock",function()
		local step=assert(draft.steps[selected],"Select a bench recipe step")
		local result=assert(options.trackUnlock,"Tracking is unavailable")(step,model)
		main:OpenMessagePopup("Recipe unlock",result.created and "Added to Roadmap. Keep this recipe separately and save the build to persist both." or result.conflict and "The existing task was relinked. Review it in Roadmap; nothing was changed." or "This unlock is already in Roadmap. Its existing notes and completion are unchanged.")
	end)
	controls.trackUnlock.shown=function() return options.trackUnlock~=nil end
	controls.trackUnlock.enabled=function() local step=draft.steps[selected];return step and step.method=="bench" and model and require("Modules.CraftingBenchCosts").unlock(model,step.modId)~=nil end
	controls.trackUnlock.tooltipText="Add this listed recipe unlock to Roadmap. Keep the project first; this does not check your account or keep the recipe."
	button(controls,"flowGraph",664,24,180,"Flow graph",function()
		saveSelected()
		require("Classes.CraftingRecipeGraphControl").Open(draft,{model=model,change=function(next) draft=next;refresh() end,edit=function(index) selected=index;refresh();main:ClosePopup();main.popups[1]:SelectControl(controls.attempts) end})
	end)
	ui.selectable(controls.graph,function(row) return row.step end,function(row) selectStep(row.step) end)
	button(controls,"add",16,514,256,"Append current emulator action",function()
		saveSelected()
		assert(#draft.steps < 20,"Use up to twenty steps")
		draft=require("Modules.CraftingRoutes").append(draft,currentAction);selected=#draft.steps;refresh()
	end)
	button(controls,"replace",288,514,272,"Replace selected with emulator action",function()
		saveSelected()
		local old=assert(draft.steps[selected],"Select a step");local next=copyTable(currentAction)
		for _,key in ipairs({"maxAttempts","onSuccess","onFailure","onFailureAction","recoveryNotes","untilTargets","untilRequiredGroups","untilRequirements"}) do
			local value=old[key];if value~=nil then next[key]=type(value)=="table" and copyTable(value) or value end
		end
		draft.steps[selected]=next;refresh()
	end)
	button(controls,"delete",576,514,268,"Delete selected step",function()
		assert(draft.steps[selected],"Select a step");table.remove(draft.steps,selected)
		for _,step in ipairs(draft.steps) do for _,key in ipairs({"onSuccess","onFailure"}) do if step[key] and step[key] > selected then step[key]=step[key]-1 end end end
		selected=math.min(selected,math.max(1,#draft.steps));refresh()
	end)

	button(controls,"update",16,558,256,"Update selected routes",function() saveSelected();refresh() end)
	controls.note=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{16,604,0,14},"Loops stop at the simulation action budget. Keeping a recipe does not craft or equip an item.")
	button(controls,"recovery",288,558,272,"Failure recovery",function()
		saveSelected()
		local step=assert(draft.steps[selected],"Select a recipe step")
		require("Classes.CraftingRecoveryControl").Open(step,function(replacement) draft.steps[selected]=replacement;sim.validateRecipe(draft);refresh() end)
	end)
	button(controls,"keep",16,642,256,"Keep recipe",function() saveSelected();onKeep(sim.validateRecipe(draft));main:ClosePopup() end)
	button(controls,"addCurrency",288,642,272,"Add recipe step",function()
		saveSelected()
		assert(#draft.steps < 20,"Use up to twenty steps")
		local entries={};local workbench=require("Modules.CraftingWorkbench")
		for _,method in ipairs({"transmute","alteration","augmentation","regal","alchemy","binding","chaos","exalt","annul","scour","divine","vaal","blessed","sacred","chromatic","jeweller","fusing","tainted_chromatic","tainted_jeweller","tainted_fusing","quality"}) do
			local details={"Add this action to the recipe without changing the working item.","The item must meet its requirements when this step runs."}
			if method=="binding" then details[#details+1]="No longer generated in 3.30; existing Orbs of Binding still work." end
			if method=="jeweller" or method=="fusing" then details[#details+1]="Experimental probabilities; current game odds and some socket behavior are unverified." end
			if method:find("tainted_",1,true) then details[#details+1]="Requires a corrupted item. Outcome probabilities and edge cases are unverified." end
			for _,warning in ipairs(sim.actionWarnings({method=method},model)) do details[#details+1]=warning.message end
			entries[#entries+1]={id=method,label=sim.labels[method],category="Currency",icon=workbench.icon(method),action={method=method},
				details=details}
		end
		for _,method in ipairs({"fracture","dominance","veiled_orb","veiled_chaos","eldritch_exalt","eldritch_annul","eldritch_chaos","tainted_exalt","tainted_chaos","remembrance","unravelling","foulborn_augmentation","foulborn_regal","foulborn_exalt"}) do
			local action={method=method};local details={"Add this action to the recipe without changing the working item.","The item must meet its requirements when this step runs."}
			for _,warning in ipairs(sim.actionWarnings(action,model)) do details[#details+1]=warning.message end
			entries[#entries+1]={id=method,label=sim.labels[method],category="Currency",icon=workbench.icon(method),action=action,details=details}
		end
		for _,entry in ipairs({
			{method="omen_jeweller",note="Consumes an Omen of the Jeweller and a Jeweller's Orb to maximize sockets."},
			{method="omen_connections",note="Consumes an Omen of Connections and an Orb of Fusing to link existing sockets."},
			{method="omen_trichromatism",note="Consumes an Omen of Trichromatism and a Chromatic Orb to guarantee red, green and blue sockets. Extra-colour probabilities are estimated."},
		}) do
			entries[#entries+1]={id=entry.method,label=sim.labels[entry.method],category="Socket Omens",icon=workbench.icon(entry.method),action={method=entry.method},details={entry.note,"The item must meet its requirements when this step runs."}}
		end
		for _,count in ipairs({1,3}) do entries[#entries+1]={id="bench-reroll-"..count,label="Bench: reroll "..count.." modifier"..(count==1 and "" or "s"),category="Bench",icon=workbench.icon("bench_reroll"),action={method="bench_reroll",count=count},
			details={"Add this bench action to the recipe without changing the working item.","The item must have enough removable modifiers when this step runs."}} end
		entries[#entries+1]={id="bench_remove_enchant",label=sim.labels.bench_remove_enchant,category="Bench",icon=workbench.icon("bench_remove_enchant"),action={method="bench_remove_enchant"},
			details={"Remove the item's enchantments for three Orbs of Scouring.","The item must have an enchantment when this step runs."}}
		entries[#entries+1]={id="ducat_katakohi",label=sim.labels.ducat_katakohi,category="Ducats",icon=workbench.icon("ducat_katakohi"),action={method="ducat_katakohi"},
			details={"Historical Allflame craft for gloves; consumes a Ducat and Sulphur.","Socket selection and modifier probabilities are experimental assumptions."}}
		entries[#entries+1]={id="vorici_socket_count",label=sim.labels.vorici_socket_count,category="Betrayal",action={method="vorici_socket_count"},details={"Vorici rerolls socket counts 100 times and keeps the greatest result.","Experimental Jeweller odds and socket retention; enter a whole-service price."}}
		entries[#entries+1]={id="vorici_socket_colours",label=sim.labels.vorici_socket_colours,category="Betrayal",action={method="vorici_socket_colours"},details={"Vorici rerolls socket colours 25 times and keeps an outcome with the most non-white sockets.","Estimated colour odds and first-on-tie selection; enter a whole-service price."}}
		entries[#entries+1]={id="rog-observed",label="Rog: observed offer",category="Expedition",icon=workbench.icon("rog_reroll"),configure="rog",details={"Record a Rog offer and its observed artifact cost.","Modifier weights and offer interactions are experimental."}}
		entries[#entries+1]={id="beast_max_links",label=sim.labels.beast_max_links,category="Bestiary",icon=workbench.icon("beast_max_links"),action={method="beast_max_links"},details={"Link the item's existing sockets using the Black Morrigan and a Craicic Sand Spitter.","Add sockets first; this step does not increase their number."}}
		for _,method in ipairs({"beast_imprint","restore_imprint"}) do
			local details={sim.labels[method],method=="beast_imprint" and "Create an imprint of an eligible magic item. Enter a whole-service price if needed." or "Restore the captured imprint when one exists; this step consumes the imprint."}
			entries[#entries+1]={id=method,label=sim.labels[method],category="Bestiary",icon=workbench.icon(method),action={method=method},details=details}
		end
		for _,count in ipairs({1,2}) do local action={method="beast_talisman_fracture",count=count}
			entries[#entries+1]={id="talisman-fracture-"..count,label=workbench.actionLabel(action,model),category="Bestiary",icon=workbench.icon(action.method),action=action,details={"Fracture "..count.." modifier"..(count==1 and "" or "s").." on an eligible rare Talisman.",count==1 and "Requires at least four modifiers." or "Requires six modifiers.","Enter a whole-service price if needed."}}
		end
		for _,method in ipairs({"beast_prefix_suffix","beast_suffix_prefix"}) do
			entries[#entries+1]={id=method,label=sim.labels[method],category="Bestiary",icon=workbench.icon(method),configure="beast_swap",action={method=method},details={"Choose the red beast's level, or use the item level if unknown.","Beast-level behavior is based on community research and is not verified in the current game."}}
		end
		entries[#entries+1]={id="beast_talisman_imprint",label=sim.labels.beast_talisman_imprint,category="Bestiary",icon=workbench.icon("beast_talisman_imprint"),action={method="beast_talisman_imprint"},details={"Create an imprint of an uncorrupted, non-fractured rare Talisman.","Enter a whole-action price for the Bestiary service."}}
		if model then
			for _,choice in ipairs(sim.actionOptions(model,model.initial,"beast_flask")) do
				entries[#entries+1]={id="beast-flask-"..choice.action.modId,label=workbench.actionLabel(choice.action,model),category="Bestiary",icon=workbench.icon("beast_flask"),action=choice.action,details={choice.label,"Uses one red beast. Enter a whole-service price.","Eligibility and roll distributions require current-game verification."}}
			end
			entries[#entries+1]={id="fossil-combination",label="Fossil combination",category="Fossils",configure="fossil",details={"Choose up to four fossils for this recipe step.","The item must meet the fossil requirements when this step runs."}}
			for _,entry in ipairs(model.bench or {}) do
				local action={method="bench",modId=entry.id};local label=workbench.actionLabel(action,model)
				entries[#entries+1]={id=entry.id,label=label,search=entry.id,category="Bench",action=action,details={label,"Uses a bench-crafted slot. Item requirements and conflicts are checked when this step runs."}}
			end
			for _,entry in ipairs(model.essences or {}) do
				local action={method="essence",essenceId=entry.id}
				local mod=model.descriptions330[entry.modId] or model.byId[entry.modId];local guaranteed=mod and table.concat(mod," / ") or "Unavailable"
				local details={entry.name,"Guaranteed on this base: "..guaranteed}
				if entry.maxModLevel then details[#details+1]="Other random modifiers are restricted to level "..entry.maxModLevel.." or below." end
				details[#details+1]="Crafting data: "..sim.dataPatch..". The item must meet the Essence's requirements when this step runs."
				entries[#entries+1]={id=entry.id,label=entry.name,search=entry.id,category="Essences",icon=workbench.icon("essence",action,model),action=action,
					details=details}
			end
		end
		local reforgeOnly={influence=true,minion=true,elemental=true,attribute=true,mana=true,drop=true}
		for _,method in ipairs({"harvest_reforge","harvest_augment"}) do for _,tag in ipairs({"attack","caster","physical","fire","cold","lightning","chaos","life","defences","speed","critical","influence","minion","elemental","attribute","mana","drop"}) do
			if method~="harvest_augment" or not reforgeOnly[tag] then local action={method=method,tag=tag};local label=workbench.actionLabel(action,model)
				local details={label,"A legal modifier and item state are required when this step runs."};local costs=sim.components(action,nil,model);local keys={};local icon
				for key in pairs(costs) do keys[#keys+1]=key end;table.sort(keys)
				for _,key in ipairs(keys) do local resource=workbench.resourceInfo(key,model);details[#details+1]="Cost: "..costs[key].." "..(resource and resource.name or key);if key:find("lifeforce",1,true) and key~="sacred_lifeforce" then icon=resource and resource.path end end
				entries[#entries+1]={id=method..":"..tag,label=label,category="Harvest",icon=icon,action=action,details=details}
			end
		end end
		for _,method in ipairs({"harvest_damage","harvest_resistance"}) do for _,from in ipairs({"fire","cold","lightning"}) do for _,to in ipairs({"fire","cold","lightning"}) do if from~=to then
			local action={method=method,from=from,to=to};local label=workbench.actionLabel(action,model)
			local details={label,"A compatible modifier and item state are required when this step runs."};local costs=sim.components(action,nil,model);local keys={};local icon
			for _,warning in ipairs(sim.actionWarnings(action,model)) do details[#details+1]=warning.message end
			for key in pairs(costs) do keys[#keys+1]=key end;table.sort(keys)
			for _,key in ipairs(keys) do local resource=workbench.resourceInfo(key,model);details[#details+1]="Cost: "..costs[key].." "..(resource and resource.name or key);if not icon and key:find("lifeforce",1,true) then icon=resource and resource.path end end
			entries[#entries+1]={id=method..":"..from..":"..to,label=label,category="Harvest",icon=icon,action=action,details=details}
		end end end end
		require("Classes.PlanningBrowserControl").Open("Add a recipe step",entries,{action="Add step",closeOnChoose=false,choose=function(entry)
			main:ClosePopup()
			local function append(action) draft=require("Modules.CraftingRoutes").append(draft,action);selected=#draft.steps;refresh() end
			if entry.configure=="fossil" then require("Classes.CraftingFossilControl").Open(model,nil,append)
			elseif entry.configure=="beast_swap" then openBeastSwap(entry.action,append,"Add step")
			elseif entry.configure=="rog" then require("Classes.CraftingRogControl").Open(nil,append)
			else append(entry.action) end
		end})
	end)
	button(controls,"editFossils",576,642,136,"Edit fossils",function()
		saveSelected()
		local index=selected;local step=assert(draft.steps[index],"Select a fossil step")
		assert(model and step.method=="fossil","Select a fossil step")
		require("Classes.CraftingFossilControl").Open(model,step,function(action)
			local next=copyTable(step);next.fossils=copyTable(action.fossils);next.tangledOutcome=action.tangledOutcome
			draft.steps[index]=next;refresh()
		end)
	end)
	controls.editFossils.enabled=function() return model~=nil and draft.steps[selected]~=nil and draft.steps[selected].method=="fossil" end
	local function selectedBeast() local step=draft.steps[selected];return step and (step.method=="beast_prefix_suffix" or step.method=="beast_suffix_prefix") end
	local function selectedRog() local step=draft.steps[selected];return step and step.method=="rog_reroll" end
	controls.editFossils.shown=function() return not selectedBeast() and not selectedRog() end
	button(controls,"editBeast",576,642,136,"Edit beast level",function()
		saveSelected()
		local index=selected;local step=assert(draft.steps[index],"Select a Bestiary swap")
		openBeastSwap(step,function(action) draft.steps[index]=action;refresh() end,"Update step")
	end)
	controls.editBeast.shown=selectedBeast
	button(controls,"editRog",576,642,136,"Edit Rog offer",function()
		saveSelected()
		local index=selected;local step=assert(draft.steps[index],"Select a Rog step")
		assert(step.method=="rog_reroll","Select a Rog step")
		require("Classes.CraftingRogControl").Open(step,function(action)
			local next=copyTable(step)
			for _,key in ipairs({"rogOperation","rogSide","rogAttempts","artifactCost","count"}) do next[key]=type(action[key])=="table" and copyTable(action[key]) or action[key] end
			draft.steps[index]=next;refresh()
		end)
	end)
	controls.editRog.shown=selectedRog

	button(controls,"close",728,642,116,"Close",function() main:ClosePopup() end)
	local height=math.max(520,math.min(690,main.screenH-60));local offset=690-height
	controls.graph.height=264-offset
	for key,control in pairs(controls) do if key ~= "graph" and control.y >= 350 then control.y=control.y-offset end end
	refresh();ui.style(controls,{keep=true});for _,control in pairs(controls) do control.layoutAudit="recipe-editor" end;main:OpenPopup(860,height,"Crafting recipe routes",controls,nil,nil,"close")
	return controls
end
return Panel
