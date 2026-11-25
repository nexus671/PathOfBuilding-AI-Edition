describe("Harvest resistance conversion calculator",function()
	local sim=require("Modules.CraftingSimulator")
	it("enumerates identity outcomes and samples value-dependent targets",function()
		local blank=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local fire
		for _,entry in ipairs(blank.mods) do if entry.mod.group=="FireResistance" and blank.byId[entry.id:gsub("Fire","Cold")] then fire=entry.id;break end end
		assert.is_truthy(fire)
		local item=new("Item"):Item("Rarity: RARE\nLegacy Hat\nIron Hat\nItem Level: 86\nCrafted: true\nPrefix: DelveArmourFireResistance1\nSuffix: "..fire);item:Craft()
		local model=sim.model(item.raw);local before=copyTable(model.initial)
		local action={method="harvest_resistance",from="fire",to="cold"}
		local result=sim.calculate(item.raw,action,{{anyOf={"DelveArmourColdResistance1"}}},nil,{})
		assert.is_false(result.sampled);assert.is_true(result.showAllOutcomes);assert.equal(50,result.successChance)
		assert.equal(2,#result.outcomes);assert.matches("assumed",result.exactFor)
		local choices={};for _,row in ipairs(result.outcomes) do choices[row.sourceId]=row end
		assert.equal("DelveArmourColdResistance1",choices.DelveArmourFireResistance1.targetId)
		assert.equal(50,choices.DelveArmourFireResistance1.chance);assert.is_true(choices.DelveArmourFireResistance1.matches)
		assert.is_false(choices[fire].matches);assert.equal("harvest_resistance_assumptions",result.warnings[1].code)
		assert.same(before,model.initial)
		local sampled=sim.calculate(item.raw,action,{{anyOf={"DelveArmourColdResistance1"},minRoll=0.9}},nil,{trials=10,seed=3})
		assert.is_true(sampled.sampled);assert.equal(10,sampled.trials)
		for _,target in ipairs({{anyOf={"NotARealModifier"}},{anyOf={"NotARealModifier"},minRoll=0.9}}) do
			local ok,err=pcall(sim.calculate,item.raw,action,{target},nil,{trials=10,seed=3})
			assert.is_false(ok);assert.matches("Target modifier ID is unavailable",err)
		end
	end)
	it("prices conversion directions independently while honoring old overrides",function()
		local blank=sim.model("Rarity: NORMAL\nIron Hat\nItem Level: 86");local fire
		for _,entry in ipairs(blank.mods) do if entry.mod.group=="FireResistance" and blank.byId[entry.id:gsub("Fire","Cold")] then fire=entry.id;break end end
		assert.is_truthy(fire)
		local item=new("Item"):Item("Rarity: RARE\nLegacy Hat\nIron Hat\nItem Level: 86\nCrafted: true\nPrefix: DelveArmourFireResistance1\nSuffix: "..fire);item:Craft()
		local first={method="harvest_resistance",from="fire",to="cold"};local second={method="harvest_resistance",from="cold",to="lightning"}
		assert.equal("harvest_resistance:fire:cold",sim.priceKey(first));assert.equal("harvest_resistance:cold:lightning",sim.priceKey(second))
		local recipe={steps={first,second},targets={},requirements={minAffixes=6}}
		local function run(prices,actions) return sim.simulate(item.raw,recipe,{trials=1,maxActions=2,seed=3,forceFirstAction=true,currency="chaos",prices=prices,actionPrices=actions}) end
		local split=run(nil,{[sim.priceKey(first)]=2,[sim.priceKey(second)]=7});assert.equal(9,split.meanCost);assert.equal(2,split.actionPriceOverridesApplied)
		local legacy=run(nil,{harvest_resistance=2});assert.equal(4,legacy.meanCost)
		local mixed=run(nil,{harvest_resistance=2,[sim.priceKey(second)]=7});assert.equal(9,mixed.meanCost)
		local oldResource=run({harvest_resistance=2},nil);assert.equal(4,oldResource.meanCost)
		local mixedResource=run({harvest_resistance=2,[sim.priceKey(second)]=7},nil);assert.equal(9,mixedResource.meanCost)
		local saved=sim.simulate(item.raw,recipe,{trials=1,maxActions=2,seed=3,forceFirstAction=true,currency="chaos",priceBook={currency="chaos",source="Manual",quotedAt=1700000000,values={harvest_resistance=2,[sim.priceKey(second)]=7}}})
		assert.equal(9,saved.meanCost);assert.equal("Manual",saved.priceSource)

	end)
end)
