describe("Harvest elemental damage conversion",function()
	local sim=require("Modules.CraftingSimulator")
	local check=require("Modules.CraftingAvailability").check
	local raw="Rarity: NORMAL\nRusted Sword\nItem Level: 86"
	local function fixture()
		local model=sim.model(raw);local state=copyTable(model.initial);state.rarity="MAGIC"
		state.affixes={{id="LocalAddedFireDamage1",range=0.5}}
		return model,sim.validateState(model,state)
	end
	it("offers and applies a weapon damage swap with current ingredients",function()
		local model,state=fixture();local action={method="harvest_damage",from="fire",to="cold"}
		assert.is_true(check(action.method,state,model))
		assert.same({wild_lifeforce=300,primal_lifeforce=300,crystallised_rancour=1},sim.components(action))
		local result=sim.perform(raw,action,42,state)
		assert.equal("LocalAddedColdDamage1",result.state.affixes[1].id)
		assert.equal("LocalAddedFireDamage1",state.affixes[1].id)
		local choices=sim.actionOptions(model,state,action.method);assert.equal(2,#choices)
		local priced=sim.simulate(raw,{initialState=state,steps={action},targets={{anyOf={"LocalAddedColdDamage1"}}}},
			{trials=2,maxActions=1,currency="chaos",prices={wild_lifeforce=0.01,primal_lifeforce=0.02,crystallised_rancour=4}})
		assert.equal(13,priced.meanCost)
	end)
	it("refuses protected or conflicting damage modifiers",function()
		local model,state=fixture();local action={method="harvest_damage",from="fire",to="cold"}
		state.affixes[1].fractured=true;assert.is_false(check(action.method,state,model))
		state.affixes[1].fractured=nil;state.rarity="RARE"
		state.affixes[2]={id="LocalAddedColdDamage1",range=0.5}
		assert.matches("already present",sim.damageReason(model,state,"fire","cold"))
		assert.is_false(pcall(sim.action,model,state,action,function() return 0.5 end))
	end)
	it("converts each direction between ordinary weapon damage families",function()
		local model,state=fixture();local elements={fire="Fire",cold="Cold",lightning="Lightning"}
		for from,title in pairs(elements) do for to,target in pairs(elements) do if from~=to then
			state.affixes={{id="LocalAdded"..title.."Damage1",range=0.5}}
			local action={method="harvest_damage",from=from,to=to}
			local converted=sim.action(model,state,action,function() return 0.5 end)
			assert.equal("LocalAdded"..target.."Damage1",converted.affixes[1].id)
			assert.equal(1,sim.components(action).crystallised_rancour)
			assert.equal("harvest_damage_assumptions",sim.actionWarnings(action,model)[1].code)
		end end end
	end)
	it("preserves a conversion in a saved crafting guide",function()
		newBuild()
		local action={method="harvest_damage",from="fire",to="cold"}
		local project={id="damage-conversion",title="Damage conversion",slot="Weapon 1",startingItem=raw,goals={},steps={},preferredMethod="harvest_damage",nativeRecipe={steps={action},targets={},requirements={minAffixes=1}}}
		build.savers.CraftingProjects:Upsert(project)
		local xml=build:SaveDB("Damage conversion");loadBuildFromXML(xml,"Damage conversion")
		assert.same(action,build.savers.CraftingProjects.projects[1].nativeRecipe.steps[1])
	end)
	it("rejects ambiguous counterparts without affecting another item",function()
		local model,state=fixture()
		model.byId.LocalAddedColdDamage1_=copyTable(model.byId.LocalAddedColdDamage1)
		model.byId.LocalAddedLightningDamage1_=copyTable(model.byId.LocalAddedLightningDamage1)
		assert.matches("no supported matching conversion",sim.damageReason(model,state,"fire","cold"))
		local choices,reason=sim.damageOptions(model,state);assert.equal(0,#choices);assert.matches("no supported matching conversion",reason)
		local other,otherState=fixture()
		assert.is_nil(sim.damageReason(other,otherState,"fire","cold"))
	end)
	it("enumerates eligible choices for identity goals and samples roll goals",function()
		local ring="Rarity: NORMAL\nGold Ring\nItem Level: 86";local model=sim.model(ring)
		local state=copyTable(model.initial);state.rarity="RARE"
		state.affixes={{id="AddedFireDamage1",range=0.5},{id="FireDamagePercent1",range=0.5}}
		state=sim.validateState(model,state)
		local action={method="harvest_damage",from="fire",to="cold"}
		local result=sim.calculate(ring,action,{{anyOf={"AddedColdDamage1"}}},state,{})
		assert.is_false(result.sampled);assert.is_true(result.showAllOutcomes);assert.equal(50,result.successChance)
		assert.equal(2,#result.outcomes);assert.matches("assumed",result.exactFor)
		local bySource={};for _,entry in ipairs(result.outcomes) do bySource[entry.sourceId]=entry end
		assert.equal("AddedColdDamage1",bySource.AddedFireDamage1.targetId);assert.equal(50,bySource.AddedFireDamage1.chance)
		assert.is_true(bySource.AddedFireDamage1.matches);assert.is_false(bySource.FireDamagePercent1.matches)
		assert.equal("harvest_damage_assumptions",result.warnings[1].code)
		local either={{anyOf={"AddedColdDamage1"}},{anyOf={"ColdDamagePercent1"}}}
		assert.equal(100,sim.calculate(ring,action,either,state,{requiredGroups=1}).successChance)
		assert.equal(0,sim.calculate(ring,action,either,state,{requiredGroups=2}).successChance)
		local sampled=sim.calculate(ring,action,{{anyOf={"AddedColdDamage1"},minRoll=0.9}},state,{trials=10,seed=3})
		assert.is_true(sampled.sampled);assert.equal(10,sampled.trials)
		local ok,err=pcall(sim.calculate,ring,action,{{anyOf={"NotARealModifier"}}},state,{})
		assert.is_false(ok);assert.matches("Target modifier ID is unavailable",err)
	end)
end)
