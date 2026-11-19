-- Bounded model of a pair observed in Gwennen's 3.30 crafting interface.
local G={}
local supported={[1000]=true,[1001]=true,[1003]=true,[1004]=true,[1005]=true,[1006]=true,[1007]=true,[1008]=true,[1009]=true,[1010]=true,[1011]=true,[1012]=true,[1013]=true,[1014]=true,[1015]=true,[1016]=true,[1017]=true,[1018]=true,[1019]=true,[1020]=true,[1021]=true,[1022]=true,[1023]=true,[1024]=true,[1025]=true,[1026]=true,[1027]=true,[1028]=true,[1029]=true,[1030]=true,[1031]=true,[1032]=true,[1033]=true,[1034]=true,[1035]=true,[1036]=true,[1037]=true,[1038]=true,[1039]=true,[1040]=true,[1041]=true,[1042]=true,[1043]=true,[1044]=true}
local deterministic={[1000]="No change",[1001]="Remove all modifiers",[1022]="Destroy",[1029]="Set quality to 20%"}
local currencies={lesser="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_1",greater="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_2",grand="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_3",exceptional="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_4"}
local astragali="Metadata/Items/Currency/CurrencyRefreshGambler"
local function belowMaximum(mod,range)
	local ranges=type(range)=="table" and range or {range};local index=0;local below=false
	for _,line in ipairs(mod) do for low,high in line:gmatch("%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)") do
		index=index+1
		if tonumber(low)~=tonumber(high) then
			local value=ranges[index] or ranges[1];assert(type(value)=="number","An implicit roll could not be identified")
			if value<1 then below=true end
		end
	end end
	return below
