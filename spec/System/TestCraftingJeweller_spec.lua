describe("Experimental Jeweller socket model",function()
	local sim=require("Modules.CraftingSimulator")
	local sockets=require("Modules.CraftingSockets")
	local raw="Rarity: NORMAL\nPlate Vest\nItem Level: 86\nSockets: R-G W-W"
	it("excludes the current count and applies the disclosed maximum-count quality model",function()
		local model=sim.model(raw);local state=copyTable(model.initial)
		local base=sockets.jewellerProbabilities(model,state);local total=0
		for _,chance in ipairs(base) do total=total+chance end
		assert.are.near(1,total,1e-12);assert.equal(0,base[4]);assert.are.near(1/276,base[6],1e-12)
		state.quality=20;local quality=sockets.jewellerProbabilities(model,state);total=0
		for _,chance in ipairs(quality) do total=total+chance end
		assert.are.near(1,total,1e-12);assert.are.near(base[6]*1.2,quality[6],1e-12)
	end)
	it("preserves surviving sockets and adds unlinked white sockets under the stated assumption",function()
		local model=sim.model(raw);local before=copyTable(model.initial)
		local low=sim.action(model,before,{method="jeweller"},function() return 0 end)
		assert.equal(1,#low.sockets);assert.equal("R",low.sockets[1].color)
		local high=sim.action(model,before,{method="jeweller"},function() return 0.999999 end)
		assert.equal(6,#high.sockets);assert.equal("G",high.sockets[2].color);assert.equal(high.sockets[1].group,high.sockets[2].group)
		assert.equal("W",high.sockets[5].color);assert.not_equal(high.sockets[5].group,high.sockets[6].group)
		assert.same(before,model.initial);assert.is_false(require("Modules.CraftingAvailability").check("jeweller",high,model))
		assert.is_false(pcall(sim.action,model,high,{method="jeweller"},function() return 0 end))
	end)
	it("reports its assumptions and charges one Jeweller's Orb in a recipe",function()
		local result=sim.perform(raw,{method="jeweller"},123)
		assert.equal("jeweller_estimate",result.warnings[1].code)
		assert.matches("unverified",result.warnings[1].message)
		local recipe={steps={{method="jeweller"}},targets={},requirements={sockets=2}}
		local sampled=sim.simulate(raw,recipe,{trials=4,maxActions=1,forceFirstAction=true,currency="chaos",prices={jeweller=2}})
		assert.equal("jeweller_estimate",sampled.warnings[1].code);assert.equal(2,sampled.meanCost)
		assert.equal(4,sampled.currencySpent.jeweller)
	end)
	it("rejects unavailable modifier targets in exact socket calculations",function()
		local action={method="jeweller"}
		local ok,err=pcall(sim.calculate,raw,action,{{anyOf={"NotARealModifier"}}},nil,{})
		assert.is_false(ok);assert.matches("Target modifier ID is unavailable",err)
		local model=sim.model(raw);local id=assert(model.mods[1]).id
		local result=sim.calculate(raw,action,{{anyOf={id}}},nil,{})
		assert.is_false(result.sampled);assert.equal(0,result.successChance)
	end)
	it("enumerates the modeled socket counts and retains the uncertainty warning",function()
		local result=sim.calculate(raw,{method="jeweller"},{},nil,{requirements={sockets=6}})
		assert.is_false(result.sampled);assert.is_true(result.showAllOutcomes);assert.equal(5,#result.outcomes);assert.equal("jeweller_estimate",result.warnings[1].code)
		local total,matching=0,0
		for _,entry in ipairs(result.outcomes) do
			total=total+entry.chance;assert.equal(tonumber(entry.id),#entry.state.sockets)
			if entry.matches then matching=matching+entry.chance;assert.equal(6,#entry.state.sockets) end
		end
		assert.are.near(100,total,1e-8);assert.are.near(matching,result.successChance,1e-8);assert.are.near(100/276,matching,1e-8)
		local full=raw:gsub("R%-G W%-W","R-G W-W W W")
		assert.is_false(pcall(sim.calculate,full,{method="jeweller"},{},nil,{requirements={sockets=6}}))
	end)
end)
