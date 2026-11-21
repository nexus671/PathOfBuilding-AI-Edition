-- Experimental model for an observed Rog prefix or suffix reroll offer.
local R={}
local tiers={"lesser","greater","grand","exceptional"}
local artifacts={}
for index,tier in ipairs(tiers) do artifacts[tier]="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_"..index end

function R.validate(craft)
	local removal=craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two"
	assert(craft.rogOperation==nil or craft.rogOperation=="reroll" or craft.rogOperation=="add" or removal,"Choose a supported Rog offer")
	if removal then assert(craft.rogSide==nil and craft.rogAttempts==nil,"Lowest-level removal does not use a side or attempt count")
	else
		assert(craft.rogSide=="Prefix" or craft.rogSide=="Suffix","Choose prefixes or suffixes")
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

function R.components(craft)
	R.validate(craft)
	if craft.artifactCost==nil then return {["rog:observed_artifacts"]=1} end
	local result={}
	for tier,amount in pairs(craft.artifactCost) do if amount>0 then result[artifacts[tier]]=amount end end
	return result
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
function R.extend(M,api)
	M.methods[#M.methods+1]="rog_reroll";M.labels.rog_reroll="Rog: observed modifier offer (experimental)";table.sort(M.methods)
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
		assert(not (flags.prefixes or flags.suffixes or flags.attack or flags.caster or flags.explicitAttack or flags.explicitCaster or M.hasPartialLock(model,input)),"Rog interactions with meta modifiers are not modeled")
		for _,entry in ipairs(input.affixes) do assert(not entry.fractured and not entry.crafted,"Rog interactions with fractured or crafted modifiers are not modeled") end
		if craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two" then return R.removeLowest(model,input,craft,random) end
		return R.reroll(M,model,input,craft,random)
	end
	function M.priceKey(craft)
		if craft.method~="rog_reroll" then return priceKey(craft) end
		local removal=craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two"
		local fields=removal and {"rog_reroll",craft.rogOperation} or {"rog_reroll",tostring(craft.rogSide),tostring(craft.rogAttempts)}
		if craft.rogOperation=="add" then fields[#fields+1]="add" end
		for _,tier in ipairs(tiers) do fields[#fields+1]=craft.artifactCost and tostring(craft.artifactCost[tier] or 0) or "unknown" end
		return table.concat(fields,":")
	end
	function M.components(craft,state,model)
		if craft.method=="rog_reroll" then return R.components(craft) end
		return components(craft,state,model)
	end
	M.limits[#M.limits+1]="Experimental Rog modifier offers use observed prices. Ordinary affix weights, side-reroll count preservation, average modifier-level ranking and first-on-tie selection are assumptions; offer generation and special interactions are not modeled."
end
return R
