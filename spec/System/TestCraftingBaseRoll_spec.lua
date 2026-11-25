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
		local mana={"+(74-78) to maximum Mana","Non-Channelling Skills have -(8-6) to Total Mana Cost"}
		assert.is_nil(sim.baseRollReason(mana,2));assert.equal(-8,sim.baseRollValue(mana,{0,0},2));assert.equal(-6,sim.baseRollValue(mana,{1,1},2))
		for _,sample in ipairs({{0,-8},{0.32,-8},{0.34,-7},{0.66,-7},{0.68,-6},{0.999,-6}}) do local range=sim.rollRange(mana,function() return sample[1] end);assert.equal(sample[2],sim.baseRollValue(mana,range,2)) end
		assert.is_truthy(sim.baseRollReason({"-(10-5)% increased Damage"},1))
		local state=copyTable(model.initial);state.rarity="RARE";state.affixes={{id="LocalAddedColdDamage2",range={0,1}}}
		local groups={{anyOf={"LocalAddedColdDamage2"},baseValueComponent=1,minBaseValue=7},{anyOf={"LocalAddedColdDamage2"},baseValueComponent=2,minBaseValue=16}}
		assert.is_true(sim.matches(state,groups,nil,model));groups[2].minBaseValue=17;assert.is_false(sim.matches(state,groups,nil,model))
		local result=sim.calculate(weaponRaw,{method="alchemy"},{{anyOf={"LocalAddedColdDamage2"},baseValueComponent=2,minBaseValue=15}},nil,{trials=20,seed=5})
		assert.is_true(result.sampled);assert.equal(20,result.trials)
		assert.has_error(function() sim.validateRecipe({steps={{method="alchemy"}},targets={{anyOf={"LocalAddedColdDamage2"},baseValueComponent=2}}}) end)
	end)
	it("uses verified fractional precision for ordinary modifier rolls",function()
		local ring=sim.model('Rarity: NORMAL\nIron Ring\nItem Level: 86');local leech=ring.byId.LifeLeechPermyriadSuffix1
		assert.equal(0,sim.rollRange(leech,function() return 0.02 end))
		local range=sim.rollRange(leech,function() return 0.34 end)
		assert.is_true(math.abs(sim.baseRollValue(leech,range)-0.27)<1e-7)
		assert.equal(1,sim.rollRange(leech,function() return 0.999 end))
	end)
	it("samples pinned per-minute life regeneration rolls",function()
		local model=sim.model(raw);local regen=model.byId.LifeRegeneration2
		assert.equal(0,sim.rollRange(regen,function() return 0.001 end))
		local range=sim.rollRange(regen,function() return 0.5 end)
		assert.equal(0.5,range);assert.equal(5.1,sim.baseRollValue(regen,range))
		assert.equal(1,sim.rollRange(regen,function() return 0.9999 end))
		local state=copyTable(model.initial);state.rarity="RARE";state.affixes={{id="LifeRegeneration2",range=0.5}}
		local result=sim.perform(raw,{method="divine"},7,state);local tick=result.state.affixes[1].range*354
		assert.is_true(math.abs(tick-math.floor(tick+0.5))<1e-8)
		assert.is_truthy(result.itemText:find("Regenerate 4 Life per second",1,true))
		assert.is_true(sim.matches(result.state,{{anyOf={"LifeRegeneration2"},minBaseValue=4,maxBaseValue=4}},nil,model))

	end)
	it("samples pinned per-minute mana regeneration rolls",function()
		local rawJewel="Rarity: NORMAL\nSearching Eye Jewel\nItem Level: 86";local jewel=sim.model(rawJewel);local mod=jewel.byId.AbyssFlatManaShieldRegenerationJewel1
		assert.is_truthy(mod);assert.is_true(math.abs(sim.rollRange(mod,function() return 0.02 end)-1/54)<1e-10)
		local state=copyTable(jewel.initial);state.rarity="RARE";state.affixes={{id="AbyssFlatManaShieldRegenerationJewel1",range=0.5}}
		local result=sim.perform(rawJewel,{method="divine"},7,state);local tick=result.state.affixes[1].range*54
		assert.is_true(math.abs(tick-math.floor(tick+0.5))<1e-8)
	end)
	it("samples rounded Essence regeneration endpoints from their raw bounds",function()
		local model=sim.model(raw)
		for _,case in ipairs({{"LifeRegenerationEssence2",121,300,2,5},{"LifeRegenerationEssence7",1801,2400,30,40}}) do
			local mod=assert(model.byId[case[1]])
			for _,draw in ipairs({0,0.25,0.5,0.999999}) do
				local range=sim.rollRange(mod,function() return draw end)
				local actual=(case[4]+range*(case[5]-case[4]))*60
				local expected=case[2]+math.floor(draw*(case[3]-case[2]+1))
				assert.is_true(math.abs(actual-expected)<1e-7)
			end
		end
	end)
	it("samples pinned per-minute percentage regeneration rolls",function()
		for _,case in ipairs({{"Rarity: NORMAL\nHubris Circlet\nItem Level: 86\nCrusader Item","EnergyShieldRegenInfluence1"},{"Rarity: NORMAL\nPlate Vest\nItem Level: 86\nElder Item","LifeRegenerationRatePercentUber1"}}) do
			local model=sim.model(case[1]);local mod=assert(model.byId[case[2]]);assert.is_true(math.abs(sim.rollRange(mod,function() return 0.04 end)-1/30)<1e-9)
		end
	end)
	it("preserves base-roll goals in saved crafting recipes",function()
		newBuild();local recipe={steps={{method="alchemy"}},targets={{anyOf={"IncreasedLife4"},minBaseValue=65,maxBaseValue=67}}}
		local store=build.savers.CraftingProjects;store:Upsert({id="roll-goal",title="Roll goal",slot="Helmet",startingItem=raw,goals={},steps={},nativeRecipe=recipe})
		local xml={};store:Save(xml);local restored=require("Modules.CraftingProjects").new(build);restored:Load(xml)
		assert.same(recipe,restored.projects[1].nativeRecipe)
	end)
end)
