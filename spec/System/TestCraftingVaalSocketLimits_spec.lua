describe("Vaal equipment socket limitations",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W-W-W-W"
	it("warns before and after an equipment corruption, without affecting socketless items",function()
		local model=sim.model(raw)
		assert.matches("reroll sockets and links",require("Modules.CraftingWorkbench").hint("vaal",model.initial,model))
		local result=sim.perform(raw,{method="vaal"},3)
		assert.equal("vaal_socket_reroll_unmodeled",result.warnings[1].code)
		assert.matches("leaves them unchanged",result.warnings[1].message)
		local ring=sim.perform("Rarity: NORMAL\nIron Ring\nItem Level: 86",{method="vaal"},3)
		for _,warning in ipairs(ring.warnings) do assert.not_equal("vaal_socket_reroll_unmodeled",warning.code) end
	end)
	it("rejects socket goals rather than reporting misleading Vaal chances",function()
		for _,requirements in ipairs({{sockets=4},{links=4},{socketColours="WW"},{minAbyssSockets=1}}) do
			local recipe={steps={{method="vaal"}},targets={},requirements=requirements}
			assert.has_error(function() sim.simulate(raw,recipe,{trials=2,maxActions=1}) end,"Cannot calculate socket or link goals with Vaal corruption: rare-reroll socket changes are not modeled.")
			assert.has_error(function() sim.calculate(raw,{method="vaal"},{},nil,{requirements=requirements,trials=2}) end,"Cannot calculate socket or link goals with Vaal corruption: rare-reroll socket changes are not modeled.")
		end
	end)
	it("also guards repeated-step goals and modeled Gwennen corruption",function()
		local recipes={
			{steps={{method="vaal",untilRequirements={links=4}}},targets={},requirements={corrupted=true}},
			{steps={{method="gwennen",firstOutcome=1000,secondOutcome=1012}},targets={},requirements={links=4}},
		}
		for _,recipe in ipairs(recipes) do
			assert.has_error(function() sim.simulate(raw,recipe,{trials=2,maxActions=1}) end,"Cannot calculate socket or link goals with Vaal corruption: rare-reroll socket changes are not modeled.")
		end
		local ok=sim.simulate(raw,{steps={{method="vaal"}},targets={},requirements={corrupted=true}},{trials=2,maxActions=1})
		assert.equal(2,ok.successes);assert.equal("vaal_socket_reroll_unmodeled",ok.warnings[1].code)
	end)
end)
