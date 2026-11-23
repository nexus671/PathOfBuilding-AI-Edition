-- Native item emulator and bounded recipe trials, isolated from equipped items.
local simulator=require("Modules.CraftingSimulator")
local workbench=require("Modules.CraftingWorkbench")
local pricing=require("Modules.CraftingPrices")
local ui=require("Modules.PlanningUI")
local inspect=require("Modules.CraftingInspection")
local browser=require("Classes.PlanningBrowserControl")
local tasks=require("Modules.CraftingTasks")
local Panel={ }
local pageHints={["Target conditions"]="Choose the modifiers and item properties you want.",["Simulate recipe"]="Compare modeled chances and costs before keeping a recipe.",["Craft settings"]="Advanced methods, item edits and recipe settings."}
local function button(controls,key,x,y,w,label,callback)
	controls[key]=new("ButtonControl"):ButtonControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,24},label,function()
		local ok,err=pcall(callback)
		if not ok then require("Modules.PlanningUI").errorPopup("Native crafting",err) else return err end
	end)
	ui.styleButton(controls[key])
end
local function edit(controls,key,x,y,w,h,value,prompt,limit)
	controls[key]=new("EditControl"):EditControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,w,h},value or "",prompt,h>24 and "^%C\t\n" or nil,limit,nil,h > 24 and 16 or nil)