end
local function rerollImplicits(M,model,input,draw)
	local result=copyTable(input);local changed=false
	assert(not model.unresolvedEldritch or result.implicits,"Identify the Eldritch implicits before rerolling them")
	if result.implicits and #result.implicits>0 then
		for _,entry in ipairs(result.implicits) do
			local mod=assert(model.byId[entry.id],"The Eldritch implicit is not recognized")
			if belowMaximum(mod,entry.range) then entry.range=M.rollRange(mod,draw);changed=true end
		end
	elseif model.item.synthesised then
		assert(model.synthesisGroups,"Identify the synthesised implicits before rerolling them")
		result.synthRolls=result.synthRolls or {}
		for index,group in ipairs(model.synthesisGroups) do
			assert(#group.candidates==1,"Synthesised implicit identities must be unambiguous before rerolling")
			local entry=result.synthRolls[index] or copyTable(group.candidates[1]);result.synthRolls[index]=entry
			local mod=assert(model.byId[entry.id],"The synthesised implicit is not recognized")
			if belowMaximum(mod,entry.range) then entry.range=M.rollRange(mod,draw);changed=true end
		end
	else
		assert(not model.blessed330 and not model.blessed330Unresolved and not model.baseImplicitUnresolved,"This special implicit reroll is not modeled")
		assert(#model.item.implicitModLines>0,"This item has no supported implicit to reroll")
		assert(model.baseImplicitTemplates and #model.baseImplicitTemplates==#model.item.implicitModLines,"Rerolling unidentified base implicits is not modeled")
		local ranges={};local varyingLine
		for i,line in ipairs(model.item.implicitModLines) do
			local template=model.baseImplicitTemplates[i]
			assert(not result.baseImplicitRanges or result.baseImplicitReconstructed or line.line==template,"The legacy implicit roll cannot be identified; reset or update the working item")
			ranges[i]=result.baseImplicitRanges and result.baseImplicitRanges[i] or model.normalizedBaseImplicitRanges and model.normalizedBaseImplicitRanges[i] or line.range
			local varying=false
			for low,high in template:gmatch("%((%-?%d+%.?%d*)%-(%-?%d+%.?%d*)%)") do if tonumber(low)~=tonumber(high) then varying=true end end
			if varying then
				assert(ranges[i]~=nil,"An implicit roll could not be identified")
				assert(not varyingLine,"Rerolling multiple varying base implicit lines is not modeled")
				varyingLine=i
			else ranges[i]=ranges[i] or 0.5 end
		end
		if varyingLine and belowMaximum({model.baseImplicitTemplates[varyingLine]},ranges[varyingLine]) then
			ranges[varyingLine]=M.rollRange({model.baseImplicitTemplates[varyingLine]},draw)
			result.baseImplicitRanges=ranges;result.baseImplicitReconstructed=true;changed=true
		end
	end
	assert(changed,"No supported implicit has a value below its maximum")
	return result
end
-- This preflight checks only the implicit branch, without consuming the real
-- random stream or claiming that the other observed outcome will succeed.
function G.implicitReason(model,state)
	local M=require("Modules.CraftingSimulator")
	local ok,result=pcall(function() return rerollImplicits(M,M.context(model,state),state,function() return 0.42 end) end)
	if not ok then return require("Modules.PlanningUI").errorText(result) end
end
function G.supports(id) return supported[id]==true end
function G.supportedCount() local count=0;for _ in pairs(supported) do count=count+1 end;return count end
function G.deterministic(id) return deterministic[id] end
function G.isDiscrete(id) return deterministic[id]~=nil or id==1004 or id==1006 or id==1007 or id==1016 or id==1017 or id==1023 or id==1026 or id==1028 or id==1030 or id==1031 or id==1041 end
local influenceTypes={"shaper","elder","adjudicator","basilisk","crusader","eyrie"}
local function influenceChoices(model,state)
	assert(#(state.influences or model.initial.influences or {})==0 and not model.item.synthesised,"Influence outcome requires an uninfluenced, non-synthesised item")
	assert(#(state.implicits or {})==0 and not model.unresolvedEldritch,"Influence outcome does not support Eldritch implicits")
	local choices={};for _,key in ipairs(influenceTypes) do if model.item.base.influenceTags and model.item.base.influenceTags[key] then choices[#choices+1]=key end end
	assert(#choices>0,"This base cannot receive a supported influence")
	return choices
end
-- Restrict tier changes to ordinary families whose adjacent tier is unique
-- in the current item's legal pool. Selection and Gwennen's tier rules remain
-- assumptions; special or ambiguous families must not be guessed.
local function tierChoices(model,state,upgrade)
	local sim=require("Modules.CraftingSimulator");local metadata=require("Modules.CraftingAdvanced").data().mods
	assert(#state.affixes>0,"No modifier can change tier")
	local choices={}
	local function signature(meta)
		local groups={};for _,group in ipairs(meta.groups or {}) do groups[#groups+1]=group end;table.sort(groups)
		local stats={};for _,stat in ipairs(meta.stats or {}) do stats[#stats+1]=stat.id end;table.sort(stats)
		return table.concat(groups,"\0").."\1"..table.concat(stats,"\0")
	end
	for index,entry in ipairs(state.affixes) do
		local meta=metadata[entry.id];local stem=entry.id:match("^(.-)%d+$")
		assert(meta and stem and meta.groups and #meta.groups>0 and meta.stats and #meta.stats>0 and not entry.crafted and not entry.fractured and not entry.legacyLightRadius and not entry.description330,"Tier changes require recognized ordinary modifiers")
		local input=copyTable(state);table.remove(input.affixes,index)
		local pool=sim.pool(model,input);local current=false;local bestLevel,bestId,ties
		for _,candidate in ipairs(pool) do
			if candidate.id==entry.id then current=true end
			local other=metadata[candidate.id]
			if other and candidate.id:match("^(.-)%d+$")==stem and other.domain==meta.domain and other.generation_type==meta.generation_type and signature(other)==signature(meta) then
				local level=other.required_level
				if upgrade and level>meta.required_level or not upgrade and level<meta.required_level then
					if not bestLevel or upgrade and level<bestLevel or not upgrade and level>bestLevel then bestLevel,bestId,ties=level,candidate.id,1
					elseif level==bestLevel then ties=ties+1 end
				end
			end
		end
		assert(current,"Tier changes require a currently rollable modifier family")
		assert(bestId and ties==1,"Every modifier needs one unambiguous adjacent tier for this experimental outcome")
		local function addedTags(value) local tags=copyTable(value.adds_tags or {});table.sort(tags);return table.concat(tags,"\0") end
		assert(addedTags(meta)==addedTags(metadata[bestId]),"Adjacent tiers with different granted tags are not modeled")
		choices[#choices+1]={index=index,id=bestId}
	end
	return choices
end
-- Enumerate removal sets without multiplying equivalent removal orders.
function G.discrete(model,state,id,craft)
	if deterministic[id] then return {{draws={},probability=1,text=deterministic[id]}} end
	if id==1028 or id==1030 then
		local rolls=id==1028 and 50 or assert(craft and craft.gwennenSocketRerolls,"Choose 50 or 100 socket rerolls for this disputed offer")
		local sim=require("Modules.CraftingSimulator")
		local reason=sim.methodReason(model,state,"jeweller");assert(not reason,reason)
		local probabilities=require("Modules.CraftingSockets").jewellerProbabilities(model,state)
		local result,cumulative={},0
		for count,chance in ipairs(probabilities) do
			local below=cumulative;cumulative=math.min(1,cumulative+chance)
			local probability=cumulative^rolls-below^rolls
			if probability>0 then
				local draws={};for i=1,rolls do draws[i]=below+chance/2 end
				result[#result+1]={draws=draws,probability=probability,text="Best socket count: "..count}
			end
		end
		return result
	end
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
	if craft.firstOutcome==1030 or craft.secondOutcome==1030 then
		assert(craft.gwennenSocketRerolls==50 or craft.gwennenSocketRerolls==100,"Choose 50 or 100 socket rerolls for this disputed offer")
	else assert(craft.gwennenSocketRerolls==nil,"Socket reroll scenario applies only to the disputed offer") end
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
		local tierCache={}
		local function branch(id,draw,probe)
			if id==1000 then return copyTable(input) end
			if id>=1033 and id<=1040 then
				local single=({[1033]=1009,[1034]=1009,[1035]=1008,[1036]=1008,[1037]=1018,[1038]=1018,[1039]=1019,[1040]=1019})[id]
				local count=({[1033]=3,[1034]=5,[1035]=3,[1036]=5,[1037]=3,[1038]=6,[1039]=3,[1040]=6})[id]
				local side=(id==1033 or id==1034 or id==1037 or id==1038) and "Prefix" or "Suffix"
				local best,bestScore
				for _=1,probe and 1 or count do
					local candidate=branch(single,draw,probe);local total,num=0,0
					for _,entry in ipairs(candidate.affixes) do local mod=model.byId[entry.id]
						if mod.type==side then total=total+assert(mod.level,"Modifier level is unavailable");num=num+1 end
					end
					assert(num>0,"No modifier to score")
					local score=total/num
					if not bestScore or score>bestScore then best,bestScore=candidate,score end
				end
				return best
			end
			if id==1010 or id==1011 then
				return M.bestChromatic(model,input,probe and 1 or id==1010 and 50 or 20,draw)
			end
			if id==1016 or id==1017 then
				return M.bestFusing(model,input,probe and 1 or id==1016 and 100 or 50,draw)
			end
			if id==1028 or id==1030 then
				local reason=M.methodReason(model,input,"jeweller");assert(not reason,reason)
				local rolls=id==1028 and 50 or craft.gwennenSocketRerolls
				return M.bestJeweller(model,input,probe and 1 or rolls,draw)
			end
			if id==1031 then
				local choices=influenceChoices(model,input);local result=copyTable(input)
				result.influences={choices[math.floor(draw()*#choices)+1]};return result
			end
			if id==1032 then return rerollImplicits(M,model,input,draw) end
			if id==1022 then local result=copyTable(input);result.destroyed=true;result.affixes={};result.imprint=nil;result.implicits=nil;result.corruptedImplicits=nil;result.synthRolls=nil;return result end
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
			if id==1020 or id==1021 or id==1043 or id==1044 then
				local count=id==1043 and 2 or id==1044 and 3 or 1
				assert(#input.affixes>=count,"This tier outcome requires at least "..count.." modifiers")
				local choices=tierCache[id] or tierChoices(model,input,id~=1021);tierCache[id]=choices
				local remaining=copyTable(choices);local result=copyTable(input)
				for _=1,count do
					local selected=table.remove(remaining,math.floor(draw()*#remaining)+1)
					local entry=result.affixes[selected.index];entry.id=selected.id;entry.range=M.rollRange(model.byId[selected.id],draw)
				end
				return result
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
			if not ok then error("A modeled Gwennen outcome cannot apply: "..require("Modules.PlanningUI").errorText(err),0) end
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
