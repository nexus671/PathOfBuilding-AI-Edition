-- Bounded Monte Carlo estimates for ordinary-map rerolls, not game odds.
local map=require("Modules.MapCraftingData")
local currency=require("Modules.MapCurrency")
local encounter=require("Modules.CalcEncounter")
local M={}
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
	assert(trials*maxAttempts<=20000,"Use at most 20,000 total simulated attempts")
	local seed=integer(options.seed,1,2147483646,"estimate seed");local action=rarity=="magic" and "alteration" or "chaos"
	local base={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity=rarity,selected={}}
	local progress={trial=1,trials=trials,attempts=0}
	local function slice() if checkpoint then checkpoint(progress) end end
	-- The ordered wanted list must itself be a supported ordinary-map state.
	local test=copyTable(base);test.selected=copyTable(wanted);currency.perform(test,action,seed,slice,true)
	if #alternatives>0 then
		local eligible,offset={},0
		repeat local page=map.inspect(base.baseId,base.tier,base.itemLevel,{},"",offset,100,slice,rarity);for _,entry in ipairs(page.candidates) do eligible[entry.id]=true end;offset=page.nextOffset until not offset
		for _,group in ipairs(alternatives) do for _,id in ipairs(group) do assert(eligible[id],"A wanted alternative is not eligible for this modeled map") end end
	end
	-- Reject only pairwise contradictions we can prove from the modeled
	-- modifier groups and magic-map prefix/suffix limits. More complex
	-- incompatibilities can still produce zero sampled successes.
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
	return {trials=trials,maxAttempts=maxAttempts,successes=successes,successChance=successes/trials*100,confidenceLow=low,confidenceHigh=high,
		attempts=totalAttempts,meanAttempts=totalAttempts/trials,action=action,seed=seed,wanted=copyTable(wanted),wantedGroups=copyTable(alternatives),avoid=copyTable(avoid),
		successDistribution=distribution,sampleSuccess=sample and sample.state or nil,sampleSummary=sample and sample.summary or nil,sampleAttempts=successfulAttempts,
		note="Chance of meeting every wanted group (at least one alternative per group) and no avoided modifiers within the attempt limit. Wilson interval measures sampling uncertainty only. Map roll counts, weights, stat distributions and some restrictions are unverified estimates; no prices or game odds are inferred."}
end
return M
