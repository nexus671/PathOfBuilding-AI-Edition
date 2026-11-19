-- Deterministic unique-item recipes use item text, not ordinary affix states.
local M={}
local supported={quality=true,beast_max_links=true,omen_connections=true,socket_white_bench=true,socket_bench=true}
local fields={method=true,count=true,linked=true,maxAttempts=true,untilRequirements=true,onSuccess=true,onFailure=true,onFailureAction=true,recoveryNotes=true}
function M.stepReason(step)
	if not supported[step.method] then return "This unique recipe action is not supported: "..tostring(step.method) end
	if step.method~="socket_bench" and (step.count~=nil or step.linked~=nil) then return "This unique recipe action does not accept socket options" end
	for key in pairs(step) do if not fields[key] then return "This unique recipe option is not supported: "..tostring(key) end end
end
local function integer(value,low,high,label)
	assert(type(value)=="number" and value==math.floor(value) and value>=low and value<=high,"Invalid "..label)
	return value
end
local function quantiles(value)
	local result={};for _,percent in ipairs({10,25,50,75,90,95,99}) do result["p"..percent]=value end;return result
end
function M.simulate(sim,raw,recipe,options)
	options=options or {};recipe=sim.validateRecipe(recipe)
	assert(not recipe.initialState and not options.initialState,"Unique recipes continue from item text, not an ordinary crafting state")
	assert(#recipe.targets==0,"Modifier-identity targets are not yet supported for unique items")
	local unique=require("Modules.CraftingUniqueQuality");local start=unique.inspect(raw)
	for _,step in ipairs(recipe.steps) do
		local reason=M.stepReason(step);assert(not reason,reason)
		if step.untilRequirements then unique.matches(raw,step.untilRequirements) end
	end
	unique.matches(raw,recipe.requirements)
	local trials=integer(options.trials or 200,1,2000,"trial count")
	local maxActions=integer(options.maxActions or 100,1,2000,"action budget")
	assert(trials*maxActions<=20000,"Use at most 20000 total budgeted actions per simulation")
	local seed=integer(options.seed or 104729,1,2147483646,"seed")
	local retain=integer(options.retainSuccesses or 0,0,100,"retained successful items")
	local baseCost=options.baseCost or 0;assert(type(baseCost)=="number" and baseCost==baseCost and baseCost>=0 and baseCost<=1e12,"Invalid starting item cost")
	for _,key in ipairs({"prices","actionPrices"}) do if options[key]~=nil then assert(type(options[key])=="table","Invalid supplied prices") end end
	local suppliedPrices=options.prices and next(options.prices)~=nil or false
	local suppliedActions=options.actionPrices and next(options.actionPrices)~=nil or false
	local pricing=require("Modules.CraftingPrices");local model={item=start}
	local book=options.priceBook and pricing.validate(options.priceBook) or nil
	local currency=options.currency or book and book.currency
	assert(baseCost==0 or type(currency)=="string" and currency:match("%S"),"Name the currency for the starting item cost")
	if suppliedPrices or suppliedActions then assert(type(currency)=="string" and currency:match("%S"),"Specify a common currency for supplied prices") end
	for key,value in pairs(options.prices or {}) do assert(type(key)=="string" and type(value)=="number" and value==value and value>=0 and value<=1e12,"Invalid currency price") end
	local actionCount=0
	for key,value in pairs(options.actionPrices or {}) do
		assert(type(key)=="string" and #key>0 and #key<=1024 and not key:find("[%c]") and type(value)=="number" and value==value and value>=0 and value<=1e12,"Invalid action price")
		actionCount=actionCount+1
	end
	assert(actionCount<=100,"Use at most 100 action price overrides")
	local prices=(book or options.prices) and pricing.forSimulation(book,currency,model,options.prices) or nil
	local current,at,actions,executed,cost=raw,1,0,0,baseCost
	local spent,missing,errors,usage,routes={},{},{},{},{}
	local recovery={restarts=0,stopped=0,salvaged=0};local rejected=false;local actionPriceUses=0
	local function target(text,requirements)
		return (not recipe.rarity or recipe.rarity=="UNIQUE") and unique.matches(text,requirements)
	end
	while at<=#recipe.steps and actions<maxActions and (options.forceFirstAction and actions==0 or not target(current,recipe.requirements)) do
		if options.checkpoint then options.checkpoint({trial=1,trials=trials,actions=actions,successes=0}) end
		local step=recipe.steps[at];local route=routes[at] or {visits=0,success=0,failure=0,executed=0};routes[at]=route;route.visits=route.visits+1
		local success=false
		for _=1,(step.maxAttempts or 1) do
			if actions>=maxActions then break end
			if options.checkpoint then options.checkpoint({trial=1,trials=trials,actions=actions,successes=0}) end
			actions=actions+1
			local action={method=step.method};if step.method=="socket_bench" then action.count=step.count;action.linked=step.linked end
			local ok,result=pcall(sim.perform,current,action,seed)
			if not ok then local message=tostring(result):match("[^:]+$") or tostring(result);errors[message]=(errors[message] or 0)+1;rejected=true;break end
			current=result.itemText;executed=executed+1;route.executed=route.executed+1
			for key,amount in pairs(result.components) do
				local canonical=pricing.key(key,model);local entry=usage[canonical]
				if not entry then local name,_,kind=pricing.describe(canonical,model,step);entry={key=canonical,name=name,kind=kind=="Whole action" and "service" or "resource",amount=0};usage[canonical]=entry end
				entry.amount=entry.amount+amount
			end
			local override=options.actionPrices and options.actionPrices[step.method]
			local service=prices and prices[step.method]~=nil and step.method or nil
			if override~=nil then actionPriceUses=actionPriceUses+1 end
			local components=(override~=nil or service) and {[override~=nil and step.method or service]=1} or result.components
			for key,amount in pairs(components) do
				spent[key]=(spent[key] or 0)+amount;local price=override~=nil and override or prices and prices[key]
				if price~=nil then cost=cost+price*amount else missing[key]=true end
			end
			if target(current,recipe.requirements) or not step.untilRequirements or unique.matches(current,step.untilRequirements) then success=true;break end
		end
		route[success and "success" or "failure"]=route[success and "success" or "failure"]+1
		if not success and step.onFailureAction=="restart" then
			if actions<maxActions then recovery.restarts=recovery.restarts+1;current=raw;cost=cost+baseCost end;at=1
		elseif not success and (step.onFailureAction=="stop" or step.onFailureAction=="salvage") then
			local key=step.onFailureAction=="stop" and "stopped" or "salvaged";recovery[key]=recovery[key]+1;at=#recipe.steps+1
		else at=success and (step.onSuccess or at+1) or (step.onFailure or at+1) end
	end
	local hit=(not options.forceFirstAction or executed>0) and target(current,recipe.requirements);assert(executed>0 or hit,next(errors) or "Recipe could not execute a supported action")
	local successes=hit and trials or 0
	local resources={};for _,entry in pairs(usage) do entry.meanPerTrial=entry.amount;entry.amount=entry.amount*trials;resources[#resources+1]=entry end;table.sort(resources,function(a,b) return a.key<b.key end)
	for key,value in pairs(spent) do spent[key]=value*trials end
	for key,value in pairs(errors) do errors[key]=value*trials end
	for _,route in pairs(routes) do for key,value in pairs(route) do route[key]=value*trials end end
	for key,value in pairs(recovery) do recovery[key]=value*trials end
	local retained={};if hit then for trial=1,math.min(retain,trials) do retained[#retained+1]={trial=trial,actions=actions,cost=not next(missing) and cost or nil,itemText=current} end end
	local result={uniqueCrafting=true,exactFor="Supported deterministic unique-item recipe",sampled=false,trials=trials,successes=successes,successChance=hit and 100 or 0,confidenceLow=hit and 100 or 0,confidenceHigh=hit and 100 or 0,seed=seed,maxActions=maxActions,
		meanActions=actions,meanExecutedActions=executed,failedAttempts=(actions-executed)*trials,failedTransitionTrials=rejected and trials or 0,currencySpent=spent,resourceUsage=resources,unpriced=missing,transitionErrors=errors,
		warnings={{code="unique_crafting_scope",message="Only supported deterministic unique actions and listed item goals are modeled. Continue using item text, not an ordinary affix state."}},limitations={"Unique modifier-identity targets and other crafting methods are not modeled."},sampleSuccess=hit,sampleItem=current,
		engineVersion=2,dataPatch=sim.dataPatch,sourceVersion=launch.versionNumber,costCurrency=currency or "supplied price units",baseCost=baseCost,retainedSuccesses=retained,retentionLimit=retain,
		actionDistribution={{actions=actions,trials=trials,successes=successes}},executedActionDistribution={{actions=executed,trials=trials,successes=successes}},successfulActionQuantiles=hit and quantiles(actions) or nil,routeCounts=routes,budgetExhausted=not hit and at<=#recipe.steps and actions>=maxActions and trials or 0,
		destroyedTrials=0,uniqueTrials=trials,uniqueDistribution={{name=start.title,trials=trials,successes=successes}},recovery=recovery,stepPriceKeys={},priceOverridesSupplied=suppliedPrices or suppliedActions,resourcePriceOverridesSupplied=suppliedPrices,actionPriceOverridesSupplied=suppliedActions,actionPriceOverridesApplied=actionPriceUses*trials}
	if rejected then result.warnings[#result.warnings+1]={code="rejected_model_actions",message=string.format("All %d modeled trials included a rejected action. Rejected attempts count toward the action budget and follow failure routes, but are not charged resources. Review the transition errors.",trials)} end
	for i,step in ipairs(recipe.steps) do result.stepPriceKeys[i]={step=i,method=step.method,priceKey=step.method} end
	if not next(missing) then result.meanCost=cost;result.costPerSuccess=hit and cost or nil;result.spendingQuantiles=quantiles(cost);result.successfulSpendingQuantiles=hit and quantiles(cost) or nil;result.costDistribution={{cost=cost,trials=trials,successes=successes}} end
	if book then result.priceSource=book.source;result.priceQuotedAt=book.quotedAt end
	return sim.withTreeContext(result,options.treeVersion)
end
return M
