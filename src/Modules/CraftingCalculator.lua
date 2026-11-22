-- Prefer finite enumeration; label bounded sampling explicitly for other crafts.
local C={}
function C.extend(M)
	local calculate=M.calculate
	local finite={recombine_predictable=true,augmentation=true,regal=true,exalt=true,influence_exalt=true,beast_talisman_fracture=true,ducat_kishara=true,ducat_tzamoto=true}
	function M.calculate(raw,craft,targets,initialState,options)
		options=options or {}
		local conflict=M.requirementsConflict(options.requirements);assert(not conflict,conflict)
		if craft.method=="sacred" and not craft.allflame then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			M.perform(raw,craft,options.seed,initialState)
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			model=M.context(model,state)
			local outcomes,byDefence,hits={},{},0
			for position=0,31 do
				local draws=0;local result=M.action(model,state,craft,function() draws=draws+1;assert(draws==1,"Unexpected Sacred roll draw");return (position+0.5)/32 end)
				local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups);if hit then hits=hits+1 end
				local key={};for _,kind in ipairs({"Armour","Evasion","EnergyShield","Ward"}) do key[#key+1]=tostring(result.percentiles[kind] or "") end;key=table.concat(key,":")
				local entry=byDefence[key]
				if entry then
					assert(entry.matches==hit,"Identical Sacred outcomes disagree on the target")
					entry.weight=entry.weight+1/32;entry.chance=entry.weight*100
				else
					local stats=require("Modules.CraftingItemStats").values(M,model,result)
					entry={id=tostring(position),text=require("Modules.CraftingSacred").describe(stats),chance=100/32,weight=1/32,matches=hit,state=result}
					outcomes[#outcomes+1]=entry;byDefence[key]=entry
				end
			end
			local sample=outcomes[1].state
			return {exactFor="32 shared-roll positions; game odds unverified.",sampled=false,successChance=100*hits/32,totalWeight=1,matchingWeight=hits/32,
				outcomes=outcomes,sampleState=sample,sampleItem=M.itemText(model,sample),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
		end
		if craft.method=="rog_reroll" and (craft.rogOperation=="socket_count" or craft.rogOperation=="socket_links") then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			model=M.context(model,state)
			local branches=require("Modules.CraftingSockets").bestOfOutcomes(model,state,craft.rogOperation=="socket_count" and "count" or "links",craft.rogSocketRolls)
			local outcomes,hits={},0
			for index,branch in ipairs(branches) do
				local cursor=0;local result=M.action(model,state,craft,function() cursor=cursor+1;return assert(branch.draws[cursor],"Unexpected Rog socket draw") end)
				local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
				if hit then hits=hits+branch.probability end
				outcomes[#outcomes+1]={id=tostring(index),text=branch.text,chance=100*branch.probability,weight=branch.probability,matches=hit,state=result}
			end
			local sample=assert(outcomes[1],"No modeled socket outcomes").state
			return {exactFor="Rog best-of socket outcomes under the estimated socket model and first-on-tie rule",showAllOutcomes=true,sampled=false,successChance=100*hits,totalWeight=1,matchingWeight=hits,
				outcomes=outcomes,sampleState=sample,sampleItem=M.itemText(model,sample),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
		end
		if craft.method=="rog_reroll" and (craft.rogOperation=="remove_lowest" or craft.rogOperation=="remove_lowest_two") then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			model=M.context(model,state);local branches=require("Modules.CraftingRog").removalOutcomes(model,state,craft)
			local outcomes,hits={},0
			for index,branch in ipairs(branches) do
				local cursor=0;local result=M.action(model,state,craft,function() cursor=cursor+1;return assert(branch.draws[cursor],"Unexpected Rog random draw") end)
				local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
				if hit then hits=hits+branch.probability end
				outcomes[#outcomes+1]={id=tostring(index),text=branch.text,chance=100*branch.probability,weight=branch.probability,matches=hit,state=result}
			end
			local sample=outcomes[1].state
			return {exactFor="Rog lowest-level removal under the assumed equal tie chances",showAllOutcomes=true,sampled=false,successChance=100*hits,totalWeight=1,matchingWeight=hits,
				outcomes=outcomes,sampleState=sample,sampleItem=M.itemText(model,sample),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
		end
		local gwennen=require("Modules.CraftingGwennen")
		if craft.method=="gwennen" and gwennen.isDiscrete(craft.firstOutcome) and gwennen.isDiscrete(craft.secondOutcome) then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			model=M.context(model,state);local first=gwennen.discrete(model,state,craft.firstOutcome,craft);local second=gwennen.discrete(model,state,craft.secondOutcome,craft)
			if first and second then
				local outcomes,hits={},0
				for side,branches in ipairs({first,second}) do for _,branch in ipairs(branches) do
					local cursor=0;local result=M.action(model,state,craft,function()
						cursor=cursor+1;if cursor==1 then return side==1 and 0.25 or 0.75 end
						return assert(branch.draws[cursor-1],"Unexpected Gwennen random draw")
					end)
					local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups);local probability=branch.probability/2
					if hit then hits=hits+probability end
					outcomes[#outcomes+1]={id=tostring(side)..":"..#outcomes,text=branch.text,chance=100*probability,weight=probability,matches=hit,state=result}
				end end
				local sample=outcomes[1].state
				return {exactFor="Gwennen branches under the assumed fair coin and stated experimental outcome models",showAllOutcomes=true,sampled=false,successChance=100*hits,totalWeight=1,matchingWeight=hits,
					outcomes=outcomes,sampleState=sample,sampleItem=M.itemText(model,sample),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
			end
		end
		local method=M.baseCurrency(craft)
		local partialConversion=false
		if method=="harvest_damage" or method=="harvest_resistance" then
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			partialConversion=M.hasPartialLock(M.context(model,state),state)
		end
		-- Conversion picks one eligible modifier, then rerolls its values. When
		-- targets only refer to modifier identities, the value roll cannot alter
		-- whether a target matches, so enumerate the modeled choices exactly.
		if method=="harvest_damage" and not partialConversion and not craft.allflame and not options.requirements then
			local rollGoal=false;for _,group in ipairs(targets or {}) do if group.minRoll~=nil then rollGoal=true;break end end
			if not rollGoal then
				M.validateRecipe({steps={craft},targets=targets,requiredGroups=options.requiredGroups})
				M.perform(raw,craft,options.seed,initialState)
				local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
				if M.context then model=M.context(model,state) end
				local reason,choices=M.damageReason(model,state,craft.from,craft.to);assert(not reason,reason)
				local outcomes,hits={},0
				for index,choice in ipairs(choices) do
					local draws=0;local result=M.action(model,state,craft,function()
						draws=draws+1;return draws==1 and (index-0.5)/#choices or 0.5
					end)
					local hit=M.matches(result,targets,nil,model,nil,options.requiredGroups);if hit then hits=hits+1 end
					local source=state.affixes[choice.index].id
					outcomes[#outcomes+1]={id=source..":"..choice.id,sourceId=source,targetId=choice.id,
						text=table.concat(model.byId[source]," / ").." -> "..table.concat(model.byId[choice.id]," / "),
						chance=100/#choices,weight=1,matches=hit,state=result}
				end
				return {exactFor="One conversion: assumed tiers and uniform selection",showAllOutcomes=true,outcomesFirst=true,
					sampled=false,successChance=100*hits/#choices,totalWeight=#choices,matchingWeight=hits,outcomes=outcomes,
					sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
			end
		end
		if method=="harvest_resistance" and not partialConversion and not craft.allflame and not options.requirements then
			local rollGoal=false;for _,group in ipairs(targets or {}) do if group.minRoll~=nil then rollGoal=true;break end end
			if not rollGoal then
				M.validateRecipe({steps={craft},targets=targets,requiredGroups=options.requiredGroups})
				M.perform(raw,craft,options.seed,initialState)
				local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
				if M.context then model=M.context(model,state) end
				local reason,choices=M.resistanceReason(model,state,craft.from,craft.to);assert(not reason,reason)
				local outcomes,hits={},0
				for index,affixIndex in ipairs(choices) do
					local draws=0;local result=M.action(model,state,craft,function()
						draws=draws+1;return draws==1 and (index-0.5)/#choices or 0.5
					end)
					local hit=M.matches(result,targets,nil,model,nil,options.requiredGroups);if hit then hits=hits+1 end
					local source,target=state.affixes[affixIndex].id,result.affixes[affixIndex].id
					outcomes[#outcomes+1]={id=source..":"..target,sourceId=source,targetId=target,
						text=table.concat(model.byId[source]," / ").." -> "..table.concat(model.byId[target]," / "),
						chance=100/#choices,weight=1,matches=hit,state=result}
				end
				return {exactFor="One conversion under assumed tier mapping and uniform selection",showAllOutcomes=true,outcomesFirst=true,
					sampled=false,successChance=100*hits/#choices,totalWeight=#choices,matchingWeight=hits,outcomes=outcomes,
					sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
			end
		end
		if method=="jeweller" and not craft.allflame then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			if M.context then model=M.context(model,state) end
			local reason=M.methodReason(model,state,method);assert(not reason,reason)
			local probabilities=require("Modules.CraftingSockets").jewellerProbabilities(model,state);local outcomes,hitWeight,offset={},0,0
			for count,probability in ipairs(probabilities) do if probability>0 then
				local draw=offset+probability/2;offset=offset+probability
				local result=M.action(model,state,craft,function() return draw end)
				local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
				if hit then hitWeight=hitWeight+probability end
				outcomes[#outcomes+1]={id=tostring(count),text=count..(count==1 and " socket" or " sockets"),chance=100*probability,weight=probability,matches=hit,state=result}
			end end
			return {exactFor="One Jeweller's Orb under the historical socket-weight and quality assumptions",showAllOutcomes=true,sampled=false,successChance=100*hitWeight,totalWeight=1,matchingWeight=hitWeight,
				outcomes=outcomes,sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
		end
		if method=="fusing" and not craft.allflame then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			if M.context then model=M.context(model,state) end
			local candidates=require("Modules.CraftingSockets").fusingOutcomes(state);local outcomes,hitWeight,offset={},0,0
			for index,entry in ipairs(candidates) do
				local draw=offset+entry.probability/2;offset=offset+entry.probability
				local result=M.action(model,state,craft,function() return draw end)
				local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
				if hit then hitWeight=hitWeight+entry.probability end
				local sizes={};for _,group in ipairs(entry.groups) do sizes[group+1]=(sizes[group+1] or 0)+1 end
				outcomes[#outcomes+1]={id=tostring(index),text="Link groups: "..table.concat(sizes," + "),chance=100*entry.probability,weight=entry.probability,matches=hit,state=result}
			end
			return {exactFor="One Fusing under the historical link-group and quality assumptions",sampled=false,successChance=100*hitWeight,totalWeight=1,matchingWeight=hitWeight,
				outcomes=outcomes,sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
		end
		if craft.method=="vaal" and not craft.allflame then
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			if M.context then model=M.context(model,state) end
			if model.item.type=="Flask" then
				M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
				local outcomes,byQuality,hits={},{},0
				for draw=0,20 do
					local result=M.action(model,state,craft,function() return (draw+0.5)/21 end)
					local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
					if hit then hits=hits+1 end
					local entry=byQuality[result.quality]
					if not entry then entry={id=tostring(result.quality),text="Quality: "..result.quality.."%",weight=0,matches=hit,state=result};byQuality[result.quality]=entry;outcomes[#outcomes+1]=entry end
					entry.weight=entry.weight+1
				end
				for _,entry in ipairs(outcomes) do entry.chance=100*entry.weight/21 end
				return {exactFor="Flask Vaal quality under the assumed equal-weight model",sampled=false,successChance=100*hits/21,totalWeight=21,matchingWeight=hits,
					outcomes=outcomes,sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
			end
		end
		if craft.method=="annul" and not craft.allflame then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			if M.context then model=M.context(model,state) end
			if M.hasPartialLock(model,state) then
				local branches=M.partialAnnulBranches(model,state)
				if branches then
					local outcomes,success={},0
					for _,branch in ipairs(branches) do
						local draw=0;local result=M.action(model,state,craft,function()
							draw=draw+1;if draw<=#branch.draws then return branch.draws[draw] end
							assert(draw==#branch.draws+1,"Unexpected Annulment draw");return branch.removalDraw
						end)
						local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
						if hit then success=success+branch.probability end
						local entry=state.affixes[branch.index];local mod=model.byId[entry.id]
						outcomes[#outcomes+1]={id=entry.id,chance=100*branch.probability,weight=branch.probability,matches=hit,text="Remove: "..table.concat(mod," / "),state=result}
					end
					return {exactFor="One Annulment under the model's uniform lock-selection and removal assumptions",sampled=false,successChance=100*success,totalWeight=1,matchingWeight=success,
						outcomes=outcomes,sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
				end
			end
			if not M.hasPartialLock(model,state) then
			local choices=M.annulCandidates(model,state);local count=#choices
			assert(state.rarity~="NORMAL","Annulment requires a magic or rare item")
			assert(count>0,"No modifier can be removed")
			local outcomes,hits={},0
			for i,index in ipairs(choices) do
				local result=M.action(model,state,craft,function() return (i-0.5)/count end)
				local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
				if hit then hits=hits+1 end
				local entry=state.affixes[index];local mod=model.byId[entry.id]
				outcomes[#outcomes+1]={id=entry.id,chance=100/count,weight=1,matches=hit,text="Remove: "..table.concat(mod," / "),state=result}
			end
			return {exactFor="One Annulment under the model's uniform removable-modifier assumption",sampled=false,successChance=100*hits/count,totalWeight=count,matchingWeight=hits,
				outcomes=outcomes,sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
			end
		end
		if method=="omen_trichromatism" and not craft.allflame then
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			if #(state.sockets or {})==3 then
				M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
				local outcomes,hits={},0
				for first=1,3 do for second=1,2 do
					local draws={(first-0.5)/3,(second-0.5)/2};local at=0
					local result=M.action(model,state,craft,function() at=at+1;return assert(draws[at],"Unexpected socket-placement draw") end)
					local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
					if hit then hits=hits+1 end
					outcomes[#outcomes+1]={chance=100/6,weight=1,matches=hit,text="RGB placement "..(#outcomes+1),state=result}
				end end
				return {exactFor="Six socket placements under the stated uniform-position model",sampled=false,successChance=100*hits/6,totalWeight=6,matchingWeight=hits,
					outcomes=outcomes,sampleState=outcomes[1].state,sampleItem=M.itemText(model,outcomes[1].state),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
			end
		end
		if (craft.method=="quality" or craft.method=="catalyst" or craft.method=="tainted_quality") and not craft.allflame then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial;model=M.context(model,state)
			local draws={}
			if craft.method=="tainted_quality" then
				for quality=1,20 do draws[#draws+1]={value=(quality-0.5)/20,weight=1/20} end
			else
				local _,fraction=require("Modules.CraftingProperties").qualityGainProfile(model.item.itemLevel)
				if fraction>0 then draws[#draws+1]={value=fraction/2,weight=fraction} end
				if fraction<1 then draws[#draws+1]={value=(1+fraction)/2,weight=1-fraction} end
			end
			local outcomes,byQuality,hits={},{},0
			for _,draw in ipairs(draws) do
				local result=M.action(model,state,craft,function() return draw.value end)
				local quality=craft.method=="catalyst" and result.catalystQuality or result.quality
				local key=tostring(quality);local entry=byQuality[key]
				if not entry then
					local hit=M.matches(result,targets,nil,model,options.requirements,options.requiredGroups)
					entry={id=key,text=(craft.method=="catalyst" and "Catalyst quality: " or "Quality: ")..quality.."%",chance=0,weight=0,matches=hit,state=result};byQuality[key]=entry;outcomes[#outcomes+1]=entry
				end
				entry.weight=entry.weight+draw.weight;entry.chance=entry.weight*100;if entry.matches then hits=hits+draw.weight end
			end
			local sample=assert(outcomes[1],"No modeled quality outcome").state
			local exactFor=craft.method=="tainted_quality" and "One tainted quality action under the assumed uniform 1-20% model; game odds are unverified" or "One quality action under the estimated item-level gain model; game odds are unverified"
			return {exactFor=exactFor,showAllOutcomes=true,sampled=false,successChance=100*hits,totalWeight=1,matchingWeight=hits,
				outcomes=outcomes,sampleState=sample,sampleItem=M.itemText(model,sample),dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
		end
		if (method=="socket_bench" or method=="socket_white_bench" or method=="omen_jeweller" or method=="omen_connections" or method=="beast_max_links" or method=="beast_imprint" or method=="beast_talisman_imprint" or method=="restore_imprint" or method=="bench_remove_enchant" or method=="bench_flask_enchant" or method=="rog_reroll" and craft.rogOperation=="set_quality") and not craft.allflame then
			M.validateRecipe({steps={craft},targets=targets,requirements=options.requirements,requiredGroups=options.requiredGroups})
			local model=M.model(raw);local result=M.perform(raw,craft,options.seed,initialState)
			local hit=M.matches(result.state,targets,nil,model,options.requirements,options.requiredGroups)
			local imprint=method=="beast_imprint" or method=="beast_talisman_imprint" or method=="restore_imprint"
			return {exactFor=imprint and "One deterministic imprint action on the supplied item" or method=="bench_remove_enchant" and "One deterministic enchantment removal on the supplied item" or method=="bench_flask_enchant" and "One deterministic flask enchantment on the supplied item" or method=="rog_reroll" and "One modeled Rog quality action on the supplied item" or "One deterministic socket craft on the supplied item",sampled=false,successChance=hit and 100 or 0,
				totalWeight=1,matchingWeight=hit and 1 or 0,sampleState=result.state,sampleItem=result.itemText,
				outcomes={{chance=100,weight=1,matches=hit,text=M.labels[method],state=result.state}},dataPatch=M.dataPatch,limitations=copyTable(M.limits)}
		end
		local sampled=not finite[method] or options.requirements~=nil or options.requiredGroups~=nil
		for _,list in ipairs({targets,craft.allflame and craft.allflame.preferredTargets or {}}) do
			for _,group in ipairs(list) do if group.minRoll ~= nil then sampled=true end end
		end
		if not sampled then return calculate(raw,craft,targets,initialState) end
		-- A calculator always applies its action, even when the input already matches.
		local partialHarvest=false
		if method=="harvest_reforge" or method=="harvest_augment" or method=="harvest_resistance" or method=="harvest_damage" then
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			partialHarvest=M.hasPartialLock(M.context(model,state),state)
		end
		-- Partial-lock selection can make only some attempts invalid. Let the
		-- simulator report those transition errors instead of rejecting the
		-- entire calculation based on one arbitrarily seeded preflight.
		if method=="tainted_exalt" then
			-- Either modeled branch can fail at an affix limit. Check the item
			-- prerequisites without letting one random preflight decide whether
			-- the whole calculation is available.
			local model=M.model(raw);local state=initialState and M.validateState(model,initialState) or model.initial
			local available,reason=require("Modules.CraftingAvailability").check(method,state,model);assert(available,reason)
		elseif not partialHarvest then M.perform(raw,craft,options.seed,initialState) end
		local result=M.simulate(raw,{steps={craft},targets=targets,initialState=initialState,requirements=options.requirements,requiredGroups=options.requiredGroups},
			{trials=options.trials or 1000,maxActions=1,seed=options.seed,forceFirstAction=true,checkpoint=options.checkpoint})
		result.sampled=true;result.outcomes={}
		result.estimateFor="One action, sampled from the supplied state under the stated transition assumptions"
		return result
	end
end
return C