end
local function rows(lines,width)
	width=width or 388
	local result={ }
	for _,line in ipairs(lines) do
		for part in tostring(line):gmatch("[^\r\n]+") do
			part=StripEscapes(part)
			while DrawStringWidth(18,"VAR",part) > width do
				local low,high=1,#part
				while low < high do local middle=math.ceil((low+high)/2);if DrawStringWidth(18,"VAR",part:sub(1,middle)) <= width then low=middle else high=middle-1 end end
				local space=part:sub(1,low):match("^.*()%s")
				local cut=space and space > 1 and space-1 or low
				result[#result+1]={height=18,colorCodes.NORMAL..part:sub(1,cut)};part=part:sub(cut+1):gsub("^%s+","")
			end
			result[#result+1]={height=18,colorCodes.NORMAL..part}
		end
	end
	return result
end
local function label(controls,key,x,y,text)
	controls[key]=new("LabelControl"):LabelControl({"TOPLEFT",nil,"TOPLEFT"},{x,y,0,14},colorCodes.NORMAL..text)
end

function Panel.Open(build,project,layout)
	local draft=copyTable(project)
	local model=simulator.model(draft.startingItem)
	local state=draft.nativeRecipe and draft.nativeRecipe.initialState and simulator.validateState(model,draft.nativeRecipe.initialState) or copyTable(model.initial)
	local initial=copyTable(state)
	local targets=draft.nativeRecipe and copyTable(draft.nativeRecipe.targets) or { }
	local requirements=draft.nativeRecipe and draft.nativeRecipe.requirements and copyTable(draft.nativeRecipe.requirements)
	local requiredGroups=draft.nativeRecipe and draft.nativeRecipe.requiredGroups
	local controls,history,actions={},{},{}
	local itemWarnings={}
	local ready=false
	local function changed()
		if ready then ui.draft(build,"workingCraft",draft.id) end
	end
	local configured={}
	local sequence=0
	local lastSimulation,lastSimulationRun,lastFossilComparison
	local changedAffixes={}
	local favorites=layout and (layout.favorites or layout.workbench and layout.workbench.favorites) or {}
	if layout then layout.favorites=favorites end
	if layout then layout.selectedProject=draft.id end
	local restored=layout and layout.workbench or draft.run and require("Modules.CraftingCheckpoint").validate(draft.startingItem,draft.run)
	local savedSimulationRun=restored and not restored.simulationRequestWarning and restored.simulationRequest or nil
	local invalidSimulationRun=restored and restored.simulationRequestWarning and restored.simulationRequest or nil
	if layout then layout.workbench=nil end
	if restored then
		state=restored.state;initial=restored.initial;targets=restored.targets;requirements=restored.requirements;requiredGroups=restored.requiredGroups
		history=restored.history;actions=restored.actions;configured=restored.configured;sequence=restored.sequence;lastSimulation=restored.lastSimulation;lastSimulationRun=restored.lastSimulationRun;lastFossilComparison=restored.lastFossilComparison
	end
	local analysis=require("Modules.CraftingAnalysis").get(build,draft,restored)
	local function syncAnalysis()
		local result=analysis.results.simulation
		lastSimulation=result and result.result;lastSimulationRun=result and result.context
		lastFossilComparison=analysis.results.fossils and analysis.results.fossils.result
	end
	syncAnalysis()
	local paletteOpen=restored and restored.paletteOpen or false
	local inspectedId=restored and restored.inspectedId
	local paletteView
	local populateAffix
	local refreshTargetOptions
	local action,overrideKey,updateCurrency,actionConfigurationReason,gwennenApplyReason
	local function actionName()
		local selected=action()
		return (selected.allflame and "Allflame " or "")..workbench.actionLabel(selected,model)
	end
	local priceOverrides=copyTable(restored and restored.priceOverrides or {})
	local width=layout and layout.width or math.min(1120,main.screenW-40)
	local height=layout and layout.height or math.max(520,math.min(740,main.screenH-60))
	local leftWidth=math.max(416,math.min(width-400,layout and layout.craftWidth or restored and restored.craftWidth or 416))
	local itemWidth=math.min(540,width-leftWidth-64)
	local itemX=leftWidth+32+math.floor((width-leftWidth-48-itemWidth)/2)
	label(controls,"intro",16,64,"Select a currency, then click your item to craft.")
	local refreshItem=workbench.item(controls,"item",itemX,112,itemWidth,height-184,model,function() return state end,function() controls.apply:Click() end,{header=196,artSize=96,compact=true,slot=draft.slot,selectedAffix=function() return inspectedId end,changedAffixes=function() return changedAffixes end})
	controls.targetSummary=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,244,416,height-312},nil,{})
	local targetReason,savedResultRows,warningActive,oddsContext
	local function refresh(extra,capturedOdds)
		if refreshTargetOptions then refreshTargetOptions() end
		if action and controls.price then
			local key=simulator.priceKey(action())
			if overrideKey and overrideKey~=key then priceOverrides[overrideKey]=controls.price.buf;controls.price:SetText(priceOverrides[key] or "") end
			overrideKey=key
		end
		if inspectedId then local exists;for _,entry in ipairs(state.affixes) do if entry.id==inspectedId then exists=true end end;if not exists then inspectedId=nil end end
		refreshItem()
		local lines={inspect.slots(model,state),"Target groups: "..#targets.." ("..(requiredGroups or "all").." required)"}
		for index,group in ipairs(targets) do
			local names={}
			for _,id in ipairs(group.anyOf) do local mod=simulator.context(model,state).byId[id] or model.byId[id];names[#names+1]=mod and table.concat(mod," / ") or "Unknown modifier" end
			lines[#lines+1]=index..". "..(group.negate and "Exclude " or "Require ")..(group.atLeast or 1)..": "..table.concat(names," OR ")
			if group.fractured ~= nil then lines[#lines+1]=group.fractured and "Fractured only" or "Not fractured" end
			if group.crafted ~= nil then lines[#lines+1]=group.crafted and "Crafted only" or "Not crafted" end
			if group.minRoll then lines[#lines+1]="Minimum roll: "..(group.minRoll*100).."%" end
			if group.minBaseValue~=nil then lines[#lines+1]="Minimum base roll: "..group.minBaseValue end
			if group.maxBaseValue~=nil then lines[#lines+1]="Maximum base roll: "..group.maxBaseValue end
		end
		for key,value in pairsSortByKey(requirements or {}) do
			if key=="nativeStats" then
				for _,field in ipairs(require("Modules.CraftingItemStats").fields) do if value[field[1]] then lines[#lines+1]="Minimum "..field[2]..": "..value[field[1]] end end
			elseif key=="mirrored" then lines[#lines+1]=value and "Must be mirrored" or "Must not be mirrored"
			elseif key=="twiceCorrupted" then lines[#lines+1]=value and "Must be twice corrupted" or "Must not be twice corrupted"
			elseif key=="foreseeing" then lines[#lines+1]=value and "Must be foreseeing" or "Must not be foreseeing"
			elseif key=="influence" then for _,info in ipairs(itemLib.influenceInfo.default) do if info.key==value then lines[#lines+1]="Influence: "..info.display;break end end
			elseif key=="catalyst" then lines[#lines+1]="Catalyst: "..(require("Modules.CraftingUniqueQuality").catalysts[value] or "Unknown")
			elseif key=="minCatalystQuality" then lines[#lines+1]="Minimum catalyst quality: "..value.."%"
			elseif key=="minAbyssSockets" then lines[#lines+1]="Minimum Abyss sockets: "..value
			elseif key=="flaskEnchant" then lines[#lines+1]="Flask enchantment: "..require("Modules.CraftingFlaskEnchants").label(value)
			elseif key=="flaskEnchantMin" then lines[#lines+1]="Minimum enchantment roll: "..value
			else lines[#lines+1]=key:gsub("(%l)(%u)","%1 %2")..": "..tostring(value) end
		end
		controls.targetSummary.list=rows(lines)
		local workingWarning=targetReason and targetReason()
		local savedWarning=targetReason and draft.nativeRecipe and targetReason(true)
		if controls.resultSummary then
			if extra then savedResultRows=rows(extra);oddsContext=capturedOdds
			elseif not warningActive then savedResultRows=controls.resultSummary.list end
			local notices={}
			if workingWarning then notices[#notices+1]="Working item: "..workingWarning end
			if savedWarning and not workingWarning then notices[#notices+1]="Saved recipe: "..savedWarning end
			if oddsContext and action and not tableDeepEquals(oddsContext,{state=state,craft=action(),targets=targets,requirements=requirements,requiredGroups=requiredGroups}) then
				notices[#notices+1]="Action odds use an earlier item, action or target setup. Recalculate for the current setup."
			end
			local wasWarning=warningActive;warningActive=#notices>0
			if warningActive then
				local combined=rows(notices,leftWidth-28);for _,row in ipairs(savedResultRows or {}) do combined[#combined+1]=row end
				controls.resultSummary.list=combined
				if not wasWarning then controls.resultSummary.controls.scrollBar.offset=0 end
			else controls.resultSummary.list=savedResultRows or controls.resultSummary.list end
		end
		local craftingPage=not controls.page or controls.page:GetSelValue()=="Emulate item"
		local message=craftingPage and inspectedId and "Modifier details. Your working item stays in view." or craftingPage and paletteOpen and "Find an action without leaving your working item." or extra and extra[1] or controls.page and pageHints[controls.page:GetSelValue()] or "Select a currency, then click your item to craft."
		if craftingPage and state.uniqueTitle and not (extra and extra[1]) then message="Unique outcome. Undo or keep this item." end
		if controls.page and controls.page:GetSelValue()=="Simulate recipe" then message="Selected action: "..actionName() end
		if workingWarning or savedWarning then message=controls.page and controls.page:GetSelValue()=="Simulate recipe" and "Implicit target unavailable; details below." or "Implicit target unavailable; see Simulate tab." end
		controls.intro.label="^7"..ui.fit(message,leftWidth,14)
		if controls.actionHint and controls.actionHint.list then
			local method=controls.method:GetSelValueByKey("val")
			local available,unavailableReason=workbench.available(method,state,model)
			local hint=workbench.hint(method,state,model,action and action())
			local configuration=actionConfigurationReason and actionConfigurationReason()
			local blocker=not available and unavailableReason or configuration or (gwennenApplyReason and gwennenApplyReason())
			hint=blocker or hint
			local selected=controls.option and controls.option:GetSelValue()
			local id=selected and selected.action and selected.action.modId
			if not blocker and selected and selected.action and selected.action.essenceId then
				for _,essence in ipairs(model.essences) do if essence.id==selected.action.essenceId and essence.maxModLevel then
					hint="Other random modifiers are restricted to level "..essence.maxModLevel.." or below."
				end end
			end
			if not blocker and selected and selected.action and selected.action.essenceId=="Metadata/Items/Currency/CurrencyEssenceUber1" then
				hint="Delirium Fog effects are not modeled in build calculations."
			end
			if not blocker and (id and id:match("^bench:partial%-") or simulator.hasPartialLock(simulator.context(model,state),state) and available) then
				local method=controls.method:GetSelValueByKey("val")
				hint=(method=="harvest_reforge" or method=="harvest_augment" or method=="harvest_resistance" or method=="harvest_damage") and "Experimental lock: some protection selections may leave no legal Harvest outcome."
					or method=="bench_reroll" and "Experimental lock: protection is selected once; some selections may leave too few removable modifiers."
					or "Experimental partial lock: random protection is modeled with assumed equal weights."
			end
			local warnings={};itemWarnings={};local warningAction=selected and selected.action or action and action()
			local warningLabels={abyss_socket_layout="Abyss sockets",tincture_imported_values="Tincture scaling",magic_affix_name="Magic item name",affix_roll_outside_current_tier="Outside-tier roll"}
			local warningBrief={abyss_socket_layout="Abyss socket placement and removal are unverified.",tincture_imported_values="Copied tincture values: verify tiers and effects.",magic_affix_name="Imported tier uses item name; verify the original name.",affix_roll_outside_current_tier="A roll is outside its current tier; verify its origin."}
			if warningAction then for _,warning in ipairs(simulator.actionWarnings(warningAction,{item=model.item,initial=state})) do
				if warningLabels[warning.code] then
					warnings[#warnings+1]=warningBrief[warning.code]
					itemWarnings[#itemWarnings+1]={label=warningLabels[warning.code],details={warning.message}}
				end
			end end
			local unlock=id and require("Modules.CraftingBenchCosts").unlock(simulator.context(model,state),id)
			local lines={}
			if unlock and #warnings==0 then
				lines[#lines+1]="Recipe listed in "..unlock.map.."; check your unlocks."
				local brief=hint
				if hint=="Experimental partial lock: random protection is modeled with assumed equal weights." then brief="Experimental partial lock: equal odds assumed." end
				lines[#lines+1]=ui.fit(brief,leftWidth-38,14)
				controls.option.tooltipText=hint.." Recipe location is listed by PoEDB; account unlocks and Ruthless availability are not checked."
			else
				lines[1]=#warnings>0 and ui.fit(hint,leftWidth-30,14) or hint
				controls.option.tooltipText=unlock and hint.." Recipe location is listed by PoEDB; account unlocks and Ruthless availability are not checked." or nil
			end
			if #warnings>1 then lines[#lines+1]=#warnings.." item warnings; select Review warnings."
			elseif #warnings==1 then lines[#lines+1]=warnings[1] end
			controls.actionHint.list=ui.rows(lines,leftWidth-30,14)
		end
	end
	label(controls,"methodLabel",16,64,"Crafting action")
	local methods={ }
	for _,method in ipairs(simulator.methods) do methods[#methods+1]={label=simulator.labels[method],val=method} end
	controls.method=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,84,416,24},methods)
	label(controls,"optionLabel",16,124,"Action options (dropdown search is available)")
	controls.option=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,144,416,24},{})
	local stateAwareOptions={bench=true,essence=true,harvest_reforge=true,harvest_augment=true,harvest_resistance=true,harvest_damage=true}
	local function updateOptions(preferUnveil)
		if state.veil and preferUnveil then controls.method:SelByValue("unveil","val") end
		local method=controls.method:GetSelValueByKey("val")
		local previous=controls.option:GetSelValue()
		local reference=stateAwareOptions[method] and configured[method] or previous and previous.action
		local choices=simulator.actionOptions(model,state,method);local selected=1;local found=false
		if method=="fossil" and configured.fossil and type(configured.fossil.fossils)=="table" and #configured.fossil.fossils>0 then
			local names={};for _,id in ipairs(configured.fossil.fossils) do
				local name=id;for _,fossil in ipairs(model.fossils) do if fossil.id==id then name=fossil.name;break end end;names[#names+1]=name
			end
			table.insert(choices,1,{label="Configured: "..table.concat(names," + "),action=copyTable(configured.fossil),configuredFossils=true})
			reference=configured.fossil
		end
		for i,choice in ipairs(choices) do if tableDeepEquals(choice.action,reference) then selected=i;found=true;break end end
		controls.option:SetList(choices)
		if #choices>0 then controls.option:SetSel(selected,true) else controls.option.selIndex=1 end
		if #choices>0 and stateAwareOptions[method] and (not configured[method] or not found) then
			local old=configured[method];configured[method]=copyTable(choices[selected].action)
			if old and old.allflame and old.allflame.auto then configured[method].allflame=copyTable(old.allflame) end
		end
	end
	controls.method.selFunc=function() updateOptions();changed();refresh() end
	controls.option.enabled=function() return #controls.option.list > 0 end
	controls.option.selFunc=function()
		local method=controls.method:GetSelValueByKey("val");local previous=configured[method]
		local selected=controls.option:GetSelValue()
		configured[method]=(stateAwareOptions[method] or method=="fossil" and selected and selected.configuredFossils) and selected and copyTable(selected.action) or nil
		if previous and previous.allflame and previous.allflame.auto and selected then
			configured[method]=copyTable(selected.action);configured[method].allflame=copyTable(previous.allflame)
		end
		changed()
		refresh()
	end
	label(controls,"seedLabel",16,184,"Seed")
	edit(controls,"seed",16,204,130,24,"104729","Seed",12)
	action=function()
		local method=controls.method:GetSelValueByKey("val")
		local option=controls.option:GetSelValue()
		return copyTable(configured[method] or option and option.action or {method=method})
	end
	local function chooseMethod(method)
		paletteOpen=false;inspectedId=nil;controls.method:SelByValue(method,"val");updateOptions();changed();refresh()
	end
	local function palette()
		paletteOpen=true;inspectedId=nil;paletteView.refresh();refresh()
		return controls.paletteSearch
	end
	local function pickTarget(id)
		assert(#targets<6,"Use up to six target groups")
		local mod=simulator.context(model,state).byId[id];targets[#targets+1]={anyOf={id},scope=require("Modules.CraftingModifiers").scope(mod)};changed();refresh()
	end
	populateAffix=function(id)
		local found;for _,entry in ipairs(state.affixes) do if entry.id==id then found=entry end end
		if not found then return end
		controls.affixFacts.list=ui.rows(inspect.modDetails(simulator.context(model,state),id,found),leftWidth-30)
		controls.affixFacts.controls.scrollBar.offset=0
		local entries={}
		for _,method in ipairs(found.crafted and {"remove_crafted","divine"} or found.fractured and {"divine","bench"} or {"divine","annul","bench"}) do
			entries[#entries+1]={val=method,label=simulator.labels[method]}
		end
		controls.affixAction:SetList(entries)
	end
	controls.itemMods.onClick=function(row)
		local id=row and row.line.affixId;if not id then return end
		inspectedId=id;paletteOpen=false;controls.page:SelByValue("Emulate item");populateAffix(id);refresh()
	end

	button(controls,"apply",162,204,130,"Apply currency",function()
		local craft=action();local seed=tonumber(controls.seed.buf)
		assert(seed and seed==math.floor(seed) and seed>=1 and seed<=2147483646,"Seed must be an integer from 1 to 2147483646")
		local usedSeed=(seed-1+sequence)%2147483646+1
		local result=simulator.perform(draft.startingItem,craft,usedSeed,state,build.spec.treeVersion)
		local function keep(nextState,index)
			sequence=sequence+1
			changedAffixes={};local previous={};for _,entry in ipairs(state.affixes) do previous[entry.id]=require("dkjson").encode(entry) end
			for _,entry in ipairs(nextState.affixes) do if previous[entry.id]~=require("dkjson").encode(entry) then changedAffixes[entry.id]=true end end
			ui.draft(build,"workingCraft",draft.id)
			history[#history+1]=copyTable(state);if #history > 40 then table.remove(history,1) end
			if index then craft.allflame=craft.allflame or copyTable(result.allflame.settings);craft.allflame.choiceIndex=index end
			local label=craft.method=="essence" and "Essence: "..workbench.actionLabel(craft,model) or simulator.labels[craft.method] or "craft"
			state=nextState;actions[#actions+1]=craft;updateOptions(craft.method=="veiled_chaos" or craft.method=="veiled_orb")
			local message=state.uniqueTitle and ("Applied "..label..". Unique outcome; undo or keep this item.") or ("Applied "..label..". Select another currency or undo.")
			if craft.method=="mirror" then message="Mirrored copy. Original is in Item history." end
			for _,warning in ipairs(result.warnings or {}) do if warning.code=="abyss_socket_layout" then message="Applied "..label..". Abyss socket layout is experimental.";break end end
			if result.gwennen then for _,entry in ipairs(require("Modules.CraftingGwennenReference").search("",100).offers) do if entry.id==result.gwennen.outcome then message="Gwennen modeled outcome: "..entry.description;break end end end
			if state.socketLayoutUnknown then message="Socket layout is unknown after corruption. Set it in Edit hypothetical item before socket crafts or build preview." end
			refresh({message})
		end
		if state.foreseeing and not (result.choices and #result.choices>1) then
			local currency=require("Modules.CraftingGwennen").isForesightCurrency(craft.method)
			local note=currency and "Hypothetical sample only: this does not predict the game's actual future." or "This modeled action consumes foreseeing. This is not a game Lock preview."
			local popup={};ui.description(popup,"note",16,24,628,32,{note},14)
			local update=workbench.item(popup,"preview",16,60,628,300,model,function() return result.state end);update()
			button(popup,"keep",16,390,200,"Apply sample",function() keep(result.state);main:ClosePopup() end)
			button(popup,"close",528,390,116,"Cancel",function() main:ClosePopup() end)
			main:OpenPopup(660,440,currency and "Foreseeing: hypothetical sample" or "Review modeled action",popup,nil,nil,"close")
		elseif result.choices and #result.choices > 1 then
			local popup={};local choices={}
			for i=1,#result.choices do choices[i]={label="Ghost outcome "..i,val=i} end
			popup.choice=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,628,24},choices)
			local showChoice=workbench.item(popup,"preview",16,70,628,300,model,function()
				return result.choices[popup.choice:GetSelValueByKey("val")].state
			end)
			popup.choice.selFunc=showChoice;showChoice()
			if state.foreseeing then ui.description(popup,"note",16,50,628,20,{"Hypothetical samples; applying one consumes modeled foreseeing."},14) end
			button(popup,"keep",16,390,200,"Keep ghost outcome",function() local index=popup.choice:GetSelValueByKey("val");keep(result.choices[index].state,index);main:ClosePopup() end)
			button(popup,"close",528,390,116,"Cancel",function() main:ClosePopup() end)
			main:OpenPopup(660,440,"Allflame outcomes",popup,nil,nil,"close")
		else keep(result.state) end
	end)
	button(controls,"undo",308,204,124,"Undo currency",function() assert(#history > 0,"No currency action to undo"); state=table.remove(history);table.remove(actions);changedAffixes={};ui.draft(build,"workingCraft",draft.id);updateOptions();refresh() end)
	button(controls,"history",232,390,200,"Item history",function()
		require("Classes.CraftingHistoryControl").Open(model,state,history,actions,function(saved,count)
			state=saved;for i=1,count do table.remove(history);table.remove(actions) end;changed();updateOptions();refresh({"Restored an earlier working item."})
		end)
	end)
	button(controls,"compareItem",16,238,200,"Before / after",function()
		local entries={};for i,line in ipairs(inspect.diff(model,initial,state)) do entries[#entries+1]={id=i,label=line,details={line,"Compared with the recipe starting item."}} end
		browser.Open("Starting item versus working item",entries)
	end)
	button(controls,"inspectItem",16,338,416,"Inspect affixes and slots",function()
		local current=simulator.context(model,state)
		local entries={};for _,entry in ipairs(state.affixes) do local id=entry.id;local side=current.byId[id].type;entries[#entries+1]={id=id,label=side..": "..table.concat(simulator.entryMod(current,entry)," / "),category=side,details=function() return inspect.modDetails(current,id,entry) end} end
		browser.Open("Item modifiers | "..inspect.slots(model,state),entries,{action="Use as target",choose=function(entry) pickTarget(entry.id);controls.page:SelByValue("Target conditions") end})
	end)
	button(controls,"allflame",16,410,416,"Allflame settings (3.29)",function()
		local craft=action();local profile=craft.allflame or {};local popup={}
		popup.mode=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,28,296,24},{"3.29 client data","Observed override"})
		popup.mode:SelByValue(profile.outcomes and not profile.auto and "Observed override" or "3.29 client data")
		popup.upgrade=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{328,28,300,24},{{label="Ship: basic",val=0},{label="Ship: one upgrade",val=1},{label="Ship: fully upgraded",val=2}})
		popup.upgrade:SelByValue(profile.upgradeTier or 2,"val")
		popup.preview=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,70,628,100},nil,{})
		local function automatic() return popup.mode:GetSelValue() == "3.29 client data" end
		local function updateProfile()
			local copy=copyTable(craft);copy.allflame={auto=true,upgradeTier=popup.upgrade:GetSelValueByKey("val")}
			local ok,value=pcall(simulator.allflameProfile,model,state,copy)
			popup.preview.list=rows(ok and {value.outcomes.." ghost outcomes",string.format("Intangibility gain: %d-%d%% | Sulphur: %d",value.gainMin,value.gainMax,value.sulphur),"Choose the ship upgrades you have unlocked."} or {tostring(value):match("^[^\n]+")})
		end
		popup.upgrade.selFunc=updateProfile;popup.preview.shown=automatic;popup.upgrade.enabled=automatic
		edit(popup,"outcomes",16,80,140,24,tostring(profile.outcomes or ""),"Outcomes 1-4",12)
		edit(popup,"gainMin",172,80,140,24,tostring(profile.gainMin or ""),"Min gain %",12)
		edit(popup,"gainMax",328,80,140,24,tostring(profile.gainMax or ""),"Max gain %",12)
		edit(popup,"sulphur",16,120,296,24,tostring(profile.sulphur or ""),"Dead Man's Sulphur cost",12)
		for _,key in ipairs({"outcomes","gainMin","gainMax","sulphur"}) do popup[key].shown=function() return not automatic() end end
		ui.description(popup,"historical",16,178,628,36,{"Allflame is not core in 3.30. These settings model historical or hypothetical crafting."},14)
		label(popup,"policy",16,222,"Recipes prefer the most matching target groups; ties keep the first.")
		button(popup,"use",16,266,200,"Use Allflame settings",function()
			local values
			if automatic() then
				values={auto=true,upgradeTier=popup.upgrade:GetSelValueByKey("val")}
				local copy=copyTable(craft);copy.allflame=values;simulator.allflameProfile(model,state,copy)
			else
				values={};for _,key in ipairs({"outcomes","gainMin","gainMax","sulphur"}) do values[key]=assert(tonumber(popup[key].buf),"Enter all four observed settings") end
				assert(values.outcomes == math.floor(values.outcomes) and values.outcomes >= 1 and values.outcomes <= 4,"Choose one to four outcomes")
				assert(values.gainMin >= 0 and values.gainMax >= values.gainMin and values.gainMax <= 100,"Invalid Intangibility gain range")
			end
			if #targets > 0 then values.preferredTargets=copyTable(targets) end
			craft.allflame=values;configured[craft.method]=craft;changed();main:ClosePopup();refresh({"Allflame settings enabled for "..simulator.labels[craft.method]})
		end)
		button(popup,"disable",232,266,200,"Use ordinary currency",function() craft.allflame=nil;configured[craft.method]=craft;changed();main:ClosePopup() end)
		button(popup,"close",448,266,116,"Cancel",function() main:ClosePopup() end)
		updateProfile();main:OpenPopup(660,318,"Allflame settings (3.29)",popup,nil,nil,"close")
	end)
	local function openGwennen()
		require("Classes.CraftingGwennenControl").Open(function(first,second,cost)
			local price=cost~="" and " Artifact price: "..cost.."." or " Verify the artifact price in game."
			draft.steps[#draft.steps+1]={action="Gwennen observed pair: "..first.description.." OR "..second.description.."."..price,stopWhen="Review both outcomes and cost before committing; Gwennen keeps the item until you choose.",onFailure="The selected outcome is random; this pair is not simulated.",done=false}
			changed();refresh({"Pair added to this guide. Keep working craft, then save the build."})
		end,function(first,second,cost,rerolls)
			local craft={method="gwennen",firstOutcome=first.id,secondOutcome=second.id,gwennenSocketRerolls=rerolls}
			local amount,tier=cost:lower():match("^(%d+)%s+(%a+)%s+broken%s+circle%s+artifacts?$")
			if amount and ({lesser=true,greater=true,grand=true,exceptional=true})[tier] and tonumber(amount)<=1000000000 then craft.artifactCost={[tier]=tonumber(amount)} end
			if not craft.artifactCost and configured.gwennen and configured.gwennen.artifactCost then
				local parts={};for _,key in ipairs({"lesser","greater","grand","exceptional"}) do local n=configured.gwennen.artifactCost[key];if n and n>0 then parts[#parts+1]=n.." "..key:gsub("^%l",string.upper).." Broken Circle Artifacts" end end
				if cost==table.concat(parts," + ") and #parts>0 then craft.artifactCost=copyTable(configured.gwennen.artifactCost) end
			end
			configured.gwennen=craft;chooseMethod("gwennen");controls.page:SelByValue("Emulate item");changed();refresh({"Experimental Gwennen pair selected. Coin odds and ordinary currency transitions are assumptions."})
		end,configured.gwennen,function(first,second,rerolls)
			-- A single deterministic preview does not prove every random branch
			-- succeeds; report only failures and preserve future-step planning.
			return pcall(simulator.action,model,state,{method="gwennen",firstOutcome=first,secondOutcome=second,gwennenSocketRerolls=rerolls},function() return 0.42 end)
		end)
	end
	button(controls,"gwennen",232,378,200,"Record Gwennen pair",openGwennen)
	button(controls,"configure",16,231,416,"Configure fossil combination / donor item",function()
		local method=controls.method:GetSelValueByKey("val")
		local popup={}
		if method == "gwennen" then openGwennen();return
		elseif method == "rog_reroll" then
			require("Classes.CraftingRogControl").Open(configured.rog_reroll,function(craft) configured.rog_reroll=craft;changed();refresh() end,model);return
		elseif method == "fossil" then
			require("Classes.CraftingFossilControl").Open(model,configured.fossil,function(craft) configured.fossil=craft;updateOptions();changed();refresh() end)
			return
		elseif method == "beast_prefix_suffix" or method == "beast_suffix_prefix" then
			label(popup,"beastHint",16,40,"Enter the level of the red beast used for this craft (1-100).")
			label(popup,"beastCaveat",16,70,"Community-researched interaction; current game behavior is unverified.")
			edit(popup,"beastLevel",16,105,180,24,configured[method] and tostring(configured[method].beastLevel or "") or "","Beast level",3)
			button(popup,"use",16,260,180,"Use beast level",function()
				local value=tonumber(popup.beastLevel.buf)
				assert(value and value==math.floor(value) and value>=1 and value<=100,"Enter a whole beast level from 1 to 100")
				local craft=action();craft.beastLevel=value;configured[method]=craft;changed();main:ClosePopup();refresh()
			end)
			button(popup,"clearBeast",216,260,180,"Use item level",function()
				local craft=action();craft.beastLevel=nil;configured[method]=craft;changed();main:ClosePopup();refresh()
			end)
		elseif method == "awakener" or method == "recombine" or method == "recombine_predictable" then
			edit(popup,"donor",16,36,608,170,"","Paste the donor item",24000)
			if method == "recombine_predictable" then
				edit(popup,"chance",16,216,180,24,"","In-game success %",12)
				label(popup,"selectionHint",208,221,"Exact target IDs select mods from each input.")
			end
			button(popup,"use",16,260,180,"Use donor",function()
				local craft={method=method,donorItem=popup.donor.buf}
				local donor
				if method=="awakener" then
					donor=simulator.model(popup.donor.buf)
					local reason=simulator.awakenerDonorReason(simulator.context(model,state),state,donor);assert(not reason,reason)
				elseif method=="recombine" or method=="recombine_predictable" then
					donor=simulator.model(popup.donor.buf)
					assert(simulator.sameRecombinationClass(simulator.context(model,state).item,donor.item),"Recombination requires the same item class")
					assert(not donor.initial.corrupted and not donor.initial.mirrored and not donor.item.synthesised,"Donor must be uncorrupted, non-mirrored and non-synthesised")
					if method=="recombine_predictable" then assert(not simulator.hasPartialLock(donor,donor.initial),"Predictable recombination with a partial affix lock on the donor is not yet modeled") end
				end
				if method == "recombine_predictable" then
					local selected={left={},right={}}
					for _,group in ipairs(targets) do
						assert(#group.anyOf == 1 and not group.negate and (group.atLeast or 1) == 1 and (group.scope or "explicit") == "explicit","Use exact explicit targets without alternatives for predictable selections")
						local id=group.anyOf[1];local side
						for key,input in pairs({left=state,right=donor.initial}) do for _,entry in ipairs(input.affixes) do if entry.id == id and not entry.fractured then assert(not side,"Selected modifier appears on both inputs; use the MCP action to select its input explicitly");side=key end end end
						assert(side,"Each selected target must be present on one input");selected[side][#selected[side]+1]=id
					end
					assert(#selected.left > 0 and #selected.right > 0,"Select at least one exact target from each input")
					craft.selectedMods=selected;craft.reportedSuccessChance=assert(tonumber(popup.chance.buf),"Enter the game's displayed success percentage")
					assert(craft.reportedSuccessChance >= 0 and craft.reportedSuccessChance <= 100,"Success percentage must be between 0 and 100")
					craft.observedRecipientState=copyTable(state)
					craft.observedInputs=simulator.predictableObservation(craft)
				end
				configured[method]=craft;changed();main:ClosePopup();refresh()
			end)
		else error("Select a fossil, Awakener's Orb or recombination first") end
		button(popup,"close",508,260,116,"Cancel",function() main:ClosePopup() end)
		main:OpenPopup(640,310,method=="fossil" and "Fossil combination" or "Craft options",popup,nil,nil,"close")
	end)
	label(controls,"targetLabel",16,262,"Target modifier (add several for AND conditions)")
	controls.target=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,282,416,24},{})
	local targetModel,targetState,targetBeastKey
	refreshTargetOptions=function()
		local current=simulator.context(model,state)
		local first=configured.beast_prefix_suffix and configured.beast_prefix_suffix.beastLevel
		local second=configured.beast_suffix_prefix and configured.beast_suffix_prefix.beastLevel
		local beastKey=tostring(first)..":"..tostring(second)
		local observedState=(first or second) and state or nil
		if current==targetModel and observedState==targetState and beastKey==targetBeastKey then return end;targetModel=current;targetState=observedState;targetBeastKey=beastKey
		local selected=controls.target:GetSelValue();selected=selected and selected.val
		local mods,seen={},{}
		for _,entry in ipairs(current.mods) do seen[entry.id]=true;mods[#mods+1]={label=entry.mod.type.." | "..table.concat(entry.mod," / ").." | iLvl "..entry.mod.level,val=entry.id} end
		for _,config in ipairs({{level=first,side="Suffix"},{level=second,side="Prefix"}}) do if config.level then
			for _,entry in ipairs(simulator.beastTargetSource(current,state,config.level)) do if entry.mod.type==config.side and not seen[entry.id] then
				seen[entry.id]=true;mods[#mods+1]={label=entry.mod.type.." | "..table.concat(entry.mod," / ").." | beast level "..config.level,val=entry.id}
			end end
		end end
		for _,entry in ipairs(current.essences) do mods[#mods+1]={label=entry.name.." guaranteed mod",val=entry.modId} end
		for id in pairs(current.special) do local mod=current.byId[id];if mod.type=="Prefix" or mod.type=="Suffix" or mod.type=="Corrupted" or mod.type=="Exarch" or mod.type=="Eater" or mod.type=="Enchant" then mods[#mods+1]={label=mod.type.." | "..table.concat(mod," / "),val=id} end end
		controls.target:SetList(mods);controls.target.selIndex=1;if selected then controls.target:SelByValue(selected,"val") end
	end
	refreshTargetOptions()
	button(controls,"targetPicker",16,188,416,"Find target modifiers",function()
		require("Classes.CraftingModifierControl").Open(model,copyTable(state),{choose=pickTarget,canAlternative=function() return #targets>0 end,alternative=function(id)
			local group=assert(targets[#targets],"Add a target group first");assert(require("Modules.CraftingModifiers").scope(simulator.context(model,state).byId[id])==(group.scope or "explicit"),"Choose the same explicit/implicit scope, or create a separate group");for _,value in ipairs(group.anyOf) do if value==id then return end end;assert(#group.anyOf<30,"Use up to thirty alternatives per group");group.anyOf[#group.anyOf+1]=id;changed();refresh()
		end,present=function(id)
			assert(not state.destroyed and not state.veil,"Reset destruction or finish the unveil first")
			local next=copyTable(state);if next.rarity=="NORMAL" then next.rarity="RARE" end
			next.affixes[#next.affixes+1]={id=id,range=0.5,crafted=false};local socketAdjusted=simulator.syncAbyssSocket(state,next);state=simulator.validateState(model,next);initial=copyTable(state);history={};actions={};analysis:clearSimulation();syncAnalysis();changedAffixes={};ui.draft(build,"workingCraft",draft.id);updateOptions();refresh({socketAdjusted and "Modifier staged. Abyss socket layout is experimental." or "Modifier staged on a hypothetical item. Working actions reset."})
		end})
	end)
	button(controls,"addTarget",16,310,132,"Add target",function()
		assert(#targets < 6,"Use up to six target groups")
		local id=controls.target:GetSelValueByKey("val");local mod=simulator.context(model,state).byId[id]
		targets[#targets+1]={anyOf={id},scope=require("Modules.CraftingModifiers").scope(mod)};changed();refresh()
	end)
	button(controls,"alternative",160,310,132,"Add alternative",function()
		local group=assert(targets[#targets],"Add a target group first")
		assert(#group.anyOf < 30,"Use up to thirty alternatives per group")
		group.anyOf[#group.anyOf+1]=controls.target:GetSelValueByKey("val");changed();refresh()
	end)
	button(controls,"clearTargets",304,310,128,"Clear targets",function() targets={};changed();refresh() end)
	label(controls,"trialsLabel",16,354,"Trials / action budget per trial")
	edit(controls,"trials",16,374,130,24,"200","Trials",5)
	edit(controls,"budget",162,374,130,24,"20","Action budget",5)
	label(controls,"priceLabel",16,418,"Action override / unit / base cost")
	edit(controls,"price",16,438,130,24,"","Override price",16)
	edit(controls,"currency",162,438,130,24,"chaos","Unit",24)
	edit(controls,"baseCost",308,438,124,24,"","Base cost",16)
	local function capturedSettings(request)
		local options=request.options
		return "Action limit: "..options.maxActions.." per trial | seed "..options.seed
	end
	local function baseCostNote(result)
		local baseCost=result.baseCost
		return type(baseCost)~="number" and "Starting-item cost is unavailable in this older result; rerun to review it."
			or baseCost==0 and "Starting item counted at zero. Enter Base cost if it has a price."
			or string.format("Starting item: %.12g %s each, included in spending.",baseCost,result.costCurrency or "units")
	end
	local function showSimulationResult(result,captured)
		local lines={string.format("Modeled successes: %d / %d (%s)",result.successes,result.trials,ui.percent(result.successChance,2)),
			result.meanCost~=nil and string.format("Mean spent: %.2f %s",result.meanCost,result.costCurrency) or "Cost unavailable: some executed actions have no supplied price.",
			captured.label,capturedSettings(captured),
			"95% sampling interval: "..ui.percent(result.confidenceLow,2).." to "..ui.percent(result.confidenceHigh,2),string.format("Mean attempted actions: %.2f",result.meanActions)}
		table.insert(lines,3,baseCostNote(result))
		if result.meanExecutedActions then lines[#lines+1]=string.format("Mean executed actions: %.2f | failed attempts: %d",result.meanExecutedActions,result.failedAttempts) end
		local warnings=result.warnings or simulator.recipeWarnings(captured.recipe,model)
		for i,warning in ipairs(warnings) do table.insert(lines,1+i,"Model note: "..warning.message) end
		if result.treeVersion then table.insert(lines,2+#warnings,"Build tree: "..(treeVersions[result.treeVersion] and treeVersions[result.treeVersion].display or result.treeVersion).." (context only) | crafting data: "..tostring(result.dataPatch).."; modifiers: "..tostring(result.modifierPatch or simulator.modifierPatch or "bundled")) end
		if result.priceSource then lines[#lines+1]="Quotes: "..result.priceSource.." | "..os.date("%Y-%m-%d",result.priceQuotedAt) end
		if result.actionPriceOverridesSupplied then
			lines[#lines+1]=result.actionPriceOverridesApplied>0 and "Includes selected-action price overrides." or "Selected-action override was not used by this recipe."
		elseif result.priceOverridesSupplied then lines[#lines+1]="Includes resource price overrides." end
		lines[#lines+1]="Result uses the captured starting state."
		if result.resourceUsage then
			lines[#lines+1]="Modeled ingredients and services (all trials)"
			for _,entry in ipairs(result.resourceUsage) do lines[#lines+1]=string.format("%s%s: %.12g total | %.3g per trial",entry.kind=="service" and "Service: " or "",entry.name,entry.amount,entry.meanPerTrial) end
			if #result.resourceUsage==0 then lines[#lines+1]="No resources or services used." end
			lines[#lines+1]="Ingredient quantities exclude starting items. Price overrides do not change quantities."
		else
			for key,count in pairsSortByKey(result.currencySpent) do lines[#lines+1]=pricing.describe(key,simulator.context(model,state))..": "..count.." priced uses" end
		end
		for message,count in pairsSortByKey(result.transitionErrors) do lines[#lines+1]="Failed transitions: "..count.." | "..message end
		refresh(lines)
	end
	local function startSimulation(request)
		local captured=copyTable(request)
		local options=copyTable(captured.options)
		analysis:start("simulation",captured,function(checkpoint)
			options.checkpoint=checkpoint;return simulator.simulate(captured.raw,copyTable(captured.recipe),options)
		end)
		savedSimulationRun=captured;invalidSimulationRun=nil
	end
	local function showSimulation(recipe,fromInitial)
		local budget=assert(tonumber(controls.budget.buf),"Invalid action budget")
		local actionPrices=pricing.actionOverride(simulator.priceKey(action()),
			controls.price.buf~="" and assert(tonumber(controls.price.buf),"Invalid action price") or nil)
		local options={retainSuccesses=10,treeVersion=build.spec.treeVersion,baseCost=controls.baseCost.buf ~= "" and assert(tonumber(controls.baseCost.buf),"Invalid starting item cost") or 0,trials=assert(tonumber(controls.trials.buf),"Invalid trial count"),maxActions=budget,seed=assert(tonumber(controls.seed.buf),"Invalid seed"),
			initialState=copyTable(fromInitial and (recipe.initialState or model.initial) or state),actionPrices=actionPrices,priceBook=draft.priceBook and copyTable(draft.priceBook),currency=controls.currency.buf}
		startSimulation({raw=draft.startingItem,recipe=recipe,options=options,label=fromInitial and "Saved recipe | original starting item" or "Selected action: "..actionName()})
	end
	button(controls,"simulate",16,486,200,"Simulate action",function()
		local a=action();local attempts=assert(tonumber(controls.budget.buf),"Invalid budget");a.maxAttempts=attempts; a.untilTargets=#targets > 0 and copyTable(targets) or nil;a.untilRequiredGroups=a.untilTargets and requiredGroups or nil;a.untilRequirements=(requirements and copyTable(requirements) or nil)
		showSimulation({steps={a},targets=copyTable(targets),requirements=(requirements and copyTable(requirements) or nil),requiredGroups=requiredGroups},false)
	end)
	button(controls,"runRecipe",232,486,200,"Simulate saved recipe",function() assert(draft.nativeRecipe,"This project has no saved native recipe"); showSimulation(draft.nativeRecipe,true) end)
	button(controls,"compareRecipes",16,354,200,"Compare recipes",function()
		assert(#targets>0 or requirements and next(requirements),"Choose target modifiers or item conditions first")
		require("Classes.CraftingCompareControl").Open(build,draft.startingItem,copyTable(state),copyTable(targets),requirements and copyTable(requirements),requiredGroups,action(),draft.nativeRecipe,
			{trials=assert(tonumber(controls.trials.buf)),budget=assert(tonumber(controls.budget.buf)),seed=assert(tonumber(controls.seed.buf)),currency=controls.currency.buf,treeVersion=build.spec.treeVersion,priceBook=draft.priceBook and copyTable(draft.priceBook),
				hasSavedRecipe=function() return draft.nativeRecipe~=nil end,keepRecipe=function(recipe)
					if recipe.initialState then simulator.validateState(model,recipe.initialState) end
					local candidate=copyTable(draft);candidate.nativeRecipe=recipe
					draft=copyTable(build.savers.CraftingProjects:Upsert(candidate));refresh({"Recipe kept. Use build Save to persist."})
				end,
				alternatives=copyTable(draft.recipeAlternatives or {}),
				keepAlternative=function(name,recipe)
					local candidate=copyTable(draft);candidate.recipeAlternatives=candidate.recipeAlternatives or {}
					candidate.recipeAlternatives[#candidate.recipeAlternatives+1]={name=name,recipe=recipe}
					draft=copyTable(build.savers.CraftingProjects:Upsert(candidate));refresh({"Alternative recipe kept. Use build Save to persist."})
					return copyTable(draft.recipeAlternatives[#draft.recipeAlternatives])
				end,
				updateAlternative=function(name,recipe)
				if recipe.initialState then simulator.validateState(model,recipe.initialState) end
					local candidate=copyTable(draft);local found
					for _,alternative in ipairs(candidate.recipeAlternatives or {}) do if alternative.name==name then alternative.recipe=copyTable(recipe);found=true;break end end
					assert(found,"Saved alternative no longer exists");draft=copyTable(build.savers.CraftingProjects:Upsert(candidate));refresh({"Alternative recipe updated. Use build Save to persist."})
					for _,alternative in ipairs(draft.recipeAlternatives) do if alternative.name==name then return copyTable(alternative) end end
				end,
				trackAlternative=function(name,enabled)
					local candidate=copyTable(draft);local found
					for _,alternative in ipairs(candidate.recipeAlternatives or {}) do if alternative.name==name then alternative.trackPickups=enabled;found=true;break end end
					assert(found,"Saved alternative no longer exists");draft=copyTable(build.savers.CraftingProjects:Upsert(candidate));refresh({"Pickup tracking updated. Use build Save to persist."})
				end,
				renameAlternative=function(oldName,newName)
					local candidate=copyTable(draft);local found
					for _,alternative in ipairs(candidate.recipeAlternatives or {}) do if alternative.name==oldName then alternative.name=newName;found=true;break end end
					assert(found,"Saved alternative no longer exists");draft=copyTable(build.savers.CraftingProjects:Upsert(candidate));refresh({"Alternative recipe renamed. Use build Save to persist."})
					for _,alternative in ipairs(draft.recipeAlternatives) do if alternative.name:lower()==newName:match("^%s*(.-)%s*$"):lower() then return alternative.name end end
				end,
				removeAlternative=function(name)
					local candidate=copyTable(draft);local found
					for index,alternative in ipairs(candidate.recipeAlternatives or {}) do if alternative.name==name then table.remove(candidate.recipeAlternatives,index);found=true;break end end
					assert(found,"Saved alternative no longer exists");draft=copyTable(build.savers.CraftingProjects:Upsert(candidate));refresh({"Alternative recipe removed. Use build Save to persist."})
				end})
	end)
	button(controls,"resourcePrices",232,266,200,"Resource prices",function()
		local books={};for _,project in ipairs(build.savers.CraftingProjects.projects) do if project.id~=draft.id and project.priceBook and next(project.priceBook.values) then books[#books+1]=project end end
		local crafts={action()};for _,step in ipairs(require("Modules.CraftingPrices").reachableSteps(draft.nativeRecipe and draft.nativeRecipe.steps)) do crafts[#crafts+1]=step end
		require("Classes.CraftingPricesControl").Open(simulator.context(model,state),state,crafts,draft.priceBook,controls.currency.buf,function(book)
			if controls.currency.buf~=book.currency then controls.currency:SetText(book.currency);updateCurrency() end
			draft.priceBook=book;if draft.run then draft.run.settings.currency=book.currency end;draft=copyTable(build.savers.CraftingProjects:Upsert(draft))
			ui.kept(build,"craftingPrices");refresh({"Resource prices kept in this build. Use build Save to persist."})
		end,books,draft.nativeRecipe and (draft.nativeRecipe.initialState or model.initial))
	end)
	button(controls,"keepRecipe",16,530,200,"Keep actions as recipe",function()
		assert(#actions > 0,"Apply a crafting action first")
		draft.nativeRecipe=simulator.validateRecipe({steps=copyTable(actions),targets=copyTable(targets),requirements=(requirements and copyTable(requirements) or nil),requiredGroups=requiredGroups,initialState=copyTable(initial),rarity=state.rarity})
		if not state.socketLayoutUnknown then draft.targetItem=simulator.toItem(model,state).raw end
		build.savers.CraftingProjects:Upsert(draft)
		refresh({state.socketLayoutUnknown and "Recipe kept. Set the unknown socket layout before keeping a target item." or "Native recipe and target kept in this build. Use build Save to persist."})
	end)
	button(controls,"editRecipe",16,574,200,"Recipe routes",function()
		local recipe=draft.nativeRecipe or {steps=copyTable(actions),targets=copyTable(targets),requirements=(requirements and copyTable(requirements) or nil),requiredGroups=requiredGroups,initialState=copyTable(initial)}
		require("Classes.CraftingRecipeControl").Open(recipe,action(),function(result) draft.nativeRecipe=result;build.savers.CraftingProjects:Upsert(draft);refresh({"Recipe kept. Use build Save to persist."}) end,simulator.context(model,state),{trackUnlock=function(step,context) return require("Modules.CraftingUnlockTasks").track(build,draft.id,context,step) end,reviewUnlocks=function(steps,context) return require("Modules.CraftingUnlockTasks").review(build,draft.id,context,steps) end})
	end)
	button(controls,"targetConditions",16,650,416,"Target counts, rolls and item properties",function()
		require("Classes.CraftingTargetControl").Open(targets,requirements,requiredGroups,function(groups,properties,count) targets=groups;requirements=properties;requiredGroups=count;changed();refresh() end,0,simulator.context(model,state).item.baseName)
	end)
	controls.targetConditions.width=200;controls.targetConditions.label="Item properties"
	button(controls,"targetGroups",232,226,200,"Edit target groups",function()
		require("Classes.CraftingTargetGroupsControl").Open(model,state,targets,requirements,requiredGroups,function(groups,properties,count) targets=groups;requirements=properties;requiredGroups=count;changed();refresh() end)
	end)
	local function showFossilComparison()
		assert(lastFossilComparison,"Run a fossil comparison first")
		require("Classes.CraftingFossilCompareControl").Open(lastFossilComparison,function(ids)
			configured.fossil={method="fossil",fossils=ids};changed();controls.method:SelByValue("fossil","val");updateOptions()
			refresh({"Selected fossil combination. No currency was spent; the item is unchanged."})
		end)
	end
	button(controls,"fossilResults",232,310,200,"Fossil results",showFossilComparison)
	button(controls,"optimize",16,618,200,"Compare fossil subsets",function()
		local selected=action();assert(selected.method == "fossil" and selected.fossils,"Configure a fossil combination first")
		local options={priceBook=draft.priceBook and copyTable(draft.priceBook),currency=controls.currency.buf,treeVersion=build.spec.treeVersion,fossils=copyTable(selected.fossils),initialState=copyTable(state),maxSockets=#selected.fossils,requirements=requirements and copyTable(requirements),requiredGroups=requiredGroups,trials=assert(tonumber(controls.trials.buf)),seed=assert(tonumber(controls.seed.buf))}
		local captured=copyTable(targets)
		analysis:start("fossils",nil,function(checkpoint) options.checkpoint=checkpoint;return simulator.optimizeFossils(draft.startingItem,captured,options) end)
	end)
	local function showOddsResult(result,context)
		local lines={"Target chance under model: "..ui.percent(result.successChance),result.exactFor or result.estimateFor}
		if result.outcomesFirst then
			lines[#lines+1]="Modeled outcomes (assumptions below):"
			for _,entry in ipairs(result.outcomes) do lines[#lines+1]=ui.percent(entry.chance).." | "..(entry.text or "Finite item outcome")..(entry.matches and " | Target" or "") end
		end
		for _,warning in ipairs(result.warnings or {}) do
			if warning.code=="gwennen_estimate" then lines[#lines+1]="Experimental: Gwennen odds and rules are unverified.";break end
		end
		for _,warning in ipairs(result.warnings or {}) do lines[#lines+1]="Model note: "..warning.message end
		if result.sampled then lines[#lines+1]=string.format("%d trials | 95%% sampling interval %s to %s; model uncertainty is separate.",result.trials,ui.percent(result.confidenceLow,2),ui.percent(result.confidenceHigh,2)) end
		for message,count in pairsSortByKey(result.transitionErrors or {}) do lines[#lines+1]="Failed modeled transitions: "..count.." | "..message end
		if result.showAllOutcomes and not result.outcomesFirst then lines[#lines+1]="All modeled outcomes (target matches marked):" end
		if not result.outcomesFirst then for _,entry in ipairs(result.outcomes) do if entry.matches or result.showAllOutcomes then lines[#lines+1]=ui.percent(entry.chance).." | "..(entry.text or "Finite item outcome")..(result.showAllOutcomes and entry.matches and " | Target" or "") end end end
		if result.treeVersion then lines[#lines+1]="Build tree: "..(treeVersions[result.treeVersion] and treeVersions[result.treeVersion].display or result.treeVersion).." (context only) | crafting data: "..tostring(result.dataPatch).."; modifiers: "..tostring(result.modifierPatch or simulator.modifierPatch or "bundled") end
		refresh(lines,context)
	end
	button(controls,"exact",232,574,200,"Calculate action odds",function()
		local craft=action();local captured=copyTable(state);local capturedTargets=copyTable(targets)
		local options={trials=assert(tonumber(controls.trials.buf)),seed=assert(tonumber(controls.seed.buf)),treeVersion=build.spec.treeVersion,requirements=requirements and copyTable(requirements),requiredGroups=requiredGroups}
		local context={state=captured,craft=craft,targets=capturedTargets,requirements=options.requirements,requiredGroups=options.requiredGroups}
		analysis:start("odds",context,function(checkpoint)
			options.checkpoint=checkpoint;return simulator.calculate(draft.startingItem,craft,capturedTargets,captured,options)
		end)
		controls.page:SelByValue("Simulate recipe");refresh()
	end)
	button(controls,"distribution",448,height-48,140,"Results / distribution",function()
		if not lastSimulation and savedSimulationRun then startSimulation(savedSimulationRun);return end
		local result=assert(lastSimulation,"Run a simulation first")
		local request=lastSimulationRun and copyTable(lastSimulationRun)
		local lines={}
		if result.uniqueTrials and result.uniqueTrials>0 then
			lines[#lines+1]={height=24,"Trials ending with unique jewels: "..result.uniqueTrials.." (modeled outcomes)"}
			for _,entry in ipairs(result.uniqueDistribution or {}) do lines[#lines+1]={height=22,string.format("%d %s, %d %s | %s",entry.trials,entry.trials==1 and "trial" or "trials",entry.successes,entry.successes==1 and "success" or "successes",entry.name)} end
		end
		for _,warning in ipairs(result.warnings or request and simulator.recipeWarnings(request.recipe,model) or {}) do lines[#lines+1]={height=24,"Model note: "..warning.message} end
		lines[#lines+1]={height=24,"Attempted actions per trial (all trials, including failures)"}
		for _,bucket in ipairs(result.actionDistribution) do
			lines[#lines+1]={height=20,string.format("%4d | %s %d trials, %d successes",bucket.actions,string.rep("|",math.max(1,math.floor(bucket.trials/result.trials*50))),bucket.trials,bucket.successes)}
		end
		lines[#lines+1]={height=26,"Trials stopped at the action budget: "..result.budgetExhausted}
		lines[#lines+1]={height=24,"Hypothetical items destroyed: "..result.destroyedTrials}
		lines[#lines+1]={height=24,"Spending percentiles include capped failures. They are not the cost of guaranteed success."}
		lines[#lines+1]={height=24,baseCostNote(result)}
		local function show(title,values)
			if not values then return end
			lines[#lines+1]={height=26,title}
			for _,key in ipairs({"p10","p25","p50","p75","p90","p95","p99"}) do lines[#lines+1]={height=20,key..": "..string.format("%.2f",values[key])} end
		end
		show("Actions among successful trials only",result.successfulActionQuantiles)
		show("Spending across all trials ("..result.costCurrency..")",result.spendingQuantiles)
		show("Spending among successful trials only",result.successfulSpendingQuantiles)
		if result.recovery then lines[#lines+1]={height=24,string.format("Recovery: %d restarted bases | %d stopped | %d set aside; no salvage proceeds assumed",result.recovery.restarts,result.recovery.stopped,result.recovery.salvaged)} end
		lines[#lines+1]={height=26,"Final modifier frequencies (all trials / successful trials)"}
		for id,bucket in pairsSortByKey(result.affixDistribution or {}) do
			lines[#lines+1]={height=22,string.format("%d / %d | %s",bucket.trials,bucket.successes,model.byId[id] and table.concat(model.byId[id]," / ") or id)}
		end
		for i,route in pairsSortByKey(result.routeCounts) do
			lines[#lines+1]={height=24,string.format("Step %d: %d visits, %d actions, %d success routes, %d failure routes",i,route.visits,route.executed,route.success,route.failure)}
			local spending=(type(route.pricedCost)~="number" or type(route.unpricedComponents)~="number") and "Rerun to see step spending." or route.unpricedComponents>0 and "Step spending unavailable: missing prices." or string.format("Step spending: %.2f %s per trial",route.pricedCost/result.trials,result.costCurrency or "units")
			lines[#lines+1]={height=22,spending}
		end
		if next(result.routeCounts) then lines[#lines+1]={height=22,"Step spending excludes starting items and restarts."} end
		local popup={}
		local resultHeight=math.max(420,math.min(650,main.screenH-60))
		local display={};for _,line in ipairs(lines) do for _,row in ipairs(require("Modules.PlanningUI").rows({line[1]},798)) do display[#display+1]=row end end;lines=display
		local cardWidth=195
		ui.card(popup,"successCard",16,28,cardWidth,"SUCCESS",ui.percent(result.successChance,1),result.successes.." / "..result.trials.." trials")
		ui.card(popup,"attemptCard",227,28,cardWidth,"MEAN ATTEMPTS",string.format("%.1f",result.meanActions),"All trials, including failures")
		ui.card(popup,"costCard",438,28,cardWidth,"MEAN SPENDING",result.meanCost and string.format("%.2f",result.meanCost) or "Not priced",result.meanCost and result.costCurrency or "Unpriced actions")
		ui.card(popup,"intervalCard",649,28,195,"95% INTERVAL",ui.percent(result.confidenceLow,1).." - "..ui.percent(result.confidenceHigh,1),"Sampling uncertainty")
		local precision={}
		if result.warnings and #result.warnings>0 then precision[#precision+1]="Model notes are listed with the distribution below." end
		if request then precision[#precision+1]=request.label.." | "..capturedSettings(request) end
		precision[#precision+1]=(result.trials<100 or result.confidenceHigh-result.confidenceLow>10) and "Imprecise sampling: run more trials; model uncertainty remains." or "Sampling interval excludes uncertainty in the model."
		ui.description(popup,"precision",16,132,828,40,precision,14)
		for index,entry in ipairs({{"medianSpend","MEDIAN SPEND","p50"},{"unluckySpend","90TH PERCENTILE","p90"},{"veryUnluckySpend","99TH PERCENTILE","p99"}}) do
			local values=result.spendingQuantiles;local value=values and string.format("%.2f",values[entry[3]]) or "Not priced"
			ui.card(popup,entry[1],16+(index-1)*282,174,264,entry[2],value,values and result.costCurrency or "Supply every action price")
		end
		popup.results=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,284,828,resultHeight-398},nil,lines)
		local kept={};for i,entry in ipairs(result.retainedSuccesses or {}) do if entry.itemText then
			local cost=entry.cost~=nil and string.format("%.2f %s",entry.cost,result.costCurrency or "units") or "cost unavailable"
			kept[#kept+1]={label=ui.fit("Item "..i.." (trial "..entry.trial..") | "..cost,320,14),val=i}
		end end
		button(popup,"resources",16,resultHeight-84,176,"Resources used",function()
			local entries={}
			for _,entry in ipairs(result.resourceUsage) do
				local _,icon=pricing.describe(entry.key)
				entries[#entries+1]={id=entry.key,label=entry.name.." | "..string.format("%.12g used",entry.amount),icon=icon,category=entry.kind=="service" and "Services" or "Ingredients",
					details={entry.name,string.format("Total used: %.12g",entry.amount),string.format("Mean per trial: %.6g",entry.meanPerTrial),"Across all "..result.trials.." trials, including failed and capped trials.",
						entry.kind=="service" and "Service units only: no verified ingredient breakdown is available." or "Modeled ingredient quantities from executed actions.",
						"Price overrides change spending, not these quantities. Starting-item costs are separate."}}
			end
			browser.Open("Crafting resources used",entries)
		end)
		popup.resources.enabled=result.resourceUsage and #result.resourceUsage>0 or false
		popup.resources.tooltipText=not result.resourceUsage and "Rerun this older simulation to record ingredient usage." or #result.resourceUsage==0 and "No modeled resources or services were used in this run." or "Browse captured ingredients and service quantities with currency artwork."
		popup.item=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{208,resultHeight-84,348,24},kept)
		button(popup,"preview",572,resultHeight-84,132,"Preview",function()
			local index=assert(popup.item:GetSelValueByKey("val"),"No successful items retained")
			local entry=copyTable(draft);entry.targetItem=result.retainedSuccesses[index].itemText
			require("Classes.CraftingProjectControl").Preview(build,entry)
		end)
		popup.preview.tooltipText="Preview this item against the current build."
		button(popup,"keepTarget",712,resultHeight-84,132,"Keep target",function()
			local index=assert(popup.item:GetSelValueByKey("val"),"No successful items retained")
			local target=result.retainedSuccesses[index].itemText
			local function keep()
				local entry=copyTable(draft);entry.targetItem=target
				build.savers.CraftingProjects:Upsert(entry)
				draft.targetItem=target
				popup.precision.list=ui.rows({"Target kept in guide. Save the build to persist it.",precision[#precision]},828,14)
			end
			if draft.targetItem and draft.targetItem:match("%S") and draft.targetItem~=target then
				main:OpenConfirmPopup("Replace crafting target","Replace the target item in this crafting guide?\nUse build Save to persist the change.","Replace",function()
					local ok,err=pcall(keep);if not ok then ui.errorPopup("Native crafting",err) end
				end)
			else keep() end
		end)
		popup.keepTarget.label=function()
			local index=popup.item:GetSelValueByKey("val")
			local selected=index and result.retainedSuccesses and result.retainedSuccesses[index]
			return selected and draft.targetItem==selected.itemText and "Target kept" or "Keep target"
		end
		popup.keepTarget.tooltipText="Keep this sampled item as the guide's target. Use build Save to persist it."
		popup.item.enabled=#kept>0;popup.preview.enabled=#kept>0;popup.keepTarget.enabled=#kept>0
		if #kept==0 then popup.item:SetList({{label=#(result.retainedSuccesses or {})>0 and "No items available to preview" or "No successful items retained",val=0}}) end
		button(popup,"close",728,resultHeight-42,116,"Close",function() main:ClosePopup() end)
		button(popup,"sample",252,resultHeight-42,220,"Inspect sampled outcome",function()
			local index=popup.item:GetSelValueByKey("val")
			local selected=index and result.retainedSuccesses and result.retainedSuccesses[index]
			local sampleState=result.sampleState
			if selected then sampleState=selected.state end
			local sampleItem=selected and selected.itemText or result.sampleItem
			local success=selected~=nil or result.sampleSuccess
			local c={};local w,h=math.min(660,main.screenW-40),math.min(560,main.screenH-48)
			ui.description(c,"hint",16,28,w-32,48,{success and "Selected successful sampled outcome. Other trials can differ." or "One unsuccessful sampled outcome. Inspect it before deciding whether to salvage or restart."},16)
			local render=require("Classes.JourneyItemControl").new(c,"sampleItem",16,92,w-32,h-166,"SAMPLED OUTCOME");render(require("Modules.CraftingProjects").item(sampleItem))
			button(c,"load",16,h-48,200,"Load into workbench",function()
				local sampled=simulator.validateState(model,copyTable(assert(sampleState,"This older result has no saved item state. Run a new simulation.")))
				assert(not sampled.destroyed and not sampled.uniqueTitle,"This outcome cannot be crafted in this workbench.")
				main:OpenConfirmPopup("Load sampled outcome","Replace the working item with this simulated outcome?\nWorking actions and history will be cleared; the saved recipe is kept.","Load",function()
					state=sampled;initial=copyTable(sampled);history={};actions={};sequence=0;analysis:clearSimulation();syncAnalysis();changedAffixes={};ui.draft(build,"workingCraft",draft.id)
					controls.page:SelByValue("Emulate item");controls.page.selFunc();updateOptions();refresh({"Simulated outcome loaded as a new hypothetical starting item. Working actions reset."})
					main:ClosePopup();main:ClosePopup()
				end)
			end)
			c.load.enabled=sampleState~=nil and not sampleState.destroyed and not sampleState.uniqueTitle
			c.load.tooltipText=not sampleState and "Run a new simulation to capture an item state." or sampleState.destroyed and "Destroyed items cannot be loaded for crafting." or sampleState.uniqueTitle and "This unique outcome cannot be crafted in this workbench." or "Continue crafting this simulated outcome as a new hypothetical starting item."
			button(c,"close",w-156,h-48,140,"Back to results",function() main:ClosePopup() end);ui.style(c);main:OpenPopup(w,h,"Sampled crafting outcome",c,nil,nil,"close")
		end)
		popup.sample.enabled=result.sampleItem~=nil
		popup.sample.label=function() local index=popup.item:GetSelValueByKey("val");return index and result.retainedSuccesses and result.retainedSuccesses[index] and "Inspect selected item" or "Inspect sampled outcome" end
		popup.sample.tooltipText="Inspect the selected successful item, or a sample if none succeeded."
		button(popup,"charts",484,resultHeight-42,220,"Explore charts",function() require("Classes.CraftingChartsControl").Open({{label=draft.title,result=result,recipe=request and request.recipe}}) end)
		button(popup,"moreTrials",16,resultHeight-42,220,"Run more trials",function()
			assert(request,"Run a fresh simulation to capture its setup")
			request.options.trials=math.min(2000,math.floor(20000/request.options.maxActions),math.max(32,result.trials*4))
			controls.trials:SetText(tostring(request.options.trials),true);main:ClosePopup();startSimulation(request)
		end)
		popup.moreTrials.enabled=function() return request~=nil and not tasks.job and result.trials<math.min(2000,math.floor(20000/request.options.maxActions)) end
		popup.moreTrials.tooltipText=function()
			if not request then return "Run a fresh simulation to capture the setup for this older result." end
			if tasks.job then return "Finish or cancel the running calculation before starting more trials." end
			local limit=math.min(2000,math.floor(20000/request.options.maxActions))
			if result.trials>=limit then return limit==2000 and "This setup has reached the maximum of 2,000 trials." or "This setup has reached its "..limit.."-trial limit. Reduce the action budget in a new simulation to allow more trials." end
			return "Repeat this captured recipe, item, targets, seed and prices with more trials. Only the trial count changes."
		end
		ui.style(popup,{moreTrials=true})
		main:OpenPopup(860,resultHeight,"Crafting simulation results",popup,nil,nil,"close")
	end)
	local function openManual(directSockets)
		local editor=require("Classes.CraftingItemEditorControl").Open(model,state,function(edited)
			if state.foreseeing and not tableDeepEquals(state,edited) then edited.foreseeing=nil end
			state=edited;initial=copyTable(edited);history={};actions={};analysis:clearSimulation();syncAnalysis();changedAffixes={};ui.draft(build,"workingCraft",draft.id)
			updateOptions();refresh({"Manual edits set a new recipe starting state."})
		end)
		if directSockets then editor.editSockets:Click() end
	end
	button(controls,"manual",16,448,416,"Edit hypothetical item",function() openManual(false) end)
	button(controls,"reset",232,530,200,"Reset item",function() state=copyTable(initial);history={};actions={};changedAffixes={};ui.draft(build,"workingCraft",draft.id);updateOptions();refresh() end)
	button(controls,"preview",16,height-48,200,"Preview in build",function()
		assert(not state.veil and not state.destroyed,"A pending unveil or destroyed item cannot be previewed")
		assert(not state.socketLayoutUnknown,"Set the unknown socket layout before previewing this item in a build.")
		local entry=copyTable(draft); entry.targetItem=simulator.toItem(model,state).raw
		require("Classes.CraftingProjectControl").Preview(build,entry)
	end)
	button(controls,"cancelJob",232,height-48,200,"Cancel crafting job",function() require("Modules.CraftingTasks").cancel() end)
	button(controls,"coverage",width-312,height-48,132,"Coverage",function()
		local entries={}
		for i,line in ipairs(simulator.limits) do entries[#entries+1]={id=i,label=line,category="Assumptions",details={line,"Supplemental baseline: "..tostring(simulator.dataPatch or "bundled"),"Modifier data: "..tostring(simulator.modifierPatch or "bundled")}} end
		for _,method in ipairs(simulator.methods) do entries[#entries+1]={id=method,label=simulator.labels[method],category=inspect.category(method),details={"Implemented in the bounded model",workbench.hint(method,state,model),"Item-specific options and prerequisites are validated when applying.","Coverage does not imply complete game parity."}} end
		browser.Open("Crafting coverage and assumptions",entries)
	end)
	controls.coverage.label=function() return "Rules & sources" end
	controls.coverage.tooltipText="View supported crafting methods, data versions and assumptions."
	button(controls,"close",width-164,height-48,148,layout and "Back to projects" or "Close",function()
		if tasks.job and tasks.job.owner==controls then tasks.cancel("Crafting view closed") end
		if layout then layout.openProjects() else ui.discard(build,"workingCraft",draft.id);main:ClosePopup() end
	end)
	controls.resultSummary=new("TextListControl"):TextListControl({"TOPLEFT",nil,"TOPLEFT"},{16,398,416,height-464},nil,rows({"Run an action or a recipe to inspect its results."}))
	controls.undo.enabled=function() return #history>0 end
	controls.undo.tooltipText=function() return #history==0 and "Apply a crafting action first; there is nothing to undo." or "Undo the most recent crafting action." end
	targetReason=function(saved)
		local recipe=saved and draft.nativeRecipe
		local current=recipe and (recipe.initialState or model.initial) or state
		return simulator.implicitTargetReason(simulator.context(model,current),current,recipe and recipe.targets or targets)
	end
	actionConfigurationReason=function()
		local reason=simulator.configurationReason(model,state,action())
		if reason then return reason end
		local observed=configured.recombine_predictable and configured.recombine_predictable.observedRecipientState
		if controls.method:GetSelValueByKey("val")=="recombine_predictable" and (type(observed)~="table" or observed.origin~=model.initial.origin or not tableDeepEquals(observed,state) or not tableDeepEquals(state,observed)) then
			return "Recipient changed or the observation is missing. Reconfirm the in-game success percentage in Craft settings."
		end
		if controls.method:GetSelValueByKey("val")=="recombine_predictable" and not simulator.predictableObservationMatches(configured.recombine_predictable or {}) then
			return "Donor or selection changed, or the observation is incomplete. Reconfirm the in-game success percentage in Craft settings."
		end
	end
	gwennenApplyReason=function()
		local craft=action()
		if craft.method~="gwennen" or not workbench.available("gwennen",state,model) then return end
		if not pcall(require("Modules.CraftingGwennen").validate,craft) then return end
		return simulator.gwennenPairReason(model,state,craft)
	end
	local function actionConfigured() return actionConfigurationReason()==nil end
	local function missingTargets() return #targets==0 and not (requirements and next(requirements)) end
	local noTargets="Choose a target modifier or item condition first."
	local busy="Finish or cancel the running calculation first."
	controls.simulate.enabled=function() return actionConfigured() and not tasks.job and not targetReason() and (#targets>0 or requirements and next(requirements)~=nil) end
	controls.simulate.tooltipText=function()
		local message=actionConfigurationReason() or tasks.job and busy or targetReason() or missingTargets() and noTargets
		if message then return "Selected action: "..actionName().."\n"..message end
		local available,reason=workbench.available(controls.method:GetSelValueByKey("val"),state,model)
		reason=not available and reason or gwennenApplyReason()
		return "Selected action: "..actionName().."\n"..(reason and reason.." The simulation can still succeed without an action if the item already meets the goal." or "Simulate from the working item using the chosen target modifiers or item conditions.")
	end
	controls.resourcePrices.enabled=function() return require("Modules.CraftingTasks").job==nil end
	controls.currency.enabled=function() return not draft.priceBook or not next(draft.priceBook.values) end
	controls.currency.showDisabledValue=true
	updateCurrency=function()
		if draft.priceBook and not next(draft.priceBook.values) then draft.priceBook.currency=controls.currency.buf end
		priceOverrides={};controls.price:SetText("");controls.baseCost:SetText("")
		if draft.run then
			draft.run.priceOverrides={};draft.run.settings.price="";draft.run.settings.baseCost="";draft.run.settings.currency=controls.currency.buf
		end
	end
	controls.currency.changeFunc=updateCurrency
	controls.currency.tooltipText="Saved resource quotes use this common unit. Change it through Resource prices. Changing units clears action overrides and base cost."
	controls.price.tooltipText=function() return "Optional total price of "..actionName()..". It applies when that action executes, including inside saved recipes." end
	local function savedObservationReason()
		local reason=simulator.predictableRecipeObservationReason(draft.nativeRecipe)
		if reason then return reason.." Configure a new observation in Craft settings, then use Recipe routes to replace the selected step with the emulator action." end
	end
	controls.runRecipe.enabled=function() return not tasks.job and draft.nativeRecipe~=nil and not targetReason(true) and not savedObservationReason() end
	controls.runRecipe.tooltipText=function() return tasks.job and busy or not draft.nativeRecipe and "Save a recipe in this project first." or targetReason(true) or savedObservationReason() or "Run the project's saved steps from the original starting item, with the saved recipe's targets." end
	controls.exact.enabled=function() return actionConfigured() and not tasks.job and not targetReason() and (#targets>0 or requirements~=nil and next(requirements)~=nil) and workbench.available(controls.method:GetSelValueByKey("val"),state,model) and not gwennenApplyReason() end
	controls.exact.tooltipText=function()
		local configuration=actionConfigurationReason();if configuration then return configuration end
		local pairReason=gwennenApplyReason();if pairReason then return pairReason end
		if tasks.job then return "Finish or cancel the running calculation first." end
		if #targets==0 and not (requirements and next(requirements)) then return "Choose a target modifier or item condition before calculating." end
		if targetReason() then return targetReason() end
		local available,reason=workbench.available(controls.method:GetSelValueByKey("val"),state,model)
		return available and "Calculate this action from the working item, with captured target conditions." or reason
	end
	controls.compareRecipes.enabled=function() return not tasks.job and not targetReason() and (#targets>0 or requirements and next(requirements)~=nil) end
	controls.compareRecipes.tooltipText=function() return tasks.job and busy or targetReason() or missingTargets() and noTargets or "Compare recipes using the current targets." end
	controls.keepRecipe.enabled=function() return #actions>0 and not state.destroyed and not state.veil end
	controls.keepRecipe.tooltipText=function()
		return state.destroyed and "This item was destroyed. Undo that action before keeping a recipe." or state.veil and "Resolve the veiled modifier before keeping a recipe." or #actions==0 and "Apply an action first to create a recipe." or "Keep the recorded actions as this project's recipe."
	end
	controls.manual.enabled=function() return not state.destroyed and not state.veil and not state.uniqueTitle end
	controls.manual.tooltipText=function()
		return state.destroyed and "This item was destroyed. Undo that action before editing it." or state.veil and "Resolve the veiled modifier before editing the item." or state.uniqueTitle and "Editing this unique outcome is not supported here." or "Edit a hypothetical item state."
	end
	controls.allflame.enabled=function() return simulator.supportsAllflame(controls.method:GetSelValueByKey("val")) end
	controls.allflame.tooltipText=function() return controls.allflame:IsEnabled() and "Historical 3.29 Allflame model; Allflame is not core in 3.30." or "Allflame is not modeled for this action. Choose a supported itemised currency." end
	controls.fossilResults.tooltipText="Reopen the captured comparison. Rerun after changing the item, targets or quotes."
	controls.fossilResults.enabled=function() return lastFossilComparison~=nil and require("Modules.CraftingTasks").job==nil end
	controls.optimize.tooltipText=function()
		if targetReason() then return targetReason() end
		if controls.method:GetSelValueByKey("val")~="fossil" then return "Select Fossil resonator first." end
		if tasks.job then return busy end
		if missingTargets() then return noTargets end
		local craft=action();if not craft.fossils or #craft.fossils==0 then return "Configure at least one fossil first." end
		return "Configure fossil candidates in Settings, then compare ordinary fossil crafts."
	end
	controls.optimize.enabled=function()
		if controls.method:GetSelValueByKey("val")~="fossil" or not controls.simulate:IsEnabled() then return false end
		local craft=action();return craft.fossils~=nil and #craft.fossils>0
	end
	controls.distribution.enabled=function() return not tasks.job and (lastSimulation~=nil or savedSimulationRun~=nil) end
	controls.distribution.label=function() return not lastSimulation and savedSimulationRun and "Rerun saved" or "Results / distribution" end
	controls.distribution.tooltipText=function() return tasks.job and busy or not lastSimulation and savedSimulationRun and "Rerun the saved recipe, item, seed and prices using current crafting data." or not lastSimulation and invalidSimulationRun and "The saved simulation setup could not be read. Run a new simulation; the original setup is preserved." or not lastSimulation and "Run a simulation first to see its results and distribution." or "Inspect the most recent simulation results and distribution." end
	controls.cancelJob.enabled=function() return require("Modules.CraftingTasks").job~=nil end
	controls.apply.enabled=function() return not state.destroyed and not state.uniqueTitle end
	controls.preview.enabled=function() return not state.destroyed and not state.veil and not state.socketLayoutUnknown end
	controls.preview.tooltipText=function() return state.destroyed and "This item was destroyed. Undo that action before previewing it." or state.veil and "Resolve the veiled modifier before previewing this item." or state.socketLayoutUnknown and "Set the unknown socket layout before previewing this item in a build." or "Preview this item against the current build." end
	controls.configure.label=function() local method=controls.method:GetSelValueByKey("val");return method=="fossil" and "Configure fossil combination" or method=="gwennen" and "Configure Gwennen pair" or method=="rog_reroll" and "Configure Rog offer" or (method=="beast_prefix_suffix" or method=="beast_suffix_prefix") and "Set beast level" or "Configure donor item" end
	controls.configure.enabled=function() local method=controls.method:GetSelValueByKey("val");return method=="beast_prefix_suffix" or method=="beast_suffix_prefix" or method=="gwennen" or method=="rog_reroll" or method=="fossil" or method=="awakener" or method=="recombine" or method=="recombine_predictable" end
	controls.configure.tooltipText=function() return controls.configure:IsEnabled() and "Configure the selected craft before applying or simulating it." or "The selected craft does not need additional settings." end
	controls.page=new("DropDownControl"):DropDownControl({"TOPLEFT",nil,"TOPLEFT"},{16,18,416,28},{"Emulate item","Target conditions","Simulate recipe","Craft settings"})
	controls.page.selFunc=function() refresh() end
	button(controls,"settings",16,380,200,"Find currencies",palette)
	button(controls,"benchRarity",16,458,416,"Preview bench rarity outcome",function()
		local popup={}
		ui.description(popup,"help",16,30,350,110,{"Choose a hypothetical outcome to inspect.","Modifier rolls and retained properties are estimates.","Rarity odds, price and eligibility are unknown.","Unique references may be legacy or unavailable.","Unique values, sockets and quality are illustrative.","Copied text does not retain this label."},14)
		popup.outcome=new("DropDownControl"):DropDownControl(ui.anchor,{16,150,300,26},{{label="Magic example",val="MAGIC"},{label="Rare example",val="RARE"},{label="Unique reference",val="UNIQUE"}})
		popup.unique=new("DropDownControl"):DropDownControl(ui.anchor,{16,188,300,26},{})
		popup.unique.shown=function() return popup.outcome:GetSelValueByKey("val")=="UNIQUE" end
		popup.reference=ui.description(popup,"reference",16,346,350,60,{},14)
		popup.reference.shown=popup.unique.shown
		popup.notice=ui.description(popup,"notice",16,414,350,32,{},14)
		local function showSource()
			local choice=popup.unique:GetSelValue();local source=choice and choice.source
			popup.reference.list=ui.rows({#popup.unique.list==0 and "No bundled unique references for this base." or source and "Bundled source: "..source or "Bundled source not recorded."},334,14)
		end
		local show=require("Classes.JourneyItemControl").new(popup,"example",390,30,360,408,"CONDITIONAL EXAMPLE",{expanded=true})
		local example,kept
		local function generate()
			local outcome=popup.outcome:GetSelValueByKey("val")
			if outcome=="UNIQUE" then showSource() end
			local title=outcome=="UNIQUE" and #popup.unique.list>0 and popup.unique:GetSelValueByKey("val") or nil
			local ok,result=pcall(require("Modules.CraftingBenchRarityPreview").preview,draft.startingItem,outcome,tonumber(controls.seed.buf),state,title)
			if not ok then ui.errorPopup("Bench rarity preview",result);return end
			example=result;kept=false;popup.notice.list={};show(new("Item"):Item(example.itemText))
		end
		popup.outcome.selFunc=function()
			example=nil;popup.notice.list={};show(nil)
			if popup.outcome:GetSelValueByKey("val")=="UNIQUE" then
				local ok,result=pcall(require("Modules.CraftingBenchRarityPreview").uniqueCandidates,draft.startingItem,state)
				if not ok then ui.errorPopup("Bench rarity preview",result);return end
				local choices={};for _,entry in ipairs(result.candidates) do choices[#choices+1]={label=entry.title,val=entry.title,source=entry.source} end;popup.unique:SetList(choices);showSource()
			end
		end
		popup.unique.selFunc=function() example=nil;popup.notice.list={};show(nil);showSource() end
		button(popup,"generate",16,230,300,"Generate example",generate)
		popup.generate.enabled=function() return popup.outcome:GetSelValueByKey("val")~="UNIQUE" or #popup.unique.list>0 end
		popup.generate.tooltipText=function() return not popup.generate:IsEnabled() and "No bundled unique references are available for this base. Choose another outcome." or "Generate a conditional example without applying a craft." end
		button(popup,"copy",16,268,300,"Copy example item",function() assert(example,"Generate an example first");Copy(example.itemText) end)
		popup.copy.enabled=function() return example~=nil end
		button(popup,"keep",16,306,300,"Keep as new project",function()
			assert(example,"Generate an example first")
			local store=build.savers.CraftingProjects;local id,exists,attempt
			repeat
				attempt=(attempt or 0)+1;id="bench-"..require("sha1")(tostring({})..os.time()..attempt):sub(1,24);exists=false
				for _,project in ipairs(store.projects) do if project.id==id then exists=true;break end end
			until not exists
			local title="Bench rarity example ("..example.outcome:lower()..")"
			local project=require("Modules.CraftingBenchRarityPreview").project(draft.startingItem,example,draft.slot,title,id)
			store:Upsert(project);kept=true;popup.notice.list=ui.rows({"Project kept. Save the build to retain it."},334,14)
		end)
		popup.keep.enabled=function() return example~=nil and not kept end
		button(popup,"close",630,458,120,"Close",function() main:ClosePopup() end)
		ui.style(popup,{generate=true});main:OpenPopup(768,500,"Bench rarity preview",popup,nil,nil,"close")
	end)
	controls.benchRarity.tooltipText="View a conditional magic or rare example; this does not simulate rarity odds or apply a craft."
	local function crafting() return controls.page:GetSelValue()=="Emulate item" and not paletteOpen and not inspectedId end
	controls.item.enabled=function() return crafting() and controls.apply:IsEnabled() end
	controls.apply.x=16;controls.apply.width=200;controls.undo.x=232;controls.undo.width=200
	ui.label(controls,"selectedAction",16,230,"",20)
	controls.selectedAction.label=function()
		local name=actionName();local suffix=""
		while #name>0 and DrawStringWidth(20,"VAR",name..suffix)>leftWidth do name=name:sub(1,-2);suffix="..." end
		return "^xE2C28C"..name..suffix
	end
	controls.actionHint=ui.description(controls,"actionHint",16,264,416,40,{})
	local pages={
		["Craft settings"]={methodLabel=96,method=116,configure=160,keepRecipe=198,reset=198,exact=238,compareItem=238,seedLabel=278,seed=298,inspectItem=338,allflame=378,gwennen=378,manual=418,benchRarity=458},
		["Emulate item"]={selectedAction=230,actionHint=264,optionLabel=310,option=330,apply=370,undo=370,settings=414,history=414},
		["Target conditions"]={targetLabel=96,target=116,addTarget=154,alternative=154,clearTargets=154,targetPicker=188,targetConditions=226,targetGroups=226,targetSummary=270},
		["Simulate recipe"]={trialsLabel=96,trials=116,budget=116,priceLabel=160,price=180,currency=180,baseCost=180,simulate=224,runRecipe=224,editRecipe=266,resourcePrices=266,optimize=310,fossilResults=310,distribution=354,compareRecipes=354,resultSummary=398},
	}
	for page,layout in pairs(pages) do for key,y in pairs(layout) do
		local control=controls[key];control.y=y;control.shown=page=="Emulate item" and crafting or function() return controls.page:GetSelValue()==page end
	end end
	controls.distribution.x=232;controls.distribution.width=200
	controls.option.shown=function() return crafting() and #controls.option.list>0 end
	controls.optionLabel.shown=controls.option.shown
	controls.apply.enabled=function() return actionConfigured() and workbench.available(controls.method:GetSelValueByKey("val"),state,model) and not gwennenApplyReason() end
	controls.apply.tooltipText=function()
		local method=controls.method:GetSelValueByKey("val");local available,reason=workbench.available(method,state,model)
		local text=not available and reason or actionConfigurationReason() or gwennenApplyReason() or workbench.hint(method,state,model,action())
		for _,warning in ipairs(simulator.actionWarnings(action(),{item=model.item,initial=state})) do
			if warning.code=="abyss_socket_layout" or warning.code=="tincture_imported_values" then text=text.."\n"..warning.message end
		end
		local lines={};for _,row in ipairs(ui.rows({text},math.min(leftWidth+80,500),14)) do lines[#lines+1]=row[1] end
		return table.concat(lines,"\n")
	end
	controls.apply.height=32;controls.undo.height=32
	controls.apply.y=function() return #controls.option.list>0 and 370 or 320 end;controls.undo.y=controls.apply.y
	controls.settings.y=function() return controls.apply:GetProperty("y")+44 end;controls.history.y=controls.settings.y
	button(controls,"warningDetails",232,458,200,"Review warnings",function() browser.Open("Crafting item warnings",copyTable(itemWarnings)) end)
	controls.warningDetails.y=function() return controls.settings:GetProperty("y")+44 end
	controls.warningDetails.shown=function() return crafting() and #itemWarnings>1 end
	controls.warningDetails.tooltipText="Review all item import and socket warnings."
	button(controls,"resolveSockets",16,458,200,"Set socket layout",function() openManual(true) end)
	controls.resolveSockets.y=function() return controls.settings:GetProperty("y")+44 end
	controls.resolveSockets.shown=function() return crafting() and state.socketLayoutUnknown and not state.destroyed and not state.veil end
	controls.resolveSockets.tooltipText="Enter an observed or hypothetical layout; accepting the edit starts a new recipe state."
	controls.targetSummary.height=height-338
	controls.history.enabled=function() return #history>0 end
	controls.history.tooltipText=function() return #history==0 and "Apply an action first to see item history." or "Review the item's recorded crafting history." end
	controls.settings.label="Find currencies"
	controls.allflame.width=200
	controls.cancelJob.shown=function() return require("Modules.CraftingTasks").job~=nil end
	ui.style(controls,{apply=true,preview=true},{item=true})
	ui.tabs(controls,controls.page,{{"tab_craft","Emulate item","Craft"},{"tab_targets","Target conditions","Targets"},{"tab_simulate","Simulate recipe","Simulate"},{"tab_settings","Craft settings","Settings"}},16,18,416)
	workbench.currencies(controls,function(method)
		chooseMethod(method)
	end,function() return controls.method:GetSelValueByKey("val") end,crafting,function(method)
		local count=0;for _,entry in ipairs(actions) do if entry.method == method then count=count+1 end end;return count
	end,function() return state end,model,leftWidth)
	controls.methodLabel.label="More currencies and crafting methods"
	controls.optionLabel.label="Options for selected currency"
	controls.apply.label="Apply to item"
	ui.label(controls,"projectName",leftWidth+32,24,"",18)
	controls.projectName.label=function()
		local title=draft.title
		while #title>0 and DrawStringWidth(18,"VAR",title)>width-leftWidth-64 do title=title:sub(1,-2) end
		return "^7"..title
	end
	local function inventoryChanged(project) if project.id==draft.id then draft.inventory=copyTable(project.inventory) end end
	button(controls,"inventory",leftWidth+32,54,math.floor((width-leftWidth-60)/2),"Item inventory",function()
		require("Classes.CraftingInventoryControl").Open(build,{current={baseItem=draft.startingItem,state=copyTable(state),title="Working item",slot=draft.slot},change=inventoryChanged,resume=function(project)
			if layout then layout.openWorkbench(project) else Panel.Open(build,project) end
		end})
	end)
	button(controls,"keepItem",leftWidth+44+math.floor((width-leftWidth-60)/2),54,math.floor((width-leftWidth-60)/2),"Keep item snapshot",function()
		local project=copyTable(draft);for _,saved in ipairs(build.savers.CraftingProjects.projects) do if saved.id==draft.id then project=copyTable(saved);break end end
		local originNote=draft.originNote or (draft.notes and draft.notes:find("Conditional bench-rarity example;",1,true)==1 and draft.notes:sub(1,1000) or nil)
		project.inventory=project.inventory or {};project.inventory[#project.inventory+1]=require("Modules.CraftingInventory").capture(draft,state,draft.title:sub(1,104).." / "..(#project.inventory+1),originNote)
		inventoryChanged(build.savers.CraftingProjects:Upsert(project));refresh({"Item snapshot kept in this build. Open Item inventory to compare or resume it; use build Save to persist."})
	end)
	controls.keepItem.tooltipText="Keep a snapshot in Item inventory to compare or resume later. Save the build to persist it."
	controls.stage=new("Control"):Control(ui.anchor,{leftWidth+32,84,width-leftWidth-48,height-148})
	function controls.stage:Draw()
		local x,y=self:GetPos();local w,h=self:GetSize()
		SetDrawLayer(nil,1);SetDrawColor("^x0A1018");DrawImage(nil,x,y,w,h);SetDrawColor("^x8D9DB0")
		DrawString(x+w/2,y+8,"CENTER_X",12,"VAR","WORKING ITEM");DrawString(x+w/2,y+h-2,"CENTER_X",12,"VAR","Click a modifier to inspect it | F: fractured | C: crafted");SetDrawLayer(nil,0)
	end
	for _,key in ipairs({"item","itemMods"}) do
		local control=controls[key];local draw=control.Draw
		function control:Draw(...) SetDrawLayer(nil,2);draw(self,...);SetDrawLayer(nil,0) end
	end
	if draft.priceBook then controls.currency:SetText(draft.priceBook.currency) end
	if restored then
		controls.page:SelByValue(restored.page);controls.seed:SetText(restored.seed)
		for key,value in pairs(restored.settings or {}) do controls[key]:SetText(value) end
	end
	if layout then
		layout.snapshot=function() return copyTable({kind="workbench",priceOverrides=priceOverrides,project=draft,state=state,initial=initial,targets=targets,requirements=requirements,requiredGroups=requiredGroups,craftWidth=leftWidth,favorites=favorites,paletteOpen=paletteOpen,palette=paletteView and paletteView.snapshot(),inspectedId=inspectedId,
			history=history,actions=actions,configured=configured,sequence=sequence,lastSimulation=lastSimulation,lastSimulationRun=lastSimulationRun,simulationRequest=savedSimulationRun or invalidSimulationRun,simulationRequestWarning=invalidSimulationRun~=nil,lastFossilComparison=lastFossilComparison,page=controls.page:GetSelValue(),method=controls.method:GetSelValueByKey("val"),seed=controls.seed.buf,resultRows=savedResultRows or controls.resultSummary.list,settings={trials=controls.trials.buf,budget=controls.budget.buf,price=controls.price.buf,currency=controls.currency.buf,baseCost=controls.baseCost.buf}}) end
	end
	button(controls,"keepWorking",232,height-48,200,"Keep working craft",function()
		if overrideKey then priceOverrides[overrideKey]=controls.price.buf end
		local run={priceOverrides=priceOverrides,schemaVersion=1,state=state,initial=initial,history=history,actions=actions,configured=configured,sequence=sequence,targets=targets,requirements=requirements,requiredGroups=requiredGroups,simulationRequest=lastSimulationRun or savedSimulationRun or invalidSimulationRun,
			page=controls.page:GetSelValue(),method=controls.method:GetSelValueByKey("val"),seed=controls.seed.buf,
			settings={trials=controls.trials.buf,budget=controls.budget.buf,price=controls.price.buf,currency=controls.currency.buf,baseCost=controls.baseCost.buf}}
		local saved=copyTable(draft);saved.run=run
		local kept=build.savers.CraftingProjects:Upsert(saved);draft=copyTable(kept)
		ui.kept(build,"workingCraft",draft.id)
		refresh({"Working item, history and settings kept. Use build Save to resume after restarting. No budget was spent."})
	end)
	controls.keepWorking.shown=function() return require("Modules.CraftingTasks").job==nil end
	controls.keepWorking.tooltipText="Keep the working item, history and settings in this project. Save the build to resume them later."
	ui.styleButton(controls.keepWorking,"primary")
	paletteView=require("Modules.CraftingPalette").new(controls,leftWidth,height,{current=function() return controls.method:GetSelValueByKey("val") end,favorites=favorites,restore=restored and restored.palette,
		shown=function() return controls.page:GetSelValue()=="Emulate item" and paletteOpen end,available=function(method) return workbench.available(method,state,model) end,hint=function(method) return workbench.hint(method,state,model,configured[method]) end,
		choose=chooseMethod,close=function() paletteOpen=false;refresh() end})
	ui.label(controls,"affixHeading",16,96,"Modifier details",20)
	controls.affixFacts=new("TextListControl"):TextListControl(ui.anchor,{16,128,leftWidth,height-290},nil,{})
	controls.affixAction=new("DropDownControl"):DropDownControl(ui.anchor,{16,height-146,leftWidth-136,26},{})
	button(controls,"affixUseAction",leftWidth-108,height-146,124,"Select action",function() chooseMethod(controls.affixAction:GetSelValueByKey("val")) end)
	button(controls,"affixBack",16,height-98,math.floor((leftWidth-12)/2),"< Currency tray",function() inspectedId=nil;refresh() end)
	button(controls,"affixTarget",28+math.floor((leftWidth-12)/2),height-98,math.floor((leftWidth-12)/2),"Use as target",function() pickTarget(inspectedId);inspectedId=nil;controls.page:SelByValue("Target conditions");refresh() end)
	local affixControls={}
	for _,key in ipairs({"affixHeading","affixFacts","affixAction","affixUseAction","affixBack","affixTarget"}) do controls[key].shown=function() return controls.page:GetSelValue()=="Emulate item" and inspectedId~=nil end;affixControls[key]=controls[key] end
	controls.affixUseAction.enabled=function() local method=controls.affixAction:GetSelValueByKey("val");return method and workbench.available(method,state,model) end
	controls.affixUseAction.tooltipText=function()
		local method=controls.affixAction:GetSelValueByKey("val");if not method then return "Choose an action for this modifier first." end
		local available,reason=workbench.available(method,state,model)
		return available and "Select this action in the currency tray." or reason or "This action is not available for the current item."
	end
	controls.affixTarget.enabled=function() return #targets<6 end
	controls.affixTarget.tooltipText=function() return #targets>=6 and "This plan already has six target groups. Remove one before adding another." or "Add this modifier as a target group." end
	controls.affixBack.height=28;controls.affixTarget.height=28
	ui.style(affixControls,{affixTarget=true})
	for key,control in pairs(controls) do
		if key~="item" and key~="itemMods" and key~="stage" and key~="projectName" and not key:match("^currency_") and not key:match("^palette") and not key:match("^affix") and type(control.x)=="number" and control.x<448 and type(control.width)=="number" then
			control.x=16+math.floor((control.x-16)*leftWidth/416);if control.width>0 then control.width=math.floor(control.width*leftWidth/416) end
		end
	end
	if layout then ui.splitter(controls,"splitter",leftWidth+19,84,height-148,function(delta)
		layout.workbench=layout.snapshot();layout.craftWidth=math.max(416,math.min(width-400,leftWidth+delta));Panel.Open(build,draft,layout)
	end);controls.splitter.enabled=function() return not tasks.job end end
	if restored then controls.method:SelByValue(restored.method or "alchemy","val");controls.resultSummary.list=restored.resultRows or controls.resultSummary.list
	elseif draft.preferredMethod then controls.method:SelByValue(draft.preferredMethod,"val") end
	updateOptions(true);refresh(invalidSimulationRun and {"Saved simulation setup could not be read. The original is preserved; run a new simulation to replace it."} or savedSimulationRun and not lastSimulation and {"Saved simulation setup available. Choose Rerun saved to calculate it using current crafting data."} or nil)
	-- Hook edits after restoring controls so viewing a saved craft stays clean.
	for _,key in ipairs({"trials","budget","price","currency","baseCost","seed"}) do
		local control=controls[key];local previous=control.changeFunc
		control.changeFunc=function(...)
			if previous then previous(...) end
			changed()
		end
	end
	ready=true
	if inspectedId then populateAffix(inspectedId) end
	for key,control in pairs(controls) do if key~="stage" then control.layoutAudit="crafting-workbench" end end
	if layout then layout.mount(width,height,"Crafting workbench",controls) else main:OpenPopup(width,height,"Crafting workbench",controls,nil,nil,"close") end
	analysis:bind(controls,function(event,announce)
		syncAnalysis()
		if event.phase=="error" then refresh({ui.errorText(event.message)})
		elseif event.phase=="queued" then refresh({"Calculation queued. You can cancel it below."})
		elseif event.phase=="progress" then
			local p=event.progress
			if event.kind=="fossils" and p.combinations then refresh({"Fossil combination "..p.combination.." / "..p.combinations})
			elseif p.trials then refresh({(event.kind=="simulation" and "Simulation running: trial " or "Calculating odds: trial ")..p.trial.." / "..p.trials})
			else refresh({"Calculation queued. You can cancel it below."}) end
		elseif event.kind=="simulation" then showSimulationResult(event.result,event.context)
		elseif event.kind=="odds" then showOddsResult(event.result,event.context)
		else
			refresh({"Compared "..#event.result.combinations.." ordinary fossil subsets. Open Fossil results to review captured chances and costs."})
			if announce then showFossilComparison() end
		end
	end,function()
		if layout then
			local workspace=build.planningWorkspace
			return #main.popups==0 and build.viewMode=="PLANNER" and workspace and workspace.body and workspace.body.controls==controls
		end
		return main.popups[1] and main.popups[1].controls==controls
	end)
	return controls
end
return Panel
