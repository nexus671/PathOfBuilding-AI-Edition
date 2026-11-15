describe("Experimental Gwennen pair",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
	local function item()
		local model=sim.model(raw);local state=sim.perform(raw,{method="alchemy"},4).state
		while #state.affixes>3 do state=sim.action(model,state,{method="annul"},function() return 0.3 end) end
		return model,state
	end
	it("selects either observed branch without changing the input",function()
		local model,state=item();local original=copyTable(state)
		local pair={method="gwennen",firstOutcome=1000,secondOutcome=1022}
		local intact,first=sim.action(model,state,pair,function() return 0.1 end)
		local destroyed,second=sim.action(model,state,pair,function() return 0.9 end)
		assert.same(original,state);assert.same(original,intact);assert.is_true(destroyed.destroyed);assert.equal(0,#destroyed.affixes)
		assert.equal(1000,first.gwennen.outcome);assert.equal(1022,second.gwennen.outcome)
	end)
	it("runs add and remove branches and reports estimates on calculations",function()
		local model,state=item();local pair={method="gwennen",firstOutcome=1004,secondOutcome=1005}
		local removed=sim.action(model,state,pair,function() return 0.1 end)
		local added=sim.action(model,state,pair,function() return 0.9 end)
		assert.equal(#state.affixes-1,#removed.affixes);assert.equal(#state.affixes+1,#added.affixes)
		local result=sim.perform(raw,pair,7,state);assert.equal("gwennen_estimate",result.warnings[1].code);assert.is_not_nil(result.gwennen.outcome)
		local odds=sim.calculate(raw,pair,{},state,{requirements={minAffixes=1},trials=4});assert.equal("gwennen_estimate",odds.warnings[1].code)
	end)
	it("charges observed artifacts and never treats an unknown price as free",function()
		local pair={method="gwennen",firstOutcome=1000,secondOutcome=1022}
		local astragali="Metadata/Items/Currency/CurrencyRefreshGambler"
		local grand="Metadata/Items/Expedition/ExpeditionVendorCurrencyFaction1_3"
		assert.same({[astragali]=1,["gwennen:observed_artifacts"]=1},sim.components(pair))
		pair.artifactCost={grand=20};assert.same({[astragali]=1,[grand]=20},sim.components(pair))
		local _,state=item();local result=sim.simulate(raw,{initialState=state,steps={pair},targets={},requirements={minQuality=20}},{trials=2,maxActions=1})
		local usage={};for _,entry in ipairs(result.resourceUsage) do usage[entry.key]=entry.amount end
		assert.equal(2,usage[astragali]);assert.equal(40,usage[grand]);assert.is_nil(result.meanCost)
		assert.has_error(function() sim.components({method="gwennen",firstOutcome=1000,secondOutcome=1022,artifactCost={grand=-1}}) end)
		assert.has_error(function() sim.validateRecipe({steps={{method="gwennenu",firstOutcome=1000,secondOutcome=1022}},targets={},requirements={minAffixes=1}}) end)
		assert.has_error(function() sim.validateRecipe({steps={{method="gwennen",firstOutcome=1000,secondOutcome=1044}},targets={},requirements={minAffixes=1}}) end)
	end)
	it("models the quality and modifier reroll branches",function()
		local model,state=item();local before=copyTable(state)
		local quality=sim.action(model,state,{method="gwennen",firstOutcome=1029,secondOutcome=1000},function() return 0.1 end)
		assert.equal(20,quality.quality);assert.same(before.affixes,quality.affixes)
		local rerolled=sim.action(model,state,{method="gwennen",firstOutcome=1014,secondOutcome=1015},function() return 0.1 end)
		assert.equal("RARE",rerolled.rarity);assert.is_true(#rerolled.affixes>=4)
		local values=sim.action(model,state,{method="gwennen",firstOutcome=1014,secondOutcome=1015},function() return 0.9 end)
		for i,entry in ipairs(values.affixes) do assert.equal(before.affixes[i].id,entry.id) end
		assert.same(before,state)
	end)
	it("rejects unsupported pairs and a pair with an unusable branch",function()
		local model,state=item()
		assert.has_error(function() sim.action(model,state,{method="gwennen",firstOutcome=1000,secondOutcome=1044},function() return 0.1 end) end)
		state.affixes={}
		assert.has_error(function() sim.action(model,state,{method="gwennen",firstOutcome=1000,secondOutcome=1004},function() return 0.1 end) end)
		state.corrupted=true
		assert.has_error(function() sim.action(model,state,{method="gwennen",firstOutcome=1000,secondOutcome=1022},function() return 0.1 end) end)
	end)
end)
