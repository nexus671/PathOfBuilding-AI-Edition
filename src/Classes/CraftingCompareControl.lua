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
		local slot=i;local canKeep=settings.keepRecipe~=nil
		controls["route"..slot]=new("DropDownControl"):DropDownControl(ui.anchor,{16,82+(slot-1)*38,width-(canKeep and 385 or 316),26},entries)
		controls["price"..slot]=new("EditControl"):EditControl(ui.anchor,{width-(canKeep and 357 or 288),82+(slot-1)*38,canKeep and 135 or 160,26},"","Action override",nil,16)
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
				row.choice=#recipes;row.prices[row.choice]=""
				for index=1,3 do controls["route"..index]:ResetSearch() end
				showPage();invalidate()
			end,sim.context(model,state))
		end)
		controls["edit"..slot].shown=drop.shown;controls["edit"..slot].enabled=function() return not tasks.job end
		controls["edit"..slot].tooltipText="Create a separate comparison recipe from this route. Use Keep to save one to the project."
		if canKeep then
			controls["keep"..slot]=new("ButtonControl"):ButtonControl(ui.anchor,{width-214,82+(slot-1)*38,86,26},"Keep",function()
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
