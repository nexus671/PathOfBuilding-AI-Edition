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
	assert(#wanted+#avoid>0,"Choose at least one wanted or avoided modifier")
	for id in pairs(must) do assert(not forbidden[id],"A modifier cannot be both wanted and avoided") end
	local trials=integer(options.trials,1,1000,"trial count");local maxAttempts=integer(options.maxAttempts,1,1000,"attempt limit")
	assert(trials*maxAttempts<=20000,"Use at most 20,000 total simulated attempts")
	local seed=integer(options.seed,1,2147483646,"estimate seed");local action=rarity=="magic" and "alteration" or "chaos"
	local base={baseId=state.baseId,tier=state.tier,itemLevel=state.itemLevel,rarity=rarity,selected={}}
	local progress={trial=1,trials=trials,attempts=0}
	local function slice() if checkpoint then checkpoint(progress) end end
	-- The ordered wanted list must itself be a supported ordinary-map state.
	local test=copyTable(base);test.selected=copyTable(wanted);currency.perform(test,action,seed,slice,true)
	local successes,totalAttempts=0,0;local sample,successfulAttempts;local histogram={}
	for trial=1,trials do
		for attempt=1,maxAttempts do
			totalAttempts=totalAttempts+1;progress.trial=trial;progress.attempt=attempt;progress.attempts=totalAttempts;local attemptSeed=encounter.seed(seed,totalAttempts,43)
			local result=currency.perform(base,action,attemptSeed,slice,true);local found={}
			for _,id in ipairs(result.state.selected) do found[id]=true end
			local match=true;for id in pairs(must) do if not found[id] then match=false;break end end
			if match then for id in pairs(forbidden) do if found[id] then match=false;break end end end
			if match then
				successes=successes+1;histogram[attempt]=(histogram[attempt] or 0)+1
				if not sample then sample=currency.perform(base,action,attemptSeed,slice);successfulAttempts=attempt end
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
		attempts=totalAttempts,meanAttempts=totalAttempts/trials,action=action,seed=seed,wanted=copyTable(wanted),avoid=copyTable(avoid),
		successDistribution=distribution,sampleSuccess=sample and sample.state or nil,sampleSummary=sample and sample.summary or nil,sampleAttempts=successfulAttempts,
		note="Chance of meeting all wanted and no avoided modifiers within the attempt limit. Wilson interval measures sampling uncertainty only. Map roll counts, weights, stat distributions and some restrictions are unverified estimates; no prices or game odds are inferred."}
end
return M
