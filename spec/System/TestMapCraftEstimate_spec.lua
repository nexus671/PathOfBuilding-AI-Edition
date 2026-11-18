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
	it("preserves seeded outcomes and values when modifier pools are reused",function()
		local cache={}
		for _,seed in ipairs({1,42,123,777,42}) do
			assert.same(currency.perform(state,"chaos",seed),currency.perform(state,"chaos",seed,nil,false,cache))
		end
		local magic=copyTable(state);magic.rarity="magic"
		assert.same(currency.perform(magic,"alteration",42),currency.perform(magic,"alteration",42,nil,false,cache))
		local low=copyTable(state);low.tier=5;low.itemLevel=68
		assert.same(currency.perform(low,"chaos",42),currency.perform(low,"chaos",42,nil,false,cache))
		assert.is_true(cache._count<=128)
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
		assert.is_true(one.successes>0)
		local ok,err=pcall(estimate.run,low,{wantedGroups={{fire},{cold}},trials=10,maxAttempts=4,seed=77})
		assert.is_false(ok);assert.matches("Wanted groups 1 and 2 cannot coexist",err)
		local valid=estimate.run(low,{wantedGroups={{fire,cold},{"MapMonsterAreaOfEffectMapWorlds"}},trials=1,maxAttempts=1,seed=77});assert.equal(1,valid.trials)
	end)
	it("allows a compatible alternative and rejects two magic modifiers on one side",function()
		local low=copyTable(state);low.tier=5;low.itemLevel=68
		local fire,cold="MapMonsterFireDamageMapWorlds","MapMonsterColdDamageMapWorlds"
		local result=estimate.run(low,{wantedGroups={{fire,"MapContainsMirageWorlds"},{cold}},trials=1,maxAttempts=1,seed=77})
		assert.equal(1,result.trials)
		local magic=copyTable(low);magic.rarity="magic"
		local ok,err=pcall(estimate.run,magic,{wantedGroups={{"MapMonsterAreaOfEffectMapWorlds"},{"MapMonsterCriticalStrikesAndDamageMapWorlds"}},trials=1,maxAttempts=1,seed=77})
		assert.is_false(ok);assert.matches("Wanted groups 1 and 2 cannot coexist",err)
	end)
	it("rejects collectively impossible targets while accepting a compatible alternative",function()
		local low=copyTable(state);low.tier=5;low.itemLevel=68
		local a,b,c,d="MapBossPossessedMapWorlds","MapDangerousBoss1MapWorlds","MapMonsterCannotBeStunnedMapWorlds_","MapMonsterChainMapWorlds"
		local options={wantedGroups={{a},{b},{c},{d}},trials=1,maxAttempts=1,seed=77}
		local ok,err=pcall(estimate.run,low,options);assert.is_false(ok);assert.matches("Wanted targets cannot all coexist",err)
		options.wantedGroups[4]={d,"MapMonsterAreaOfEffectMapWorlds"}
		assert.equal(1,estimate.run(low,options).trials)
	end)
	it("rejects three magic targets even when every pair has compatible alternatives",function()
		local magic=copyTable(state);magic.rarity="magic";magic.tier=5;magic.itemLevel=68
		local candidates=require("Modules.MapCraftingData").inspect(magic.baseId,magic.tier,magic.itemLevel,{},"",0,100,nil,"magic").candidates
		local picked={prefix={},suffix={}};local seen={}
		for _,entry in ipairs(candidates) do
			local distinct=true;for _,group in ipairs(entry.groups) do if seen[group] then distinct=false end end
			if distinct and #picked[entry.side]<3 then picked[entry.side][#picked[entry.side]+1]=entry.id;for _,group in ipairs(entry.groups) do seen[group]=true end end
		end
		assert.equal(3,#picked.prefix);assert.equal(3,#picked.suffix)
		local groups={};for i=1,3 do groups[i]={picked.prefix[i],picked.suffix[i]} end
		local ok,err=pcall(estimate.run,magic,{wantedGroups=groups,trials=1,maxAttempts=1,seed=77})
		assert.is_false(ok);assert.matches("Wanted targets cannot all coexist",err)
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
