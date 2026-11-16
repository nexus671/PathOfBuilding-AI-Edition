describe("Partial locks with Harvest conversions",function()
	local sim=require("Modules.CraftingSimulator")
	it("reports selections that protect the only eligible resistance",function()
		local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86";local model=sim.model(raw)
		local fire,other
		for _,entry in ipairs(model.mods) do
			if entry.mod.group=="FireResistance" and not fire then fire=entry.id end
			if entry.mod.group=="ChaosResistance" and not other then other=entry.id end
		end
		assert.is_truthy(fire);assert.is_truthy(other)
		local state=sim.validateState(model,{rarity="RARE",affixes={{id=fire,range=0.5},{id=other,range=0.5}}})
		local locked=sim.perform(raw,{method="bench",modId="bench:partial-suffix-1"},1,state).state
		local action={method="harvest_resistance",from="fire",to="cold"}
		local fullyProtected=copyTable(locked);table.remove(fullyProtected.affixes,2)
		assert.is_false(require("Modules.CraftingAvailability").check(action.method,fullyProtected,model))
		assert.is_true(require("Modules.CraftingAvailability").check(action.method,locked,model))
		local note;for _,entry in ipairs(sim.catalog(raw,"",50,locked).harvestOptions) do if entry.method==action.method then note=entry.selectionNote end end
		assert.matches("Other selections can fail",assert(note))
		assert.has_error(function() sim.action(model,locked,action,function() return 0.25 end) end)
		local result=sim.action(model,locked,action,function() return 0.75 end)
		assert.equal(fire:gsub("Fire","Cold"),result.affixes[1].id);assert.equal(other,result.affixes[2].id)
		local cold=(fire:gsub("Fire","Cold"))
		local odds=sim.calculate(raw,action,{{anyOf={cold}}},locked,{trials=30,seed=17})
		assert.is_true(odds.sampled);assert.is_truthy(next(odds.transitionErrors));assert.is_true(odds.successes>0)
		local warning=false;for _,entry in ipairs(odds.warnings) do if entry.code=="partial_lock_model" then warning=true end end;assert.is_true(warning)
	end)
	it("protects selected damage prefixes and samples the resulting alternatives",function()
		local raw="Rarity: NORMAL\nGold Ring\nItem Level: 86";local model=sim.model(raw);local other
		for _,entry in ipairs(model.mods) do if entry.mod.type=="Prefix" and entry.mod.group~="FireDamage" then other=entry.id;break end end
		local state=sim.validateState(model,{rarity="RARE",affixes={{id="AddedFireDamage1",range=0.5},{id=assert(other),range=0.5},{id="FireDamagePercent1",range=0.5}}})
		local locked=sim.perform(raw,{method="bench",modId="bench:partial-prefix-1"},1,state).state
		local action={method="harvest_damage",from="fire",to="cold"}
		assert.is_true(require("Modules.CraftingAvailability").check(action.method,locked,model))
		local protected=sim.action(model,locked,action,function() return 0 end)
		assert.equal("AddedFireDamage1",protected.affixes[1].id);assert.equal("ColdDamagePercent1",protected.affixes[3].id)
		local odds=sim.calculate(raw,action,{{anyOf={"AddedColdDamage1"}}},locked,{trials=30,seed=17})
		assert.is_true(odds.sampled);assert.is_true(odds.successes>0);assert.is_true(odds.successes<30)
	end)
end)
