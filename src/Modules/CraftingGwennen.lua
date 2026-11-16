-- Bounded model of a pair observed in Gwennen's 3.30 crafting interface.
local G={}
local supported={[1000]=true,[1001]=true,[1003]=true,[1004]=true,[1005]=true,[1006]=true,[1007]=true,[1008]=true,[1009]=true,[1010]=true,[1011]=true,[1012]=true,[1013]=true,[1014]=true,[1015]=true,[1016]=true,[1017]=true,[1018]=true,[1019]=true,[1022]=true,[1023]=true,[1024]=true,[1025]=true,[1026]=true,[1027]=true,[1029]=true,[1031]=true,[1041]=true,[1042]=true}
local deterministic={[1000]="No change",[1001]="Remove all modifiers",[1022]="Destroy",[1029]="Set quality to 20%"}
local currencies={lesser="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_1",greater="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_2",grand="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_3",exceptional="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_4"}
local astragali="Metadata/Items/Currency/CurrencyRefreshGambler"
function G.supports(id) return supported[id]==true end
function G.supportedCount() local count=0;for _ in pairs(supported) do count=count+1 end;return count end
function G.deterministic(id) return deterministic[id] end
function G.isDiscrete(id) return deterministic[id]~=nil or id==1004 or id==1006 or id==1007 or id==1016 or id==1017 or id==1023 or id==1026 or id==1031 or id==1041 end
local influenceTypes={"shaper","elder","adjudicator","basilisk","crusader","eyrie"}
local function influenceChoices(model,state)
	assert(#(state.influences or model.initial.influences or {})==0 and not model.item.synthesised,"Influence outcome requires an uninfluenced, non-synthesised item")
	assert(#(state.implicits or {})==0 and not model.unresolvedEldritch,"Influence outcome does not support Eldritch implicits")
	local choices={};for _,key in ipairs(influenceTypes) do if model.item.base.influenceTags and model.item.base.influenceTags[key] then choices[#choices+1]=key end end
	assert(#choices>0,"This base cannot receive a supported influence")
	return choices
end
-- Enumerate removal sets without multiplying equivalent removal orders.
function G.discrete(model,state,id)
	if deterministic[id] then return {{draws={},probability=1,text=deterministic[id]}} end
	if id==1016 or id==1017 then
		local sim=require("Modules.CraftingSimulator")
		local reason=sim.methodReason(model,state,"fusing");assert(not reason,reason)
		local candidates=require("Modules.CraftingSockets").fusingOutcomes(state)
		local scores,totals={},{}
		for i,candidate in ipairs(candidates) do
			local counts,largest={},0
			for _,group in ipairs(candidate.groups) do counts[group]=(counts[group] or 0)+1;largest=math.max(largest,counts[group]) end
			scores[i]=largest;totals[largest]=(totals[largest] or 0)+candidate.probability
		end
		-- The maximum has score s with probability P(score <= s)^N - P(score < s)^N.
		-- The first tied layout is distributed proportionally to its original weight.
		local rolls=id==1016 and 100 or 50;local weights={};local cumulative=0
		for score=1,6 do
			local below=cumulative;cumulative=cumulative+(totals[score] or 0)
			if totals[score] then weights[score]=(cumulative^rolls-below^rolls)/totals[score] end
		end
		local result,offset={},0
		for i,candidate in ipairs(candidates) do
			local probability=candidate.probability*weights[scores[i]]
			if probability>0 then
				local draws={};for n=1,rolls do draws[n]=offset+candidate.probability/2 end
				result[#result+1]={draws=draws,probability=probability,text="Best link: "..scores[i].." (layout "..table.concat(candidate.groups,"-")..")"}
			end
			offset=offset+candidate.probability
		end
		return result
	end
	if id==1031 then
		local choices=influenceChoices(model,state);local result={}
		for index,key in ipairs(choices) do result[#result+1]={draws={(index-0.5)/#choices},probability=1/#choices,text="Add influence: "..key} end
		return result
	end
	local choices={}
	if id==1004 or id==1023 or id==1026 then for i=1,#state.affixes do choices[#choices+1]=i end
	elseif id==1006 or id==1007 then
		local side=id==1006 and "Suffix" or "Prefix"
		for i,entry in ipairs(state.affixes) do if model.byId[entry.id].type==side then choices[#choices+1]=i end end
	elseif id==1041 then
		local lowest
		for i,entry in ipairs(state.affixes) do
			local level=assert(model.byId[entry.id].level,"Modifier level is unavailable")
			if not lowest or level<lowest then lowest=level;choices={} end
			if level==lowest then choices[#choices+1]=i end
		end
	else return nil end
	if id==1026 then
		assert(#choices>=3,"This experimental outcome requires at least three modifiers")
		local result={};local chosen={}
		local function enumerate(start,remaining,count)
			if remaining==0 then
				local draws={(count-0.5)/3};local labels={}
				for order,index in ipairs(chosen) do
					draws[#draws+1]=(index-order+0.5)/(#choices-order+1)
					labels[#labels+1]=table.concat(model.byId[state.affixes[index].id]," / ")
				end
				result[#result+1]={draws=draws,text="Remove: "..table.concat(labels,"; "),count=count}
				return
			end
			for index=start,#choices-remaining+1 do chosen[#chosen+1]=index;enumerate(index+1,remaining-1,count);chosen[#chosen]=nil end
		end
		for count=1,3 do enumerate(1,count,count) end
		local totals={};for _,entry in ipairs(result) do totals[entry.count]=(totals[entry.count] or 0)+1 end
		for _,entry in ipairs(result) do entry.probability=1/(3*totals[entry.count]) end
		return result
	end
	assert(#choices>0,"No eligible modifier for this Gwennen outcome")
	local result={}
	for index,affixIndex in ipairs(choices) do
		local text=table.concat(model.byId[state.affixes[affixIndex].id]," / ")
		result[#result+1]={draws={(index-0.5)/#choices},probability=1/#choices,text=(id==1023 and "Keep: " or "Remove: ")..text}
	end
	return result
end
function G.validate(craft)
	assert(supported[craft.firstOutcome] and supported[craft.secondOutcome],"Choose two supported, observed Gwennen outcomes")
	assert(not craft.allflame,"Allflame cannot be used with Gwennen")
	if craft.artifactCost~=nil then
		assert(type(craft.artifactCost)=="table","Invalid observed artifact cost")
		for key,value in pairs(craft.artifactCost) do assert(currencies[key] and type(value)=="number" and value==math.floor(value) and value>=0 and value<=1000000000,"Invalid observed artifact cost") end
	end
end
function G.extend(M,api)
	M.methods[#M.methods+1]="gwennen";M.labels.gwennen="Gwennen: observed pair (experimental)";table.sort(M.methods)
	local action,components,priceKey,validateRecipe=M.action,M.components,M.priceKey,M.validateRecipe
	function M.validateRecipe(recipe)
		local result=validateRecipe(recipe)
		for _,step in ipairs(result.steps) do if step.method=="gwennen" then G.validate(step) end end
		return result
	end
	function M.action(model,input,craft,random)
		if craft.method~="gwennen" then return action(model,input,craft,random) end
		G.validate(craft);model=M.context(model,input)
		assert(input.rarity=="RARE" and not input.destroyed and not input.corrupted and not input.mirrored and not input.veil,"Gwennen requires an uncorrupted rare equipment item")
		assert(model.item.type~="Jewel" and model.item.type~="Flask" and model.item.type~="Tincture","Gwennen requires equipment")
		local flags=api.flags(model,input)
		assert(not (flags.prefixes or flags.suffixes or flags.attack or flags.caster or flags.explicitAttack or flags.explicitCaster or M.hasPartialLock(model,input)),"Gwennen interactions with meta modifiers are not modeled")
		for _,entry in ipairs(input.affixes) do assert(not entry.fractured,"Gwennen interactions with fractured modifiers are not modeled") end
		local function branch(id,draw,probe)
			if id==1000 then return copyTable(input) end
			if id==1010 or id==1011 then
				return M.bestChromatic(model,input,probe and 1 or id==1010 and 50 or 20,draw)
			end
			if id==1016 or id==1017 then
				return M.bestFusing(model,input,probe and 1 or id==1016 and 100 or 50,draw)
			end
			if id==1031 then
				local choices=influenceChoices(model,input);local result=copyTable(input)
				result.influences={choices[math.floor(draw()*#choices)+1]};return result
			end
			if id==1022 then local result=copyTable(input);result.destroyed=true;result.affixes={};result.imprint=nil;result.implicits=nil;result.corruptedImplicits=nil;return result end
			if id==1001 then
				assert(#input.affixes>0,"No modifier can be removed")
				local result=copyTable(input);result.affixes={};result.rarity="NORMAL";return result
			end
			if id==1006 or id==1007 then
				local result=copyTable(input);local side=id==1006 and "Suffix" or "Prefix";local choices={}
				for index,entry in ipairs(result.affixes) do if model.byId[entry.id].type==side then choices[#choices+1]=index end end
				assert(#choices>0,"No "..side:lower().." modifier can be removed")
				table.remove(result.affixes,choices[math.floor(draw()*#choices)+1]);return result
			end
			if id==1008 or id==1009 then
				local result=copyTable(input);local side=id==1008 and "Suffix" or "Prefix";local pool,total={},0
				for _,entry in ipairs(M.pool(model,result)) do if model.byId[entry.id].type==side then pool[#pool+1]=entry;total=total+entry.weight end end
				assert(total>0,"No "..side:lower().." modifier can be added")
				local pick=draw()*total
				for _,entry in ipairs(pool) do pick=pick-entry.weight;if pick<0 then result.affixes[#result.affixes+1]={id=entry.id,range=M.rollRange(model.byId[entry.id],draw)};return result end end
				error("Could not select a modifier")
			end
			if id==1018 or id==1019 then
				local result=copyTable(input);local side=id==1018 and "Prefix" or "Suffix";local count=0
				for index=#result.affixes,1,-1 do if model.byId[result.affixes[index].id].type==side then table.remove(result.affixes,index);count=count+1 end end
				assert(count>0,"No "..side:lower().." modifiers to reroll")
				-- Rog's comparable reroll preserves the number on that side. Its
				-- application to Gwennen and modifier weights are assumptions.
				for _=1,count do
					local pool,total={},0
					for _,entry in ipairs(M.pool(model,result)) do if model.byId[entry.id].type==side then pool[#pool+1]=entry;total=total+entry.weight end end
					assert(total>0,"No legal "..side:lower().." modifier can be added")
					local pick=draw()*total;local selected
					for _,entry in ipairs(pool) do pick=pick-entry.weight;if pick<0 then selected=entry;break end end
					assert(selected,"Could not select a modifier")
					result.affixes[#result.affixes+1]={id=selected.id,range=M.rollRange(model.byId[selected.id],draw)}
				end
				return result
			end
			if id==1023 then
				assert(#input.affixes>0,"No modifier can be retained")
				local result=copyTable(input);result.affixes={copyTable(input.affixes[math.floor(draw()*#input.affixes)+1])};return result
			end
			if id==1027 then
				assert(#input.affixes>0,"No modifier can be retained")
				local result=copyTable(input);result.affixes={copyTable(input.affixes[math.floor(draw()*#input.affixes)+1])}
				local roll=draw();local target=math.min(M.capacities(model,result).total,roll<8/12 and 4 or roll<11/12 and 5 or 6)
				while #result.affixes<target do api.add(model,result,draw) end
				return result
			end
			if id==1041 then
				local lowest,choices=nil,{}
				for index,entry in ipairs(input.affixes) do
					local level=assert(model.byId[entry.id].level,"Modifier level is unavailable")
					if not lowest or level<lowest then lowest=level;choices={} end
					if level==lowest then choices[#choices+1]=index end
				end
				assert(#choices>0,"No modifier can be removed")
				local result=copyTable(input);table.remove(result.affixes,choices[math.floor(draw()*#choices)+1]);return result
			end
			if id==1024 or id==1042 then
				local result=copyTable(input);local choices={}
				for index,entry in ipairs(result.affixes) do
					local mod=model.byId[entry.id];local ranges=type(entry.range)=="table" and entry.range or {entry.range or 0.5};local rangeIndex=0;local below=false
					for _,line in ipairs(mod) do for low,high in line:gmatch("%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)") do
						rangeIndex=rangeIndex+1
						if tonumber(low)~=tonumber(high) and (ranges[rangeIndex] or ranges[1] or 0.5)<1 then below=true end
					end end
					if below then choices[#choices+1]=index end
				end
				assert(#choices>0,"No supported modifier has a value below its maximum")
				if id==1042 then choices={choices[math.floor(draw()*#choices)+1]} end
				for _,index in ipairs(choices) do local entry=result.affixes[index];entry.legacyLightRadius=nil;entry.range=M.rollRange(model.byId[entry.id],draw) end
				return result
			end
			if id==1025 then
				local result=copyTable(input);local maximum=M.capacities(model,result).total
				assert(#result.affixes<maximum,"No empty modifier slot")
				while #result.affixes<maximum do api.add(model,result,draw) end;return result
			end
			if id==1026 then
				assert(#input.affixes>=3,"This experimental outcome requires at least three modifiers")
				local result=copyTable(input);local count=math.floor(draw()*3)+1
				for _=1,count do table.remove(result.affixes,math.floor(draw()*#result.affixes)+1) end;return result
			end
			if id==1029 then
				assert(model.item.base.armour or data.weaponTypeInfo[model.item.type],"This quality outcome requires a weapon or armour")
				local result=copyTable(input);result.quality=20;return result
			end
			local method=({[1003]="fracture",[1004]="annul",[1005]="exalt",[1012]="vaal",[1013]="ducat_brinehook",[1014]="chaos",[1015]="divine"})[id]
			return action(model,input,{method=method},draw)
		end
		-- An observed pair is valid only when both modeled branches are usable.
		-- Dry runs do not consume the caller's random stream or mutate its input.
		for _,id in ipairs({craft.firstOutcome,craft.secondOutcome}) do
			local ok,err=pcall(branch,id,function() return 0.42 end,true)
			assert(ok,"A modeled Gwennen outcome cannot apply: "..tostring(err))
		end
		local outcome=random()<0.5 and craft.firstOutcome or craft.secondOutcome
		return branch(outcome,random),{gwennen={outcome=outcome}}
	end
	function M.priceKey(craft)
		if craft.method~="gwennen" then return priceKey(craft) end
		local fields={"gwennen",tostring(craft.firstOutcome),tostring(craft.secondOutcome)}
		for _,key in ipairs({"lesser","greater","grand","exceptional"}) do fields[#fields+1]=craft.artifactCost and tostring(craft.artifactCost[key] or 0) or "unknown" end
		return table.concat(fields,":")
	end
	function M.components(craft,state,model)
		if craft.method~="gwennen" then return components(craft,state,model) end
		G.validate(craft);local result={[astragali]=1}
		if craft.artifactCost==nil then result["gwennen:observed_artifacts"]=1
		else for key,amount in pairs(craft.artifactCost) do if amount>0 then result[currencies[key]]=amount end end end
		return result
	end
	M.limits[#M.limits+1]="Experimental Gwennen pairs use only observed supported outcomes. A fair coin, uniform selection and removal counts, side-reroll count preservation, normalized maximum-roll checks and ordinary crafting transitions are assumptions; offer generation, prices and special modifier interactions are not verified. Unknown artifact prices remain unpriced."
end
return G
