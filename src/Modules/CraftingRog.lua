-- Experimental model for an observed Rog prefix or suffix reroll offer.
local R={}
local tiers={"lesser","greater","grand","exceptional"}
local artifacts={}
for index,tier in ipairs(tiers) do artifacts[tier]="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction3_"..index end

function R.validate(craft)
	assert(craft.rogSide=="Prefix" or craft.rogSide=="Suffix","Choose prefixes or suffixes")
	assert(craft.rogAttempts==1 or craft.rogAttempts==3 or craft.rogAttempts==5,"Choose 1, 3 or 5 rerolls")
	assert(not craft.allflame,"Allflame cannot be used with Rog")
	if craft.artifactCost~=nil then
		assert(type(craft.artifactCost)=="table","Invalid observed artifact cost")
		for key,value in pairs(craft.artifactCost) do
			assert(artifacts[key] and type(value)=="number" and value==math.floor(value) and value>=0 and value<=1000000000,"Invalid observed artifact cost")
		end
	end
end

function R.components(craft)
	R.validate(craft)
	if craft.artifactCost==nil then return {["rog:observed_artifacts"]=1} end
	local result={}
	for tier,amount in pairs(craft.artifactCost) do if amount>0 then result[artifacts[tier]]=amount end end
	return result
end

-- Independent candidates start from the same item. Ordinary affix weights,
-- preserved affix count, average required-level ranking and first-on-tie are
-- provisional assumptions, not a reconstruction of Rog's server logic.
function R.reroll(M,model,input,craft,random)
	R.validate(craft)
	local side=craft.rogSide
	local count=0
	for _,entry in ipairs(input.affixes) do if assert(model.byId[entry.id],"Modifier is unavailable").type==side then count=count+1 end end
	assert(count>0,"No "..side:lower().." modifiers to reroll")
	local best,bestScore
	for _=1,craft.rogAttempts do
		local candidate=copyTable(input)
		for index=#candidate.affixes,1,-1 do if model.byId[candidate.affixes[index].id].type==side then table.remove(candidate.affixes,index) end end
		for _=1,count do
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
		local score=total/count
		if not bestScore or score>bestScore then best,bestScore=candidate,score end
	end
	return best
end
function R.extend(M,api)
	M.methods[#M.methods+1]="rog_reroll";M.labels.rog_reroll="Rog: observed side reroll (experimental)";table.sort(M.methods)
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
		return R.reroll(M,model,input,craft,random)
	end
	function M.priceKey(craft)
		if craft.method~="rog_reroll" then return priceKey(craft) end
		local fields={"rog_reroll",tostring(craft.rogSide),tostring(craft.rogAttempts)}
		for _,tier in ipairs(tiers) do fields[#fields+1]=craft.artifactCost and tostring(craft.artifactCost[tier] or 0) or "unknown" end
		return table.concat(fields,":")
	end
	function M.components(craft,state,model)
		if craft.method=="rog_reroll" then return R.components(craft) end
		return components(craft,state,model)
	end
	M.limits[#M.limits+1]="Experimental Rog side rerolls use observed offers and prices. Ordinary affix weights, preserved count, average modifier-level ranking and first-on-tie selection are assumptions; offer generation and special interactions are not modeled."
end
return R
