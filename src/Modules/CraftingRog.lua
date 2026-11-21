-- Experimental model for an observed Rog prefix or suffix reroll offer.
local R={}
local tiers={"lesser","greater","grand","exceptional"}
local artifacts={}
for index,tier in ipairs(tiers) do artifacts[tier]="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_"..index end

function R.validate(craft)
	local removal=craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two"
	local highest=craft.rogOperation=="upgrade_highest" or craft.rogOperation=="upgrade_highest_all"
	local fixed=craft.rogOperation=="fill" or craft.rogOperation=="set_quality" or craft.rogOperation=="upgrade" or highest
	local sockets=craft.rogOperation=="socket_count" or craft.rogOperation=="socket_links"
	local valuesOne=craft.rogOperation=="values_one"
	local valuesSide=craft.rogOperation=="values_side"
	local valuesImplicit=craft.rogOperation=="values_implicit"
	if sockets then
		assert(craft.rogSocketRolls==10 or craft.rogSocketRolls==20 or craft.rogSocketRolls==30 or craft.rogSocketRolls==50 or craft.rogSocketRolls==100,"Choose 10, 20, 30, 50 or 100 socket rerolls")
	else assert(craft.rogSocketRolls==nil,"Socket reroll count applies only to a socket offer") end
	if craft.rogOperation=="upgrade" then assert(type(craft.count)=="number" and craft.count==math.floor(craft.count) and craft.count>=1 and craft.count<=6,"Choose 1 to 6 modifiers to upgrade") end
	if craft.rogOperation=="upgrade_highest" then assert(craft.count==1 or craft.count==2,"Choose one or two modifiers to upgrade") end
	if craft.rogOperation=="upgrade_highest_all" then assert(craft.count==nil,"All-modifier offer does not use a count") end
	assert(craft.rogOperation==nil or craft.rogOperation=="reroll" or craft.rogOperation=="add" or removal or fixed or sockets or valuesOne or valuesSide or valuesImplicit,"Choose a supported Rog offer")
	if removal or fixed or sockets then assert(craft.rogSide==nil and craft.rogAttempts==nil,"This offer does not use a side or attempt count")
	else
		if valuesOne or valuesImplicit then assert(craft.rogSide==nil,"This value offer does not use a side")
		else assert(craft.rogSide=="Prefix" or craft.rogSide=="Suffix","Choose prefixes or suffixes") end
		assert(craft.rogAttempts==1 or craft.rogAttempts==3 or craft.rogAttempts==5,"Choose 1, 3 or 5 attempts")
	end
	assert(not craft.allflame,"Allflame cannot be used with Rog")
	if craft.artifactCost~=nil then
		assert(type(craft.artifactCost)=="table","Invalid observed artifact cost")
		for key,value in pairs(craft.artifactCost) do
			assert(artifacts[key] and type(value)=="number" and value==math.floor(value) and value>=0 and value<=1000000000,"Invalid observed artifact cost")
		end
	end
end

