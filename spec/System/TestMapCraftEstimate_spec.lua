describe("Map reroll estimates",function()
	local estimate=require("Modules.MapCraftEstimate");local currency=require("Modules.MapCurrency")
	local state={baseId="Metadata/Items/Maps/MapWorldsStrand",tier=16,itemLevel=83,rarity="rare",selected={}}
	it("reports a bounded probability and resource use without mutating the map",function()
		local options={wanted={},avoid={"MapMonsterAreaOfEffectMapWorlds"},trials=20,maxAttempts=3,seed=42}
		local updates=0;local result=estimate.run(state,options,function(progress) assert.is_truthy(progress.trial);assert.equal(20,progress.trials);updates=updates+1 end);local repeated=estimate.run(state,options)
		assert.is_true(updates>0)
		assert.same(result,repeated);assert.equal(20,result.successes);assert.equal(20,result.attempts);assert.equal(100,result.successChance)
		assert.is_true(result.confidenceLow<100);assert.equal("chaos",result.action);assert.equal(1,result.meanAttempts)
		assert.is_truthy(result.sampleSuccess);assert.equal(#result.sampleSuccess.selected,#result.sampleSuccess.rolls)
		assert.same({},state.selected);assert.matches("sampling uncertainty only",result.note)
	end)
	it("uses the same modifier identities in fast and full rolls",function()
		local full=currency.perform(state,"chaos",123);local fast=currency.perform(state,"chaos",123,nil,true)
		assert.same(full.state.selected,fast.state.selected);assert.same({},fast.state.rolls);assert.is_nil(fast.summary)
	end)
	it("requires wanted modifiers and excludes avoided ones from retained successes",function()
		local wanted="MapContainsMirageWorlds";local avoid="MapContainsWildwoodWorlds"
		local result=estimate.run(state,{wanted={wanted},avoid={avoid},trials=5,maxAttempts=4,seed=77})
		assert.is_true(result.attempts>=5 and result.attempts<=20);assert.is_true(result.successes>=0 and result.successes<=5)
		assert.is_truthy(result.sampleSuccess);local seen={};for _,id in ipairs(result.sampleSuccess.selected) do seen[id]=true end
		assert.is_true(seen[wanted]);assert.is_nil(seen[avoid]);assert.is_true(result.sampleAttempts<=4)
	end)
	it("accepts any explicit alternative within a wanted group",function()
		local a,b="MapContainsMirageWorlds","MapContainsWildwoodWorlds"
		local result=estimate.run(state,{wantedGroups={{a,b}},trials=5,maxAttempts=4,seed=77})
		assert.same({{a,b}},result.wantedGroups);assert.is_truthy(result.sampleSuccess)
		local found={};for _,id in ipairs(result.sampleSuccess.selected) do found[id]=true end
		assert.is_true((found[a] and not found[b]) or (found[b] and not found[a]))
	end)
	it("requires every wanted group rather than any group",function()
		local low=copyTable(state);low.tier=5;low.itemLevel=68
		local fire,cold="MapMonsterFireDamageMapWorlds","MapMonsterColdDamageMapWorlds"
		local one=estimate.run(low,{wantedGroups={{fire}},trials=10,maxAttempts=4,seed=77})
		local both=estimate.run(low,{wantedGroups={{fire},{cold}},trials=10,maxAttempts=4,seed=77})
		assert.is_true(one.successes>0);assert.equal(0,both.successes)
	end)
	it("rejects contradictory, ineligible and unbounded requests",function()
		local options={wanted={"MapMonsterAreaOfEffectMapWorlds"},avoid={},trials=1,maxAttempts=1,seed=42}
		assert.has_error(function() estimate.run(state,options) end)
		assert.has_error(function() estimate.run(state,{wanted={},avoid={},trials=1,maxAttempts=1,seed=1}) end)
		assert.has_error(function() estimate.run(state,{wanted={},avoid={"unknown"},trials=1,maxAttempts=1,seed=1}) end)
		assert.has_error(function() estimate.run(state,{wanted={"MapContainsMirageWorlds"},avoid={"MapContainsMirageWorlds"},trials=1,maxAttempts=1,seed=1}) end)
		assert.has_error(function() estimate.run(state,{wanted={},wantedGroups={{}},avoid={},trials=1,maxAttempts=1,seed=1}) end)
		assert.has_error(function() estimate.run(state,{wanted={"MapContainsMirageWorlds"},wantedGroups={{"MapContainsMirageWorlds"}},avoid={},trials=1,maxAttempts=1,seed=1}) end)
		assert.has_error(function() estimate.run(state,{wanted={},wantedGroups={{"MapContainsMirageWorlds"}},avoid={"MapContainsMirageWorlds"},trials=1,maxAttempts=1,seed=1}) end)
		assert.has_error(function() estimate.run(state,{wanted={},avoid={"MapMonsterAreaOfEffectMapWorlds"},trials=1000,maxAttempts=21,seed=1}) end)
	end)
end)
