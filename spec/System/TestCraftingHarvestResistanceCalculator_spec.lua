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
end)
