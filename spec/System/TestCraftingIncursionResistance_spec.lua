describe("Harvest Incursion resistance conversions",function()
	local sim=require("Modules.CraftingSimulator")
	local families={
		{"Iron Gauntlets",{fire="FireResistEnhancedLevel50ModAilments_",cold="ColdResistEnhancedModAilments__",lightning="LightningResistEnhancedLevel50ModAilments"}},
		{"Iron Hat",{fire="FireResistEnhancedLevel50ModPhys",cold="ColdResistEnhancedLevel50ModPhys_",lightning="LightningResistEnhancedLevel50ModPhys"}},
		{"Paua Amulet",{fire="FireResistEnhancedLevel50ModLeech",cold="ColdResistEnhancedModLeech",lightning="LightningResistEnhancedLevel50ModLeech"}},
		{"Paua Amulet",{fire="FireResistEnhancedLevel50ModLeechInverted",cold="ColdResistEnhancedLevel50ModLeechInverted",lightning="LightningResistEnhancedLevel50ModLeechInverted"}},
	}
	it("maps supported families on their native bases without adding normal rolls",function()
		for _,family in ipairs(families) do
			local raw="Rarity: NORMAL\n"..family[1].."\nItem Level: 86";local model=sim.model(raw)
			for from,id in pairs(family[2]) do for to,target in pairs(family[2]) do if from~=to then
				local state=copyTable(model.initial);state.rarity="MAGIC";state.affixes={{id=id,range=0.5}};state=sim.validateState(model,state)
				local result=sim.perform(raw,{method="harvest_resistance",from=from,to=to},17,state)
				assert.equal(target,result.state.affixes[1].id)
				for _,entry in ipairs(model.mods) do assert.not_equal(target,entry.id) end
				local odds=sim.calculate(raw,{method="harvest_resistance",from=from,to=to},{{anyOf={target}}},state,{})
				assert.equal(100,odds.successChance);assert.is_false(odds.sampled)
			end end end
		end
	end)
	it("rejects a replacement above the item level and protects fractures",function()
		local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 20";local model=sim.model(raw)
		local state=copyTable(model.initial);state.rarity="MAGIC";state.affixes={{id="ColdResistEnhancedModAilments__",range=0.5}};state=sim.validateState(model,state)
		assert.matches("unavailable",sim.resistanceReason(model,state,"cold","fire"))
		state.affixes[1].fractured=true;assert.is_truthy(sim.resistanceReason(model,state,"cold","fire"))
	end)
	it("simulates an eligible drop-only target and rejects it on another base",function()
		local raw="Rarity: NORMAL\nIron Gauntlets\nItem Level: 86";local model=sim.model(raw)
		local source="FireResistEnhancedLevel50ModAilments_";local target="ColdResistEnhancedModAilments__"
		local state=copyTable(model.initial);state.rarity="MAGIC";state.affixes={{id=source,range=0.5}};state=sim.validateState(model,state)
		local recipe={initialState=state,steps={{method="harvest_resistance",from="fire",to="cold"}},targets={{anyOf={target}}}}
		local result=sim.simulate(raw,recipe,{trials=3,maxActions=1})
		assert.equal(3,result.successes);assert.is_nil(next(result.transitionErrors))
		local ring="Rarity: NORMAL\nGold Ring\nItem Level: 86"
		local ok,err=pcall(sim.simulate,ring,{steps={{method="alchemy"}},targets={{anyOf={target}}}},{trials=1,maxActions=1})
		assert.is_false(ok);assert.matches("Target modifier ID is unavailable",err)
	end)
end)
