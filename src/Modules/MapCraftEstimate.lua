-- Bounded Monte Carlo estimates for ordinary-map rerolls, not game odds.
local map=require("Modules.MapCraftingData")
local currency=require("Modules.MapCurrency")
local encounter=require("Modules.CalcEncounter")
local M={}
function M.validatePrice(price)
	if price==nil then return nil end
	assert(type(price)=="table","Invalid orb price")
	local amount,currency=price.amount,price.currency
	assert(type(amount)=="number" and amount==amount and amount>=0 and amount<=1e12,"Invalid orb price")
	assert(type(currency)=="string" and #currency<=24 and currency:match("^[A-Za-z][A-Za-z0-9 _%-]*$"),"Invalid price currency")
	return {amount=amount,currency=currency}
end
local function integer(value,low,high,label)
	assert(type(value)=="number" and value==math.floor(value) and value>=low and value<=high,"Invalid "..label);return value
end
local function ids(list,limit,label)
	assert(type(list)=="table" and #list<=limit,"Invalid "..label)
	for key in pairs(list) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#list,"Invalid "..label) end
	local seen={};for _,id in ipairs(list) do assert(type(id)=="string" and map.source().mods[id] and not seen[id],"Unknown or duplicate "..label);seen[id]=true end
	return seen
end
function M.run(state,options,checkpoint)
	assert(type(state)=="table" and type(options)=="table","Invalid map estimate")
	assert(state.twiceCorrupted==nil or type(state.twiceCorrupted)=="boolean","Invalid twice-corrupted map state")
	assert(not state.twiceCorrupted or state.corrupted,"A twice-corrupted map must be corrupted")
	local plannedAllflame=require("Modules.MapAllflame").validate(state.plannedAllflame)
	assert(state.plannedDeified==nil or type(state.plannedDeified)=="boolean","Invalid planned Deified marker")
	assert(state.vaalPreview==nil or type(state.vaalPreview)=="boolean","Invalid conditional Vaal preview marker")
	assert(not state.vaalPreview or state.corrupted,"A conditional Vaal preview requires a corrupted map")
	assert(state.vaalTierUpPreview==nil or type(state.vaalTierUpPreview)=="boolean","Invalid tier-up preview marker")
	assert(not state.vaalTierUpPreview or state.vaalPreview,"A tier-up preview requires a conditional Vaal preview")
	assert(not state.corrupted,"Corrupted maps cannot be rerolled")
	assert(state.implicit==nil,"A map corruption implicit requires a corrupted map")
	assert(not state.mirrored,"Mirrored maps cannot be rerolled")
	assert(not state.unidentified,"Identify the map before estimating rerolls")
	local rarity=state.rarity;assert(rarity=="magic" or rarity=="rare","Choose a magic or rare map to reroll")
	local wanted=options.wanted or {};local avoid=options.avoid or {};local must=ids(wanted,6,"wanted modifier");local forbidden=ids(avoid,100,"avoided modifier")
	local alternatives=options.wantedGroups or {};assert(type(alternatives)=="table" and #alternatives+#wanted<=6,"Use at most six wanted groups")
	for key in pairs(alternatives) do assert(type(key)=="number" and key==math.floor(key) and key>=1 and key<=#alternatives,"Invalid wanted groups") end
	local groups,total={},#wanted;for _,id in ipairs(wanted) do groups[#groups+1]={id} end
	for _,group in ipairs(alternatives) do
		local members=ids(group,100,"wanted alternative");assert(#group>0,"Wanted groups cannot be empty");total=total+#group;assert(total<=200,"Use at most 200 wanted alternatives")
		for id in pairs(members) do assert(not must[id],"Wanted groups cannot share a modifier");must[id]=true end
		groups[#groups+1]=copyTable(group)
	end
	assert(#groups+#avoid>0,"Choose at least one wanted or avoided modifier")
	for id in pairs(must) do assert(not forbidden[id],"A modifier cannot be both wanted and avoided") end
	local trials=integer(options.trials,1,1000,"trial count");local maxAttempts=integer(options.maxAttempts,1,1000,"attempt limit")
	local price=M.validatePrice(options.price)
	assert(trials*maxAttempts<=20000,"Use at most 20,000 total simulated attempts")
	local seed=integer(options.seed,1,2147483646,"estimate seed");local action=rarity=="magic" and "alteration" or "chaos"
	local base={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity=rarity,plannedDeified=state.plannedDeified or nil,plannedAllflame=plannedAllflame,plannedDelirium=require("Modules.MapObservedEffects").validateDeliriumPlan(state.plannedDelirium),selected={},quality=require("Modules.MapQuality").validate(state.quality),observedEffects=require("Modules.MapObservedEffects").validate(state.observedEffects)}
	assert(not require("Modules.MapObservedEffects").hasExplicit(base.observedEffects),"Reroll estimates are unavailable while unsupported explicit map modifiers are recorded")
	local progress={trial=1,trials=trials,attempts=0}
	local function slice() if checkpoint then checkpoint(progress) end end
	-- The ordered wanted list must itself be a supported ordinary-map state.
	local test=copyTable(base);test.selected=copyTable(wanted);currency.perform(test,action,seed,slice,true)
	local unavailableAvoid={}
	if #wanted>0 or #alternatives>0 or #avoid>0 then
		local eligible,offset={},0
		repeat local page=map.inspect(base.baseId,base.tier,base.itemLevel,{},"",offset,100,slice,rarity,nil,nil,nil,nil,base.observedEffects,map.isNightmare(base.baseId));for _,entry in ipairs(page.candidates) do eligible[entry.id]=true end;offset=page.nextOffset until not offset
		for _,id in ipairs(wanted) do assert(eligible[id],"A wanted modifier is not eligible for this modeled map") end
		for _,group in ipairs(alternatives) do for _,id in ipairs(group) do assert(eligible[id],"A wanted alternative is not eligible for this modeled map") end end
		for _,id in ipairs(avoid) do if not eligible[id] then unavailableAvoid[#unavailableAvoid+1]=id end end
	end
	-- Reject only contradictions proven by modeled modifier groups and
	-- prefix/suffix limits; a bounded search can leave harder cases unresolved.
	local mods=map.source().mods
	local function compatible(left,right)
		local a,b=mods[left],mods[right]
		if rarity=="magic" and a.generation_type==b.generation_type then return false end
		for _,one in ipairs(a.groups or {}) do for _,two in ipairs(b.groups or {}) do if one==two then return false end end end
		return true
	end
	for i=1,#groups do for j=i+1,#groups do
		local possible=false;local examined=0
		for _,left in ipairs(groups[i]) do
			for _,right in ipairs(groups[j]) do
				examined=examined+1;if examined%32==0 then slice() end
				if compatible(left,right) then possible=true;break end
			end
			if possible then break end
		end
		assert(possible,"Wanted groups "..i.." and "..j.." cannot coexist under the modeled map modifier rules. Change or remove a target.")
	end end
	-- Every group must contribute a distinct modifier. If more groups require
	-- one side than the item can hold, no combination can satisfy the target.
	local required={prefix=0,suffix=0};local limit=rarity=="magic" and 1 or 3
	for _,group in ipairs(groups) do
		local side=mods[group[1]].generation_type;local same=true
		for _,id in ipairs(group) do if mods[id].generation_type~=side then same=false;break end end
		if same then required[side]=required[side]+1 end
	end
	for _,side in ipairs({"prefix","suffix"}) do
		assert(required[side]<=limit,"Wanted targets cannot all coexist: at least "..required[side].." "..side.." modifiers are required, but this map supports at most "..limit..".")
	end
	local feasibilityUnverified=false
	if #groups>2 then
		-- The search only depends on side, conflict groups and Nightmare exclusivity.
		-- Collapse equivalent choices per target without changing the actual target.
		local ordered={}
		for index,group in ipairs(groups) do
			local choices,seen={},{}
			for _,id in ipairs(group) do
				local mod=mods[id];local names=copyTable(mod.groups or {});table.sort(names)
				local exclusive=false;for _,tag in ipairs(mod.adds_tags or {}) do if tag:match("^has_uber_map_") then exclusive=true;break end end
				local key=mod.generation_type..(exclusive and ":1" or ":0")
				for _,name in ipairs(names) do key=key..":"..#name..":"..name end
				if not seen[key] then seen[key]=true;choices[#choices+1]=id end
			end
			ordered[#ordered+1]={index=index,choices=choices}
		end
		table.sort(ordered,function(a,b) return #a.choices==#b.choices and a.index<b.index or #a.choices<#b.choices end)
		local occupied={};local counts={prefix=0,suffix=0};local exclusive={prefix=0,suffix=0};local limit=rarity=="magic" and 1 or 3
		local examined,exhausted=0,false
		local function search(index)
			if index>#ordered then
				return not map.isNightmare(base.baseId) or (counts.prefix<3 or exclusive.prefix>0) and (counts.suffix<3 or exclusive.suffix>0)
			end
			for _,id in ipairs(ordered[index].choices) do
				if examined>=20000 then exhausted=true;return false end
				examined=examined+1;if examined%32==0 then slice() end
				local mod=mods[id];local side=mod.generation_type;local legal=counts[side]<limit
				for _,group in ipairs(mod.groups or {}) do if occupied[group] then legal=false;break end end
				if legal then
					local isExclusive=false;for _,tag in ipairs(mod.adds_tags or {}) do if tag:match("^has_uber_map_") then isExclusive=true;break end end
					counts[side]=counts[side]+1;if isExclusive then exclusive[side]=exclusive[side]+1 end;for _,group in ipairs(mod.groups or {}) do occupied[group]=true end
					local found=search(index+1)
					counts[side]=counts[side]-1;if isExclusive then exclusive[side]=exclusive[side]-1 end;for _,group in ipairs(mod.groups or {}) do occupied[group]=nil end
					if found then return true end;if exhausted then return false end
				end
			end
			return false
		end
		local possible=search(1)
		feasibilityUnverified=not possible and exhausted
		assert(possible or exhausted,"Wanted targets cannot all coexist under the modeled map modifier rules"..(map.isNightmare(base.baseId) and ", including required Nightmare modifiers" or "")..". Change or remove a target.")
	end
	local successes,totalAttempts=0,0;local sample,successfulAttempts;local histogram={};local poolCache={}
	for trial=1,trials do
		for attempt=1,maxAttempts do
			totalAttempts=totalAttempts+1;progress.trial=trial;progress.attempt=attempt;progress.attempts=totalAttempts;local attemptSeed=encounter.seed(seed,totalAttempts,43)
			local result=currency.perform(base,action,attemptSeed,slice,true,poolCache);local found={}
			for _,id in ipairs(result.state.selected) do found[id]=true end
			local match=true;for _,group in ipairs(groups) do local any=false;for _,id in ipairs(group) do if found[id] then any=true;break end end;if not any then match=false;break end end
			if match then for id in pairs(forbidden) do if found[id] then match=false;break end end end
			if match then
				successes=successes+1;histogram[attempt]=(histogram[attempt] or 0)+1
				if not sample then sample=currency.perform(base,action,attemptSeed,slice,false,poolCache);successfulAttempts=attempt end
				break
			end
			slice()
		end
		slice()
	end
	local low,high=encounter.wilson(successes,trials);local distribution={}
	for attempt,count in pairs(histogram) do distribution[#distribution+1]={attempt=attempt,count=count} end
	table.sort(distribution,function(a,b) return a.attempt<b.attempt end)
	local cost
	if price then
		local function percentile(fraction)
			local rank=math.ceil(trials*fraction);local count=0
			for attempt=1,maxAttempts do
				count=count+(histogram[attempt] or 0)+(attempt==maxAttempts and trials-successes or 0)
				if count>=rank then return attempt*price.amount end
			end
		end
		-- Failures stop at the attempt limit; successful trials can all finish earlier.
		local observedMax=successes<trials and maxAttempts or distribution[#distribution].attempt
		cost={currency=price.currency,unitPrice=price.amount,totalSpent=totalAttempts*price.amount,meanSpent=totalAttempts/trials*price.amount,maxPerTrial=observedMax*price.amount,p50=percentile(0.5),p90=percentile(0.9),p99=percentile(0.99)}
	end
	return {plannedDelirium=base.plannedDelirium,plannedAllflame=base.plannedAllflame,allflame=require("Modules.MapAllflame").describe(base.plannedAllflame),plannedDeified=base.plannedDeified or nil,deified=require("Modules.MapObservedEffects").deified(base.observedEffects,base.plannedDeified),dataPatch=map.source().patch,dataSource=copyTable(map.source().source),feasibilityUnverified=feasibilityUnverified,trials=trials,maxAttempts=maxAttempts,successes=successes,successChance=successes/trials*100,confidenceLow=low,confidenceHigh=high,cost=cost,
		attempts=totalAttempts,meanAttempts=totalAttempts/trials,action=action,seed=seed,wanted=copyTable(wanted),wantedGroups=copyTable(alternatives),avoid=copyTable(avoid),unavailableAvoid=unavailableAvoid,
		successDistribution=distribution,sampleSuccess=sample and sample.state or nil,sampleSummary=sample and sample.summary or nil,sampleAttempts=successfulAttempts,
		note=(feasibilityUnverified and "Target feasibility was not established within the search limit. " or "").."Chance of meeting every wanted group (at least one alternative per group) and no avoided modifiers within the attempt limit. Wilson interval measures sampling uncertainty only. Map roll counts, weights, stat distributions and some restrictions are unverified estimates; no prices or game odds are inferred."..(price and " Costs use the supplied per-orb price and exclude the map and other resources. Spending percentiles include unsuccessful trials stopped at the attempt limit." or "")..(map.isNightmare(base.baseId) and " Nightmare estimates assume one exclusive prefix and suffix drawn first, followed by four weighted draws; generation order is unverified." or "")..(#unavailableAvoid>0 and " Some avoided modifiers cannot appear in the modeled pool for this map." or "")..require("Modules.MapObservedEffects").note(base.observedEffects)..(base.plannedDelirium and " Delirium remains a hypothetical target and is not applied to the map." or "")..(base.plannedAllflame and " Allflame is a conditional plan; reroll interactions, eligibility and stacking are unverified." or "")..(base.plannedDeified and " Deified is a conditional plan; reroll and other enchantment interactions, eligibility and Pantheon capture are unverified. Boss rarity is not included in map-wide totals." or "")}
end
return M
