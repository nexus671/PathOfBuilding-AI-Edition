describe("Sacred Orb previews for unique armour", function()
	local unique=require("Modules.CraftingUniqueQuality")
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: UNIQUE\nThe Apostate\nSavant's Robe\nItem Level: 86\nEnergy Shield: 132\nImplicits: 0\nGain Maximum Life instead of Maximum Energy Shield from Equipped Armour Items"
	it("updates displayed and internal defences while preserving the unique", function()
		local seen={}
		for seed=1,20 do
			local result=unique.sacred(raw,seed*104729);local item=unique.inspect(result.itemText)
			assert.equal(item.armourData.EnergyShield,tonumber(result.itemText:match("\nEnergy Shield:%s*(%d+)")))
			assert.matches("Gain Maximum Life instead",result.itemText);assert.equal(1,result.components.sacred)
			assert.equal(result.itemText,unique.sacred(raw,seed*104729).itemText)
			assert.is_truthy(unique.sacred(result.itemText,seed*130363));seen[item.armourData.EnergyShield]=true
		end
		local count=0;for _ in pairs(seen) do count=count+1 end;assert.is_true(count>1)
		local windows=unique.sacred(raw:gsub("\n","\r\n"),104729)
		assert.is_truthy(windows.itemText:find("\r\nEnergyShieldBasePercentile:",1,true))
	end)
	it("updates both defences on hybrid armour and rejects corrupted items", function()
		local hybrid="Rarity: UNIQUE\nThe Restless Ward\nCarnal Armour\nItem Level: 86\nEvasion Rating: 300\nEnergy Shield: 50\nImplicits: 0\n+50 to maximum Life"
		local result=unique.sacred(hybrid,314159);local item=unique.inspect(result.itemText)
		assert.equal(item.armourData.Evasion,tonumber(result.itemText:match("\nEvasion Rating:%s*(%d+)")))
		assert.equal(item.armourData.EnergyShield,tonumber(result.itemText:match("\nEnergy Shield:%s*(%d+)")))
		assert.is_truthy(unique.sacredReason(raw.."\nCorrupted"))
		assert.is_false(pcall(unique.sacred,raw.."\nCorrupted",314159))
	end)
	it("offers and simulates the action with its priced resource", function()
		local options=sim.catalog(raw,"sacred",20).uniqueActions;assert.equal(1,#options);assert.is_true(options[1].available)
		local result=sim.perform(raw,{method="sacred"},104729);assert.equal(1,result.components.sacred)
		local recipe={rarity="UNIQUE",steps={{method="sacred",maxAttempts=1}},targets={},requirements={nativeStats={EnergyShield=1}}}
		local run=sim.simulate(raw,recipe,{trials=3,maxActions=1,forceFirstAction=true,seed=104729,prices={sacred=2},currency="chaos"})
		assert.equal(3,run.currencySpent.sacred);assert.equal(2,run.meanCost)
	end)
	it("explains unsafe item text before offering a preview", function()
		local cases={
			{raw:gsub("Item Level: 86", "Item Level: 86\nItem Level: 86"),"Could not safely locate item level"},
			{raw.."\nEnergyShieldBasePercentile: 0.5\nEnergyShieldBasePercentile: 0.8","Duplicate base defence percentile"},
			{raw.."\nEnergy Shield: 100","Duplicate base defence property"},
			{raw:gsub("Energy Shield: 132","Energy Shield: unknown"),"Could not safely update displayed defence"},
		}
		for _,case in ipairs(cases) do
			assert.equal(case[2],unique.sacredReason(case[1]))
			local options=sim.catalog(case[1],"sacred",20).uniqueActions
			assert.equal(1,#options);assert.is_false(options[1].available)
			assert.has_error(function() unique.sacred(case[1],104729) end)
		end
	end)
end)
