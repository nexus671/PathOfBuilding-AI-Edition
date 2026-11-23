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
	it("uses one shared position for hybrid base defences in both crafting paths", function()
		local ordinary="Rarity: NORMAL\nCarnal Armour\nItem Level: 86"
		local model=sim.model(ordinary);local armour=model.item.base.armour
		local hybrid="Rarity: UNIQUE\nThe Restless Ward\nCarnal Armour\nItem Level: 86\nEvasion Rating: 300\nEnergy Shield: 50\nImplicits: 0\n+50 to maximum Life"
		for position=0,31 do
			local state=sim.action(model,model.initial,{method="sacred"},function() return (position+0.5)/32 end)
			for _,kind in ipairs({"Evasion","EnergyShield"}) do
				local low,high=armour[kind.."BaseMin"],armour[kind.."BaseMax"]
				local expected=math.floor(low+(high-low)*position/31+0.5)
				assert.are.near(expected,low+(high-low)*state.percentiles[kind],1e-9)
			end
		end
		for seed=1,20 do
			local item=unique.inspect(unique.sacred(hybrid,seed*104729).itemText);local found=false
			for position=0,31 do
				local function base(kind) local low,high=armour[kind.."BaseMin"],armour[kind.."BaseMax"];return math.floor(low+(high-low)*position/31+0.5) end
				if item.armourData.EvasionBase==base("Evasion") and item.armourData.EnergyShieldBase==base("EnergyShield") then found=true;break end
			end
			assert.is_true(found)
		end
	end)
	it("offers and simulates the action with its priced resource", function()
		local options=sim.catalog(raw,"sacred",20).uniqueActions;assert.equal(1,#options);assert.is_true(options[1].available)
		local result=sim.perform(raw,{method="sacred"},104729);assert.equal(1,result.components.sacred)
		local warning;for _,entry in ipairs(result.warnings) do if entry.code=="unique_sacred_estimate" then warning=entry.message end end
		assert.matches("shared roll",assert(warning));assert.matches("unverified",warning)
		local recipe={rarity="UNIQUE",steps={{method="sacred",maxAttempts=1}},targets={},requirements={nativeStats={EnergyShield=1}}}
		local run=sim.simulate(raw,recipe,{trials=3,maxActions=1,forceFirstAction=true,seed=104729,prices={sacred=2},currency="chaos"})
		assert.equal(3,run.currencySpent.sacred);assert.equal(2,run.meanCost)
		local recipeWarning;for _,entry in ipairs(run.warnings) do if entry.code=="unique_sacred_estimate" then recipeWarning=entry.message end end
		assert.matches("shared roll",assert(recipeWarning))
		local ordinary=sim.perform("Rarity: NORMAL\nCarnal Armour\nItem Level: 86",{method="sacred"},104729)
		local ordinaryWarning;for _,entry in ipairs(ordinary.warnings) do if entry.code=="sacred_roll_assumptions" then ordinaryWarning=entry.message end end
		assert.matches("shared roll",assert(ordinaryWarning));assert.matches("unverified",ordinaryWarning)
	end)
	it("enumerates single-action targets under the shared-roll model", function()
		local ordinary="Rarity: NORMAL\nCarnal Armour\nItem Level: 86"
		local hybrid="Rarity: UNIQUE\nThe Restless Ward\nCarnal Armour\nItem Level: 86\nEvasion Rating: 300\nEnergy Shield: 50\nImplicits: 0\n+50 to maximum Life"
		for _,item in ipairs({ordinary,hybrid}) do
			local result=sim.calculate(item,{method="sacred"},{},nil,{requirements={nativeStats={EnergyShield=105}}})
			assert.is_false(result.sampled);assert.equal(32,#result.outcomes);assert.equal(84.375,result.successChance)
			assert.matches("unverified",result.exactFor);assert.equal(1,result.totalWeight);assert.equal(27/32,result.matchingWeight)
			local total,matching=0,0
			for _,outcome in ipairs(result.outcomes) do
				total=total+outcome.weight;if outcome.matches then matching=matching+outcome.weight end
				assert.matches("Energy shield",outcome.text)
			end
			assert.equal(1,total);assert.equal(result.matchingWeight,matching)
		end
	end)
	it("combines identical Sacred outcomes without changing their total chance", function()
		for _,case in ipairs({
			{item="Rarity: NORMAL\nIron Hat\nItem Level: 86",stat="Armour",count=5},
			{item=raw,stat="EnergyShield",count=18},
		}) do
			local result=sim.calculate(case.item,{method="sacred"},{},nil,{requirements={nativeStats={[case.stat]=1}}})
			assert.is_false(result.sampled);assert.equal(case.count,#result.outcomes);assert.equal(100,result.successChance)
			local total,combined=0,false
			for _,outcome in ipairs(result.outcomes) do
				total=total+outcome.weight;assert.equal(outcome.weight*100,outcome.chance)
				if outcome.weight>1/32 then combined=true end
			end
			assert.equal(1,total);assert.is_true(combined)
			if case.stat=="Armour" then for index,chance in ipairs({12.5,25,25,25,12.5}) do assert.equal(chance,result.outcomes[index].chance) end end
		end
	end)
	it("uses the chosen seed for the example without changing exact modeled odds", function()
		local ordinary="Rarity: NORMAL\nCarnal Armour\nItem Level: 86"
		local hybrid="Rarity: UNIQUE\nThe Restless Ward\nCarnal Armour\nItem Level: 86\nEvasion Rating: 300\nEnergy Shield: 50\nImplicits: 0\n+50 to maximum Life"
		for _,item in ipairs({ordinary,hybrid}) do
			local previous
			for _,seed in ipairs({1,104729,123456}) do
				local result=sim.calculate(item,{method="sacred"},{},nil,{seed=seed,requirements={nativeStats={EnergyShield=105}}})
				local applied=sim.perform(item,{method="sacred"},seed)
				assert.equal(applied.itemText,result.sampleItem);assert.equal(84.375,result.successChance)
				assert.equal(seed~=1,result.sampleSuccess)
				if result.nativeStats then assert.equal(unique.inspect(result.sampleItem).armourData.EnergyShield,result.nativeStats.EnergyShield) end
				if result.sampleState then assert.equal(result.sampleItem,sim.itemText(sim.model(item),result.sampleState)) end
				if previous then assert.is_true(previous~=result.sampleItem) end;previous=result.sampleItem
			end
		end
		local model=sim.model(ordinary);local initial=copyTable(model.initial);initial.quality=20
		local requirements={nativeStats={EnergyShield=130}}
		local result=sim.calculate(ordinary,{method="sacred"},{},initial,{seed=1,requirements=requirements})
		local applied=sim.perform(ordinary,{method="sacred"},1,initial)
		assert.equal(applied.itemText,result.sampleItem);assert.equal(20,result.sampleState.quality)
		assert.equal(sim.matches(applied.state,{},nil,model,requirements),result.sampleSuccess)
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
