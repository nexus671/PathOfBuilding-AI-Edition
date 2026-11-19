describe("Unique crafting recipes",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: UNIQUE\nGoldrim\nLeather Cap\nItem Level: 86\nQuality: 12\nSockets: R-G B"
	before_each(function() newBuild() end)
	it("runs supported deterministic actions, routes and supplied prices",function()
		local recipe={steps={{method="quality",maxAttempts=5,untilRequirements={minQuality=14}},{method="omen_connections"}},targets={},requirements={minQuality=14,links=3}}
		local result=sim.simulate(raw,recipe,{trials=10,maxActions=10,retainSuccesses=2,currency="chaos",baseCost=5,actionPrices={quality=2,omen_connections=10}})
		assert.is_true(result.uniqueCrafting);assert.is_false(result.sampled);assert.equal(100,result.successChance);assert.equal(10,result.successes)
		assert.equal(3,result.meanActions);assert.equal(19,result.meanCost);assert.equal(19,result.costPerSuccess)
		assert.equal(10,result.routeCounts[1].visits);assert.equal(20,result.routeCounts[1].executed);assert.equal(10,result.routeCounts[2].executed)
		assert.matches("Quality: 14",result.sampleItem);assert.matches("Sockets: R%-G%-B",result.sampleItem);assert.equal(2,#result.retainedSuccesses)
		local amounts={};for _,entry in ipairs(result.resourceUsage) do amounts[entry.key]=entry.amount end
		assert.equal(20,amounts["Metadata/Items/Currency/CurrencyArmourQuality"]);assert.equal(10,amounts["Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks"]);assert.equal(10,amounts["Metadata/Items/Currency/CurrencyRerollSocketLinks"])
	end)
	it("models corruption costs, stopping and bounded restarts",function()
		local recipe={steps={{method="socket_white_bench"}},targets={},requirements={socketColours="WWW",corrupted=true}}
		local result=sim.simulate(raw.."\nCorrupted",recipe,{trials=4,maxActions=2})
		assert.equal(100,result.successChance);assert.matches("Sockets: W%-W W",result.sampleItem)
		local amounts={};for _,entry in ipairs(result.resourceUsage) do amounts[entry.key]=entry.amount end
		assert.equal(4,amounts["Metadata/Items/Currency/CurrencyConvertToNormal"]);assert.equal(4,amounts["Metadata/Items/Currency/CurrencyCorrupt"]);assert.is_nil(result.meanCost)
		local restart={steps={{method="quality",untilRequirements={minQuality=40},onFailureAction="restart"}},targets={},requirements={minQuality=40}}
		result=sim.simulate(raw,restart,{trials=2,maxActions=3});assert.equal(0,result.successChance);assert.equal(3,result.meanActions);assert.equal(4,result.recovery.restarts);assert.equal(2,result.budgetExhausted)
		restart.steps[1].onFailureAction="stop";result=sim.simulate(raw,restart,{trials=2,maxActions=3});assert.equal(2,result.recovery.stopped);assert.equal(1,result.meanActions)
	end)
	it("uses shared resource quotes and preserves missing-price behavior",function()
		local recipe={steps={{method="quality",maxAttempts=5,untilRequirements={minQuality=14}},{method="omen_connections"}},targets={},requirements={minQuality=14,links=3}}
		local omen="Metadata/Items/Currency/AncestralOmenOnFusingMakeFullLinks";local fusing="Metadata/Items/Currency/CurrencyRerollSocketLinks"
		local book={currency="chaos",source="Manual",quotedAt=1700000000,values={quality=1,[omen]=5,[fusing]=2}}
		local result=sim.simulate(raw,recipe,{trials=2,maxActions=10,baseCost=3,priceBook=book})
		assert.equal(12,result.meanCost);assert.equal("chaos",result.costCurrency);assert.equal("Manual",result.priceSource)
		result=sim.simulate(raw,recipe,{trials=2,maxActions=10,baseCost=3,priceBook=book,actionPrices={omen_connections=0}})
		assert.equal(5,result.meanCost);assert.equal(2,result.actionPriceOverridesApplied)
		book.values[fusing]=nil;result=sim.simulate(raw,recipe,{trials=2,maxActions=10,priceBook=book})
		assert.is_nil(result.meanCost);assert.is_true(result.unpriced[fusing])
		book.values["Metadata/Items/Currency/CurrencyArmourQuality"]=3
		assert.has_error(function() sim.simulate(raw,recipe,{trials=1,maxActions=10,priceBook=book}) end)
	end)
	it("follows failure routes without charging rejected actions",function()
		local recipe={steps={{method="quality",maxAttempts=10,untilRequirements={minQuality=21},onFailure=2},{method="socket_white_bench"}},targets={},requirements={socketColours="WWW"}}
		local result=sim.simulate(raw,recipe,{trials=2,maxActions=20})
		assert.equal(100,result.successChance);assert.equal(10,result.meanActions);assert.equal(9,result.meanExecutedActions);assert.equal(2,result.failedAttempts)
		assert.equal(2,result.failedTransitionTrials);assert.equal("rejected_model_actions",result.warnings[2].code);assert.is_truthy(next(result.transitionErrors))
		assert.equal(2,result.routeCounts[1].failure);assert.equal(2,result.routeCounts[2].success)
		local amounts={};for _,entry in ipairs(result.resourceUsage) do amounts[entry.key]=entry.amount end
		assert.equal(16,amounts["Metadata/Items/Currency/CurrencyArmourQuality"]);assert.equal(2,amounts["Metadata/Items/Currency/CurrencyConvertToNormal"])
	end)
	it("rejects unsupported unique methods, modifier targets and ordinary states",function()
		assert.has_error(function() sim.simulate(raw,{steps={{method="vaal"}},targets={},requirements={minQuality=20}},{trials=1}) end)
		assert.has_error(function() sim.simulate(raw,{steps={{method="quality",allflame={auto=true}}},targets={},requirements={minQuality=20}},{trials=1}) end)
		assert.has_error(function() sim.simulate(raw,{steps={{method="quality"}},targets={{anyOf={"Life1"}}}},{trials=1}) end)
		assert.has_error(function() sim.simulate(raw,{steps={{method="quality"}},targets={},requirements={minQuality=20},initialState={rarity="RARE",affixes={}}},{trials=1}) end)
		assert.has_error(function() sim.simulate(raw,{steps={{method="quality"}},targets={},requirements={minQuality=20}},{trials=1,currency="chaos",prices={quality=-1}}) end)
	end)
end)
