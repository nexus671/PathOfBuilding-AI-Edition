-- Saved working state, distinct from a recipe and from recorded real spending.
local simulator=require("Modules.CraftingSimulator")
local M={}
function M.validate(raw,run,models)
	assert(type(run)=="table" and run.schemaVersion==1,"Unsupported crafting checkpoint")
	models=models or {}
	local function state(value)
		assert(type(value)=="table","Missing checkpoint item")
		local model=models[raw]
		if not model then model=simulator.model(raw);models[raw]=model end
		local itemModel=simulator.context(model,value)
		-- Older checkpoints predate roll provenance. Preserve their existing
		-- hypothetical values as a labelled snapshot, not as proof of a game drop.
		value=copyTable(value)
		local ok=pcall(simulator.validateLegacyRolls,itemModel,value)
		if not ok then
			local function preserve(snapshotState)
				local snapshot
				for _,entry in ipairs(snapshotState.affixes or {}) do
					if simulator.requiresRollSource(entry) and not entry.legacySource then
						snapshot=snapshot or simulator.toItem(model,snapshotState).raw;entry.legacySource=snapshot
					end
				end
			end
			preserve(value);if value.imprint then preserve(value.imprint) end
			simulator.validateLegacyRolls(itemModel,value)
		end
		-- Emulation may have created fractures since the original base was imported.
		local original=itemModel.initial.affixes;itemModel.initial.affixes=value.affixes
		local valid,result=pcall(simulator.validateState,model,value);itemModel.initial.affixes=original
		assert(valid,result)
		assert(simulator.toItem(model,result).base,"Invalid checkpoint item")
		return result
	end
	local result={schemaVersion=1,state=state(run.state),initial=state(run.initial),history={},actions={},configured={},settings={},priceOverrides={},sequence=run.sequence,targets=run.targets or {},requirements=run.requirements,requiredGroups=run.requiredGroups,page=run.page or "Emulate item",method=run.method or "alchemy",seed=run.seed or "104729"}
	assert(type(result.sequence)=="number" and result.sequence>=0 and result.sequence<=1e9 and result.sequence==math.floor(result.sequence),"Invalid craft sequence")
	for _,key in ipairs({"page","method","seed"}) do assert(type(result[key])=="string" and #result[key]<=80,"Invalid checkpoint setting") end
	for _,key in ipairs({"trials","budget","price","currency","baseCost"}) do local v=run.settings and run.settings[key];if v then assert(type(v)=="string" and #v<=80,"Invalid checkpoint setting");result.settings[key]=v end end
	for key,value in pairs(run.priceOverrides or {}) do
		assert(type(key)=="string" and #key<=1024 and type(value)=="string" and #value<=80,"Invalid saved action price")
		result.priceOverrides[key]=value
	end
	assert(type(run.history)=="table" and type(run.actions)=="table","Invalid checkpoint history")
	for _,s in ipairs(run.history) do result.history[#result.history+1]=state(s) end
	local targetRecipe=simulator.validateRecipe({steps={{method="alchemy"}},targets=result.targets,requirements=result.requirements or {minAffixes=0},requiredGroups=result.requiredGroups})
	result.targets=targetRecipe.targets
	for _,action in ipairs(run.actions) do
		result.actions[#result.actions+1]=simulator.validateRecipe({steps={action},targets={},requirements={minAffixes=0}}).steps[1]
	end
	assert(#result.history<=#result.actions,"Checkpoint history exceeds action history")
	for method,action in pairs(run.configured or {}) do
		assert(method==action.method,"Invalid configured craft")
		result.configured[method]=simulator.validateRecipe({steps={action},targets={},requirements={minAffixes=0}}).steps[1]
	end
	if run.simulationRequest then
		local ok,request=pcall(function()
			local value=run.simulationRequest
			assert(type(value)=="table" and value.raw==raw and type(value.label)=="string" and #value.label<=200 and type(value.options)=="table","Invalid saved simulation")
			assert(#require("Modules.PlanningData").encodeExact(value)<=262144,"Saved simulation is too large")
			local options=copyTable(value.options)
			for _,key in ipairs({"trials","maxActions","seed"}) do assert(type(options[key])=="number" and options[key]==math.floor(options[key]) and options[key]>=1,"Invalid saved simulation setting") end
			assert(options.trials<=2000 and options.maxActions<=2000 and options.trials*options.maxActions<=20000 and options.seed<=2147483646,"Saved simulation exceeds its limits")
			assert(type(options.initialState)=="table","Missing saved simulation item")
			options.initialState=state(options.initialState)
			if options.priceBook then options.priceBook=require("Modules.CraftingPrices").validate(options.priceBook) end
			options.checkpoint=nil
			return {raw=raw,label=value.label,recipe=simulator.validateRecipe(value.recipe),options=options}
		end)
		if ok then result.simulationRequest=request end
	end
	return result
end
return M
