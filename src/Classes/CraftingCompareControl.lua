-- Paired bounded recipe experiments; each route starts from the same captured item.
local sim=require("Modules.CraftingSimulator")
local ui=require("Modules.PlanningUI")
local tasks=require("Modules.CraftingTasks")
local M={}
function M.Open(build,raw,state,targets,requirements,requiredGroups,current,saved,settings)
	local controls={};local width=math.min(960,main.screenW-40);local height=math.min(660,main.screenH-60)
	local model=sim.model(raw);local workbench=require("Modules.CraftingWorkbench");local entries={};local recipes={};local chartResults
	local function add(label,recipe,priceKey) recipes[#recipes+1]={label=label,recipe=recipe,priceKey=priceKey};entries[#entries+1]={label=label,val=#recipes} end
	local selected=copyTable(current);selected.maxAttempts=math.min(2000,settings.budget);selected.untilTargets=#targets>0 and copyTable(targets) or nil;selected.untilRequiredGroups=selected.untilTargets and requiredGroups or nil;selected.untilRequirements=requirements and copyTable(requirements)
	add("Selected: "..(current.allflame and "Allflame " or "")..workbench.actionLabel(current,model),{steps={selected},targets=copyTable(targets),requirements=requirements and copyTable(requirements),requiredGroups=requiredGroups},sim.priceKey(selected))
	local savedIndex
	if saved then local recipe=copyTable(saved);recipe.targets=copyTable(targets);recipe.requirements=requirements and copyTable(requirements);recipe.requiredGroups=requiredGroups;add("Saved recipe",recipe);savedIndex=#recipes end
	local library,origins={},{}
	local function addAlternative(alternative)
		local recipe=copyTable(alternative.recipe);recipe.targets=copyTable(targets);recipe.requirements=requirements and copyTable(requirements);recipe.requiredGroups=requiredGroups
		add("Saved: "..alternative.name,recipe);local entry={name=alternative.name,index=#recipes,recipe=copyTable(alternative.recipe)};library[#library+1]=entry;origins[#recipes]=entry
	end
	for _,alternative in ipairs(settings.alternatives or {}) do addAlternative(alternative) end
	for _,method in ipairs({"alchemy","chaos","alteration","essence","fossil","harvest_reforge"}) do
		local available=workbench.available(method,state,model)
		if available then
			local ok,options=pcall(sim.actionOptions,model,state,method)
			if ok then
				if method=="alchemy" or method=="chaos" or method=="alteration" then options={{action={method=method}}} end
				for _,option in ipairs(options) do
					local action=copyTable(option.action);action.maxAttempts=math.min(2000,settings.budget);action.untilTargets=#targets>0 and copyTable(targets) or nil;action.untilRequiredGroups=action.untilTargets and requiredGroups or nil;action.untilRequirements=requirements and copyTable(requirements)
					local label=workbench.actionLabel(action,model)
					add(label,{steps={action},targets=copyTable(targets),requirements=requirements and copyTable(requirements),requiredGroups=requiredGroups},sim.priceKey(action))
				end
			end
		end
	end
	ui.label(controls,"intro",16,26,"Compare recipes with the same item, targets, seed, trials and action budget.",14)
	ui.label(controls,"hint",16,50,"Prices in "..settings.currency..". Saved quotes apply to every route; search the route dropdown to find a craft.",14)
	-- Three controls per page keep the dialog compact; the route list itself
	-- has no fixed count limit. Each route retains overrides per selected action.
	local rows,page,previous={},1,{};local customCount=0
	for i=1,3 do rows[i]={choice=math.min(i,#entries),prices={}} end
	local function position(slot) return (page-1)*3+slot end
	local function invalidate()
		chartResults=nil
		if controls.results then controls.results.list=ui.rows({"Routes changed. Run the comparison to update results."},width-62) end
	end
	local function savePage()
		for slot=1,3 do local row=rows[position(slot)];if row then
			local choice=controls["route"..slot]:GetSelValueByKey("val")
			row.choice=choice;row.prices[choice]=controls["price"..slot].buf
		end end
	end
	local function showPage()
		page=math.max(1,math.min(page,math.ceil(#rows/3)))
		for slot=1,3 do local row=rows[position(slot)];if row then
			controls["route"..slot]:SelByValue(row.choice,"val");previous[slot]=row.choice
			controls["price"..slot]:SetText(row.prices[row.choice] or "")
		end end
	end
	for i=1,3 do
		local slot=i;local canKeep=settings.keepRecipe~=nil;local canAlternative=settings.keepAlternative~=nil
		controls["route"..slot]=new("DropDownControl"):DropDownControl(ui.anchor,{16,82+(slot-1)*38,width-(canAlternative and 455 or canKeep and 385 or 316),26},entries)
		controls["price"..slot]=new("EditControl"):EditControl(ui.anchor,{width-(canAlternative and 427 or canKeep and 357 or 288),82+(slot-1)*38,canKeep and 135 or 160,26},"","Action override",nil,16)
		local drop,input=controls["route"..slot],controls["price"..slot]
		drop.shown=function() return rows[position(slot)]~=nil end;input.shown=drop.shown
		drop.enabled=function() return not tasks.job end;input.changeFunc=invalidate
		drop.selFunc=function()
			local row=rows[position(slot)];row.prices[previous[slot]]=input.buf
			previous[slot]=drop:GetSelValueByKey("val");row.choice=previous[slot];input:SetText(row.prices[row.choice] or "");invalidate()
		end
		input.enabled=function() local row=rows[position(slot)];return not tasks.job and row and recipes[drop:GetSelValueByKey("val")].priceKey~=nil end
		input.tooltipText="Override the complete price of one selected action. Saved and custom recipes use their ingredient prices."
		controls["edit"..slot]=new("ButtonControl"):ButtonControl(ui.anchor,{width-120,82+(slot-1)*38,60,26},"Edit",function()
			savePage();local row=rows[position(slot)];local source=recipes[row.choice]
			require("Classes.CraftingRecipeControl").Open(source.recipe,current,function(recipe)
				customCount=customCount+1
				add("Custom recipe "..customCount.." ("..#recipe.steps.." steps)",copyTable(recipe))
				origins[#recipes]=origins[row.choice]
				row.choice=#recipes;row.prices[row.choice]=""
				for index=1,3 do controls["route"..index]:ResetSearch() end
				showPage();invalidate()
			end,sim.context(model,state))
		end)
		controls["edit"..slot].shown=drop.shown;controls["edit"..slot].enabled=function() return not tasks.job end
		controls["edit"..slot].tooltipText="Create a separate comparison recipe from this route. Use Keep to save one to the project."
		if canKeep then
			controls["keep"..slot]=new("ButtonControl"):ButtonControl(ui.anchor,{width-(canAlternative and 284 or 214),82+(slot-1)*38,86,26},"Keep",function()
				savePage();local row=rows[position(slot)];local recipe=copyTable(recipes[row.choice].recipe);recipe.initialState=copyTable(state)
				local function keep()
					local ok,message=pcall(settings.keepRecipe,recipe)
					if not ok then main:OpenMessagePopup("Keep recipe",ui.errorText(message));return end
					if savedIndex then recipes[savedIndex].recipe=copyTable(recipe)
					else add("Saved recipe",copyTable(recipe));savedIndex=#recipes end
					for index=1,3 do controls["route"..index]:ResetSearch() end
					invalidate()
					main:OpenMessagePopup("Recipe kept","Saved to this crafting project. Use build Save to persist.\nComparison-only action overrides are not saved; use Resource prices.")
				end
				if settings.hasSavedRecipe and settings.hasSavedRecipe() then
					main:OpenConfirmPopup("Replace saved recipe","Replace this project's saved recipe with the selected route?\nWritten guide steps stay unchanged. Use build Save to persist.","Replace",keep)
				else keep() end
			end)
			controls["keep"..slot].shown=drop.shown;controls["keep"..slot].enabled=function() return not tasks.job end
			controls["keep"..slot].tooltipText="Keep this route as the project's saved recipe, starting from the compared item. Resource prices remain separate."
		end
		if canAlternative then
			controls["alternative"..slot]=new("ButtonControl"):ButtonControl(ui.anchor,{width-190,82+(slot-1)*38,62,26},"Save +",function()
				savePage();local row=rows[position(slot)];local recipe=copyTable(recipes[row.choice].recipe);recipe.initialState=copyTable(state)
				local origin=origins[row.choice];if origin and origin.removed then origin=nil end
				local popup={};local w,h=math.min(620,main.screenW-40),190;local number=1;local exists={}
				for _,entry in ipairs(library) do exists[entry.name:lower()]=true end
				while exists[("Alternative "..number):lower()] do number=number+1 end
				ui.label(popup,"intro",16,28,"Name this recipe for the current crafting project.",14)
				popup.name=new("EditControl"):EditControl(ui.anchor,{16,56,w-32,28},"Alternative "..number,origin and "New copy name" or "Recipe name",nil,120)
				ui.label(popup,"note",16,96,"Resource prices are shared; comparison overrides are not saved.",14)
				popup.save=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-48,150,28},"Save alternative",function()
					local ok,result=pcall(settings.keepAlternative,popup.name.buf,recipe)
					if not ok then main:OpenMessagePopup("Save alternative",ui.errorText(result));return end
					addAlternative(result);row.choice=#recipes;row.prices[row.choice]=""
					for index=1,3 do controls["route"..index]:ResetSearch() end;showPage();invalidate()
					main:ClosePopup();main:OpenMessagePopup("Recipe kept","Alternative saved to this project. Use build Save to persist.")
				end)
				if origin and settings.updateAlternative then
					ui.label(popup,"updateHint",16,118,"",12);popup.updateHint.label=function() return "^7Update saved: "..ui.fit(origin.name,w-144,12) end
					popup.update=new("ButtonControl"):ButtonControl(ui.anchor,{178,h-48,160,28},"Update saved",function()
						main:OpenConfirmPopup("Update alternative","Replace the saved alternative with this route?\nThe comparison's item state and targets will be saved.","Update",function()
							local ok,result=pcall(settings.updateAlternative,origin.name,recipe)
							if not ok then main:OpenMessagePopup("Update alternative",ui.errorText(result));return end
							origin.recipe=copyTable(result.recipe)
							local comparison=copyTable(result.recipe);comparison.targets=copyTable(targets);comparison.requirements=requirements and copyTable(requirements);comparison.requiredGroups=requiredGroups
							recipes[origin.index].recipe=comparison;row.choice=origin.index;row.prices[row.choice]=""
							for index=1,3 do controls["route"..index]:ResetSearch() end;showPage();invalidate()
							main:ClosePopup();main:OpenMessagePopup("Recipe kept","Alternative updated. Use build Save to persist.")
						end)
					end)
					popup.update.tooltipText="Replace "..origin.name.." with this route; the recipe name stays the same."
				end
				popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{w-136,h-48,120,28},"Cancel",function() main:ClosePopup() end)
				ui.style(popup,{save=true});main:OpenPopup(w,h,"Save alternative recipe",popup,nil,"name","close")
			end)
			controls["alternative"..slot].shown=drop.shown;controls["alternative"..slot].enabled=function() return not tasks.job end
			controls["alternative"..slot].tooltipText="Save this route as a named alternative without replacing the project's primary recipe."
		end
		controls["remove"..slot]=new("ButtonControl"):ButtonControl(ui.anchor,{width-52,82+(slot-1)*38,36,26},"X",function()
			savePage();table.remove(rows,position(slot));showPage();invalidate()
		end)
		controls["remove"..slot].shown=drop.shown;controls["remove"..slot].enabled=function() return #rows>1 and not tasks.job end
		controls["remove"..slot].tooltipText="Remove this route from the comparison."
	end
	showPage()
	controls.addRoute=new("ButtonControl"):ButtonControl(ui.anchor,{16,194,140,26},"Add route",function()
		savePage();rows[#rows+1]={choice=(#rows%#entries)+1,prices={}};page=math.ceil(#rows/3);showPage();invalidate()
	end)
	controls.addRoute.enabled=function() return not tasks.job end
	controls.previousPage=new("ButtonControl"):ButtonControl(ui.anchor,{166,194,80,26},"Prev",function() savePage();page=page-1;showPage() end)
	controls.nextPage=new("ButtonControl"):ButtonControl(ui.anchor,{254,194,80,26},"Next",function() savePage();page=page+1;showPage() end)
	controls.previousPage.enabled=function() return page>1 end
	controls.nextPage.enabled=function() return page<math.ceil(#rows/3) end
	ui.label(controls,"page",348,200,"",14);controls.page.label=function() return "^7Routes "..((page-1)*3+1).."-"..math.min(page*3,#rows).." of "..#rows end
	if settings.renameAlternative and settings.removeAlternative then
		controls.manageAlternatives=new("ButtonControl"):ButtonControl(ui.anchor,{width-156,194,140,26},"Saved routes",function()
			local popup={};local selected;local w,h=math.min(620,main.screenW-40),math.min(440,main.screenH-60)
			popup.list=new("TextListControl"):TextListControl(ui.anchor,{16,28,w-32,h-156},nil,{})
			popup.name=new("EditControl"):EditControl(ui.anchor,{16,h-112,w-32,26},"","Recipe name",nil,120)
			local function refreshList()
				local lines={};for index,entry in ipairs(library) do lines[#lines+1]={height=25,textSize=14,entry=index,selected=index==selected,"^7"..ui.fit(entry.name,w-68,14)} end
				if #lines==0 then lines[1]={height=25,textSize=14,"^7No saved alternatives yet."} end;popup.list.list=lines
			end
			popup.list.onClick=function(row) local index=row and row.line and row.line.entry;if index then selected=index;popup.name:SetText(library[index].name);refreshList() end end
			popup.rename=new("ButtonControl"):ButtonControl(ui.anchor,{16,h-70,140,28},"Rename",function()
				local entry=library[selected];local ok,name=pcall(settings.renameAlternative,entry.name,popup.name.buf)
				if not ok then main:OpenMessagePopup("Rename recipe",ui.errorText(name));return end
				entry.name=name;entries[entry.index].label="Saved: "..name;recipes[entry.index].label=entries[entry.index].label
				for index=1,3 do controls["route"..index]:ResetSearch() end;popup.name:SetText(name);refreshList();invalidate()
			end)
			popup.rename.enabled=function() return selected~=nil and library[selected]~=nil end
			popup.remove=new("ButtonControl"):ButtonControl(ui.anchor,{168,h-70,140,28},"Remove",function()
				local entry=library[selected]
				main:OpenConfirmPopup("Remove alternative","Remove this saved alternative from the project?\nAny route already selected remains in this comparison.","Remove",function()
					local ok,message=pcall(settings.removeAlternative,entry.name)
					if not ok then main:OpenMessagePopup("Remove recipe",ui.errorText(message));return end
					entries[entry.index].label="Unsaved: "..entry.name;recipes[entry.index].label=entries[entry.index].label
					entry.removed=true;table.remove(library,selected);selected=nil;popup.name:SetText("");for index=1,3 do controls["route"..index]:ResetSearch() end;refreshList();invalidate()
				end)
			end)
			popup.remove.enabled=popup.rename.enabled
			popup.use=new("ButtonControl"):ButtonControl(ui.anchor,{320,h-70,140,28},"Make primary",function()
				local entry=library[selected];local recipe=copyTable(entry.recipe)
				local function keep()
					local ok,message=pcall(settings.keepRecipe,recipe)
					if not ok then main:OpenMessagePopup("Make primary",ui.errorText(message));return end
					local comparison=copyTable(recipe);comparison.targets=copyTable(targets);comparison.requirements=requirements and copyTable(requirements);comparison.requiredGroups=requiredGroups
					if savedIndex then recipes[savedIndex].recipe=comparison else add("Saved recipe",comparison);savedIndex=#recipes end
					for index=1,3 do controls["route"..index]:ResetSearch() end;invalidate()
					main:OpenMessagePopup("Recipe kept","Primary recipe updated with its saved starting state.\nUse build Save to persist.")
				end
				if settings.hasSavedRecipe and settings.hasSavedRecipe() then main:OpenConfirmPopup("Replace saved recipe","Replace the primary recipe with this alternative?\nIts saved starting state and targets will be used.","Replace",keep) else keep() end
			end)
			popup.use.enabled=popup.rename.enabled
			popup.close=new("ButtonControl"):ButtonControl(ui.anchor,{w-136,h-70,120,28},"Close",function() main:ClosePopup() end)
			refreshList();ui.style(popup);main:OpenPopup(w,h,"Saved alternative recipes",popup,nil,nil,"close")
		end)
		controls.manageAlternatives.enabled=function() return not tasks.job end
	end
	controls.results=new("TextListControl"):TextListControl(ui.anchor,{16,230,width-32,height-304},nil,ui.rows({"Add routes and run the comparison.","Missing prices remain unknown. Sampling intervals do not measure model uncertainty."},width-62))
	controls.run=new("ButtonControl"):ButtonControl(ui.anchor,{16,height-48,180,28},"Compare recipes",function()
		local ok,captured=pcall(function()
			savePage();local routes={}
			for _,row in ipairs(rows) do
				local route=copyTable(recipes[row.choice]);local price=row.prices[row.choice] or ""
				if route.priceKey and price~="" then
					route.price=assert(tonumber(price),"Enter a valid action price")
					require("Modules.CraftingPrices").actionOverride(route.priceKey,route.price)
				end
				routes[#routes+1]=route
			end
			return routes
		end)
		if not ok then main:OpenMessagePopup("Compare recipes",ui.errorText(captured));return end
		chartResults=nil
		local job=tasks.start(build,function(checkpoint)
			local results={}
			for i,route in ipairs(captured) do
				local prices=settings.prices and copyTable(settings.prices)
				local actionPrices=require("Modules.CraftingPrices").actionOverride(route.priceKey,route.price)
				local options={initialState=copyTable(state),trials=settings.trials,maxActions=settings.budget,seed=settings.seed,currency=settings.currency,priceBook=settings.priceBook,prices=prices,actionPrices=actionPrices,treeVersion=settings.treeVersion,checkpoint=function(progress) checkpoint({route=i,routes=#captured,trial=progress.trial,trials=progress.trials}) end}
				local ok,result=pcall(sim.simulate,raw,route.recipe,options);results[#results+1]={label="Route "..i..": "..route.label,recipe=copyTable(route.recipe),result=ok and result or nil,error=not ok and ui.errorText(result) or nil}
			end
			return results
		end,function(results)
			chartResults=results
			local lines={"Same starting item and encounter-independent crafting model."}
			if settings.treeVersion then lines[#lines+1]="Build tree: "..(treeVersions[settings.treeVersion] and treeVersions[settings.treeVersion].display or settings.treeVersion).." (context only) | crafting data: "..tostring(sim.dataPatch).."; modifiers: "..tostring(sim.modifierPatch) end
			for _,route in ipairs(results) do
				lines[#lines+1]="";lines[#lines+1]=route.label
				if route.error then lines[#lines+1]=route.error else local r=route.result
					lines[#lines+1]=string.format("%s success | 95%% interval %s - %s | %.2f mean attempts",ui.percent(r.successChance,2),ui.percent(r.confidenceLow,2),ui.percent(r.confidenceHigh,2),r.meanActions)
					if r.meanExecutedActions then lines[#lines+1]=string.format("%.2f mean executed actions | %d failed attempts",r.meanExecutedActions,r.failedAttempts) end
					for _,warning in ipairs(r.warnings or {}) do lines[#lines+1]="Model note: "..warning.message end
					lines[#lines+1]=r.meanCost and string.format("Mean spent: %.2f %s per trial",r.meanCost,r.costCurrency) or "Cost unknown: supply every executed action's price."
					for message,count in pairs(r.transitionErrors) do lines[#lines+1]=count.." failed transitions: "..message end
				end
			end
			controls.results.list=ui.rows(lines,width-62)
		end,function(message) controls.results.list=ui.rows({ui.errorText(message)},width-62) end,function(p) controls.results.list=ui.rows({"Route "..p.route.." / "..p.routes..": trial "..p.trial.." / "..p.trials},width-62) end)
		job.owner=controls
	end)
	controls.run.enabled=function() return not tasks.job end
	controls.charts=new("ButtonControl"):ButtonControl(ui.anchor,{400,height-48,180,28},"Compare charts",function() require("Classes.CraftingChartsControl").Open(chartResults) end)
	controls.charts.enabled=function() return chartResults~=nil end
	controls.cancel=new("ButtonControl"):ButtonControl(ui.anchor,{208,height-48,180,28},"Cancel comparison",function() if tasks.job and tasks.job.owner==controls then tasks.cancel() end end);controls.cancel.enabled=function() return tasks.job and tasks.job.owner==controls end
	controls.close=new("ButtonControl"):ButtonControl(ui.anchor,{width-132,height-48,116,28},"Close",function() if tasks.job and tasks.job.owner==controls then tasks.cancel() end;main:ClosePopup() end)
	ui.style(controls,{run=true});for _,control in pairs(controls) do control.layoutAudit="crafting-comparison" end;main:OpenPopup(width,height,"Compare crafting recipes",controls,nil,nil,"close")
	return controls
end
return M