-- Ties are selected uniformly, an assumption until verified in game.
function R.removeLowest(model,input,craft,random)
	local count=craft.rogOperation=="remove_lowest_two" and 2 or 1
	assert(#input.affixes>=count,"Not enough modifiers for this offer")
	local result=copyTable(input)
	for _=1,count do
		local lowest,choices=nil,{}
		for index,entry in ipairs(result.affixes) do
			local level=assert(assert(model.byId[entry.id],"Modifier is unavailable").level,"Modifier level is unavailable")
			if not lowest or level<lowest then lowest=level;choices={} end
			if level==lowest then choices[#choices+1]=index end
		end
		table.remove(result.affixes,choices[math.floor(random()*#choices)+1])
	end
	return result
end

-- Enumerate removal sets, merging different orders that reach the same item.
-- The probabilities are exact only under the stated uniform tie assumption.
function R.removalOutcomes(model,input,craft)
	local count=craft.rogOperation=="remove_lowest_two" and 2 or 1
	assert(#input.affixes>=count,"Not enough modifiers for this offer")
	local remaining={};for index in ipairs(input.affixes) do remaining[index]=index end
	local outcomes,byKey={},{}
	local function visit(indices,removed,draws,probability)
		if #removed==count then
			local sorted=copyTable(removed);table.sort(sorted);local key=table.concat(sorted,",");local entry=byKey[key]
			if entry then entry.probability=entry.probability+probability;return end
			local labels={};for _,index in ipairs(sorted) do labels[#labels+1]=table.concat(model.byId[input.affixes[index].id]," / ") end
			entry={draws=copyTable(draws),probability=probability,text="Remove: "..table.concat(labels,"; ")};byKey[key]=entry;outcomes[#outcomes+1]=entry;return
		end
		local lowest,choices=nil,{}
		for position,index in ipairs(indices) do
			local level=assert(assert(model.byId[input.affixes[index].id],"Modifier is unavailable").level,"Modifier level is unavailable")
			if not lowest or level<lowest then lowest=level;choices={} end
			if level==lowest then choices[#choices+1]=position end
		end
		for choice,position in ipairs(choices) do
			local nextIndices=copyTable(indices);local index=table.remove(nextIndices,position)
			removed[#removed+1]=index;draws[#draws+1]=(choice-0.5)/#choices
			visit(nextIndices,removed,draws,probability/#choices)
			removed[#removed]=nil;draws[#draws]=nil
		end
	end
	visit(remaining,{},{},1)
	return outcomes
end

function R.components(craft)
	R.validate(craft)
	if craft.artifactCost==nil then return {["rog:observed_artifacts"]=1} end
	local result={}
	for tier,amount in pairs(craft.artifactCost) do if amount>0 then result[artifacts[tier]]=amount end end
	return result
end

-- This checks the current item without consuming random numbers. It does not
-- promise that every later weighted roll has a legal continuation.
function R.readiness(M,model,input,craft)
	if input.rarity~="MAGIC" and input.rarity~="RARE" then return end
	if craft.rogOperation=="socket_count" or craft.rogOperation=="socket_links" then
		return M.methodReason(model,input,craft.rogOperation=="socket_count" and "jeweller" or "fusing")
	end
	if craft.rogOperation=="set_quality" then
		if not model.item.base.armour and not data.weaponTypeInfo[model.item.type] then return "This offer requires a weapon or armour." end
		return
	end
	if craft.rogOperation=="fill" then
		if #input.affixes>=M.capacities(model,input).total then return "No empty modifier slots." end
		local _,total=M.pool(model,input);if total<=0 then return "No legal modifier can be added." end
		return
	end
	if craft.rogOperation=="values_implicit" then
		if not input.implicits and #(model.item.implicitModLines or {})==0 then return "This item has no supported implicit to reroll." end
		if not input.implicits and not model.item.synthesised and not model.blessed330 and not model.baseImplicitTemplates then return "The base implicit range could not be identified." end
		return M.methodReason(model,input,"blessed")
	end
	if craft.rogOperation=="values_one" then
		if #input.affixes==0 then return "No modifiers to reroll." end
		return
	end
	local blocked=M.blockFlags(model,input)
	if craft.rogOperation~="values_side" and (blocked.attack or blocked.caster) then return "Rog interactions with this implicit roll restriction are not modeled for this offer." end
	if craft.rogOperation=="upgrade" or craft.rogOperation=="upgrade_highest" or craft.rogOperation=="upgrade_highest_all" then
		if #input.affixes<(craft.rogOperation=="upgrade_highest_all" and 1 or craft.count) then return "Not enough modifiers to upgrade." end
		local ok,err=pcall(require("Modules.CraftingGwennen").tierChoices,model,input,true,craft.rogOperation=="upgrade_highest" or craft.rogOperation=="upgrade_highest_all")
		if not ok then return require("Modules.PlanningUI").errorText(err) end
		return
	end
	local removal=craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two"
	if removal then
		local count=craft.rogOperation=="remove_lowest_two" and 2 or 1
		if #input.affixes<count then return "Requires at least "..count.." modifier"..(count==1 and "." or "s.") end
		return
	end
	local count=0
	for _,entry in ipairs(input.affixes) do local mod=model.byId[entry.id];if mod and mod.type==craft.rogSide then count=count+1 end end
	if craft.rogOperation=="add" then
		local limits=M.capacities(model,input)
		if count>=limits[craft.rogSide] or #input.affixes>=limits.total then return "No open "..craft.rogSide:lower().." modifier slot." end
	elseif count==0 then return "No "..craft.rogSide:lower().." modifiers to reroll." end
end

-- Independent candidates start from the same item. Ordinary affix weights,
-- side-reroll count, average required-level ranking and first-on-tie are
-- provisional assumptions, not a reconstruction of Rog's server logic.
function R.reroll(M,model,input,craft,random)
	R.validate(craft)
	local side=craft.rogSide
	local count=0
	for _,entry in ipairs(input.affixes) do if assert(model.byId[entry.id],"Modifier is unavailable").type==side then count=count+1 end end
	local adding=craft.rogOperation=="add"
	if adding then assert(count<M.capacities(model,input)[side] and #input.affixes<M.capacities(model,input).total,"No open "..side:lower().." modifier slot")
	else assert(count>0,"No "..side:lower().." modifiers to reroll") end
	local best,bestScore
	for _=1,craft.rogAttempts do
		local candidate=copyTable(input)
		if not adding then for index=#candidate.affixes,1,-1 do if model.byId[candidate.affixes[index].id].type==side then table.remove(candidate.affixes,index) end end end
		for _=1,adding and 1 or count do
			local pool,total={},0
			for _,entry in ipairs(M.pool(model,candidate)) do
				if model.byId[entry.id].type==side then pool[#pool+1]=entry;total=total+entry.weight end
			end
			assert(total>0,"No legal "..side:lower().." modifier can be added")
			local pick=random()*total;local selected
			for _,entry in ipairs(pool) do pick=pick-entry.weight;if pick<0 then selected=entry;break end end
			assert(selected,"Could not select a modifier")
			candidate.affixes[#candidate.affixes+1]={id=selected.id,range=M.rollRange(model.byId[selected.id],random)}
		end
		local total=0
		for _,entry in ipairs(candidate.affixes) do local mod=model.byId[entry.id];if mod.type==side then total=total+assert(mod.level,"Modifier level is unavailable") end end
		local score=total/(count+(adding and 1 or 0))
		if not bestScore or score>bestScore then best,bestScore=candidate,score end
	end
	return best
end
-- Rank independent candidate rolls by their average normalized range position.
-- This is a provisional proxy: higher numeric rolls are not always more desirable.
function R.rerollValues(M,model,input,craft,random)
	R.validate(craft)
	local indices={};for index,entry in ipairs(input.affixes) do
		if craft.rogOperation=="values_one" or model.byId[entry.id].type==craft.rogSide then indices[#indices+1]=index end
	end
	assert(#indices>0,"No modifiers to reroll")
	if craft.rogOperation=="values_one" then indices={indices[math.floor(random()*#indices)+1]} end
	local best,bestScore
	for _=1,craft.rogAttempts do
		local candidate=copyTable(input);local sum,count=0,0
		for _,index in ipairs(indices) do
			local entry=candidate.affixes[index];entry.legacyLightRadius=nil;entry.range=M.rollRange(model.byId[entry.id],random)
			for _,value in ipairs(type(entry.range)=="table" and entry.range or {entry.range}) do sum=sum+value;count=count+1 end
		end
		local score=sum/count
		if not bestScore or score>bestScore then best,bestScore=candidate,score end
	end
	return best
end
function R.extend(M,api)
	M.methodChecks.rog_reroll=function(model,state)
		local flags=api.flags(model,state)
		if flags.prefixes or flags.suffixes or flags.explicitAttack or flags.explicitCaster then return "Rog interactions with meta modifiers are not modeled." end
		for _,entry in ipairs(state.affixes) do if entry.fractured or entry.crafted then return "Rog interactions with fractured or crafted modifiers are not modeled." end end
	end
	M.methods[#M.methods+1]="rog_reroll";M.labels.rog_reroll="Rog: observed offer (experimental)";table.sort(M.methods)
	local action,components,priceKey,validateRecipe=M.action,M.components,M.priceKey,M.validateRecipe
	function M.validateRecipe(recipe)
		local result=validateRecipe(recipe)
		for _,step in ipairs(result.steps) do if step.method=="rog_reroll" then R.validate(step) end end
		return result
	end
	function M.action(model,input,craft,random)
		if craft.method~="rog_reroll" then return action(model,input,craft,random) end
		R.validate(craft);model=M.context(model,input)
		assert((input.rarity=="MAGIC" or input.rarity=="RARE") and not input.destroyed and not input.corrupted and not input.mirrored and not input.veil,"Rog requires an uncorrupted magic or rare item")
		assert(model.item.type~="Flask" and model.item.type~="Tincture","Rog requires equipment or a jewel")
		local flags=api.flags(model,input)
		assert(not (flags.prefixes or flags.suffixes or flags.explicitAttack or flags.explicitCaster or M.hasPartialLock(model,input) or craft.rogOperation~="fill" and craft.rogOperation~="set_quality" and craft.rogOperation~="socket_count" and craft.rogOperation~="socket_links" and craft.rogOperation~="values_one" and craft.rogOperation~="values_side" and craft.rogOperation~="values_implicit" and (flags.attack or flags.caster)),"Rog interactions with meta modifiers are not modeled")
		for _,entry in ipairs(input.affixes) do assert(not entry.fractured and not entry.crafted,"Rog interactions with fractured or crafted modifiers are not modeled") end
		if craft.rogOperation=="values_one" or craft.rogOperation=="values_side" then
			local reason=R.readiness(M,model,input,craft);assert(not reason,reason)
			return R.rerollValues(M,model,input,craft,random)
		end
		if craft.rogOperation=="values_implicit" then
			local reason=R.readiness(M,model,input,craft);assert(not reason,reason)
			local best,bestScore
			for _=1,craft.rogAttempts do
				local candidate=action(model,input,{method="blessed"},random);local sum,count=0,0
				local function add(range)
					for _,value in ipairs(type(range)=="table" and range or {range}) do sum=sum+value;count=count+1 end
				end
				if candidate.implicits then for _,entry in ipairs(candidate.implicits) do add(entry.range) end
				elseif candidate.synthRolls then for _,entry in ipairs(candidate.synthRolls) do add(entry.range) end
				else for _,range in ipairs(candidate.baseImplicitRanges or {}) do add(range) end end
				assert(count>0,"No supported implicit values to rank")
				local score=sum/count;if not bestScore or score>bestScore then best,bestScore=candidate,score end
			end
			return best
		end
		if craft.rogOperation=="socket_count" or craft.rogOperation=="socket_links" then
			local reason=R.readiness(M,model,input,craft);assert(not reason,reason)
			return craft.rogOperation=="socket_count" and M.bestJeweller(model,input,craft.rogSocketRolls,random) or M.bestFusing(model,input,craft.rogSocketRolls,random)
		end
		if craft.rogOperation=="upgrade" or craft.rogOperation=="upgrade_highest" or craft.rogOperation=="upgrade_highest_all" then
			local count=craft.rogOperation=="upgrade_highest_all" and #input.affixes or craft.count
			assert(count>0 and #input.affixes>=count,"Not enough modifiers to upgrade")
			local choices=require("Modules.CraftingGwennen").tierChoices(model,input,true,craft.rogOperation=="upgrade_highest" or craft.rogOperation=="upgrade_highest_all");local result=copyTable(input)
			for _=1,count do
				local selected=table.remove(choices,math.floor(random()*#choices)+1);local entry=result.affixes[selected.index]
				entry.id=selected.id;entry.range=M.rollRange(model.byId[selected.id],random)
			end
			return result
		end
		if craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two" then return R.removeLowest(model,input,craft,random) end
		if craft.rogOperation=="set_quality" then
			local reason=R.readiness(M,model,input,craft);assert(not reason,reason)
			local result=copyTable(input);result.quality=20;return result
		end
		if craft.rogOperation=="fill" then
			local reason=R.readiness(M,model,input,craft);assert(not reason,reason)
			local result=copyTable(input);local maximum=M.capacities(model,result).total
			while #result.affixes<maximum do api.add(model,result,random) end
			return result
		end
		return R.reroll(M,model,input,craft,random)
	end
	function M.priceKey(craft)
		if craft.method~="rog_reroll" then return priceKey(craft) end
		local removal=craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two"
		local fields=(removal or craft.rogOperation=="fill" or craft.rogOperation=="set_quality") and {"rog_reroll",craft.rogOperation} or {"rog_reroll",tostring(craft.rogSide),tostring(craft.rogAttempts)}
		if craft.rogOperation=="add" then fields[#fields+1]="add" end
		if craft.rogOperation=="upgrade" or craft.rogOperation=="upgrade_highest" or craft.rogOperation=="upgrade_highest_all" then fields={"rog_reroll",craft.rogOperation,tostring(craft.count or "all")} end
		if craft.rogOperation=="socket_count" or craft.rogOperation=="socket_links" then fields={"rog_reroll",craft.rogOperation,tostring(craft.rogSocketRolls)} end
		if craft.rogOperation=="values_one" or craft.rogOperation=="values_side" or craft.rogOperation=="values_implicit" then fields={"rog_reroll",craft.rogOperation,tostring(craft.rogSide or "one"),tostring(craft.rogAttempts)} end
		for _,tier in ipairs(tiers) do fields[#fields+1]=craft.artifactCost and tostring(craft.artifactCost[tier] or 0) or "unknown" end
		return table.concat(fields,":")
	end
	function M.components(craft,state,model)
		if craft.method=="rog_reroll" then return R.components(craft) end
		return components(craft,state,model)
	end
	M.limits[#M.limits+1]="Experimental Rog offers use observed prices. Ordinary affix weights, side-reroll count preservation, average modifier-level ranking and first-on-tie selection are assumptions; offer generation and special interactions are not modeled."
end
return R
