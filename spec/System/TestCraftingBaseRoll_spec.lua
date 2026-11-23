describe("Crafting modifier base-roll targets",function()
	local sim=require("Modules.CraftingSimulator")
	local raw='Rarity: NORMAL\nIron Hat\nItem Level: 86'
	it("checks rendered base values independently of their normalized ranges",function()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="RARE";state.affixes={{id="IncreasedLife4",range=0.8}}
		local group={anyOf={"IncreasedLife4"},minBaseValue=65,maxBaseValue=67}
		assert.equal(66,sim.singleBaseRoll(model.byId.IncreasedLife4,0.8));assert.is_true(sim.matches(state,{group},nil,model))
		state.affixes[1].range=0.5;assert.is_false(sim.matches(state,{group},nil,model))
		state.affixes[1].range=1;assert.is_false(sim.matches(state,{group},nil,model))
		assert.equal(0,sim.singleBaseRoll({"+(0-5) to Level 20 Example"},0))
		assert.equal(-2,sim.singleBaseRoll({"+(-3--1) to maximum Life"},0.5))
	end)
	it("samples roll thresholds and rejects ambiguous ranges",function()
		local target={anyOf={"IncreasedLife4"},minBaseValue=65,maxBaseValue=67}
		local result=sim.calculate(raw,{method="alchemy"},{target},nil,{trials=20,seed=5})
		assert.is_true(result.sampled);assert.equal(20,result.trials)
		assert.is_nil(sim.singleBaseRoll({"Adds (1-2) to (3-4) Fire Damage"},0.5))
		assert.has_error(function() sim.validateRecipe({steps={{method="alchemy"}},targets={{anyOf={"IncreasedLife4"},scope="implicit",minBaseValue=1}}}) end)
		assert.has_error(function() sim.validateRecipe({steps={{method="alchemy"}},targets={{anyOf={"IncreasedLife4"},minBaseValue=70,maxBaseValue=60}}}) end)
	end)
	it("targets separate values from a multi-range modifier",function()
		local weaponRaw='Rarity: NORMAL\nRusted Sword\nItem Level: 86';local model=sim.model(weaponRaw);local mod=model.byId.LocalAddedColdDamage2
		assert.is_nil(sim.baseRollReason(mod,2));assert.is_truthy(sim.baseRollReason(mod,nil));assert.is_truthy(sim.baseRollReason(mod,3))
		assert.equal(7,sim.baseRollValue(mod,{0,1},1));assert.equal(16,sim.baseRollValue(mod,{0,1},2))
		assert.equal(4,sim.baseRollValue({'+(10-20) to maximum Life','+(1-5) to Strength'},{0.2,0.8},2))
		local state=copyTable(model.initial);state.rarity="RARE";state.affixes={{id="LocalAddedColdDamage2",range={0,1}}}
		local groups={{anyOf={"LocalAddedColdDamage2"},baseValueComponent=1,minBaseValue=7},{anyOf={"LocalAddedColdDamage2"},baseValueComponent=2,minBaseValue=16}}
		assert.is_true(sim.matches(state,groups,nil,model));groups[2].minBaseValue=17;assert.is_false(sim.matches(state,groups,nil,model))
		local result=sim.calculate(weaponRaw,{method="alchemy"},{{anyOf={"LocalAddedColdDamage2"},baseValueComponent=2,minBaseValue=15}},nil,{trials=20,seed=5})
		assert.is_true(result.sampled);assert.equal(20,result.trials)
		assert.has_error(function() sim.validateRecipe({steps={{method="alchemy"}},targets={{anyOf={"LocalAddedColdDamage2"},baseValueComponent=2}}}) end)
	end)
	it("preserves base-roll goals in saved crafting recipes",function()
		newBuild();local recipe={steps={{method="alchemy"}},targets={{anyOf={"IncreasedLife4"},minBaseValue=65,maxBaseValue=67}}}
		local store=build.savers.CraftingProjects;store:Upsert({id="roll-goal",title="Roll goal",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
		local xml={};store:Save(xml);local restored=require("Modules.CraftingProjects").new(build);restored:Load(xml)
		assert.same(recipe,restored.projects[1].nativeRecipe)
	end)
end)
