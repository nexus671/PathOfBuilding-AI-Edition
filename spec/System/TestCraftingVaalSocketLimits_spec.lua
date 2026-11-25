-- cspell:ignore unmodeled
describe("Vaal equipment socket limitations",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86\nSockets: W-W-W-W"
	it("warns before and after equipment corruption without affecting items without sockets",function()
		local model=sim.model(raw)
		assert.matches("reroll sockets and links",require("Modules.CraftingWorkbench").hint("vaal",model.initial,model))
		local result=sim.perform(raw,{method="vaal"},3)
		assert.equal("vaal_socket_reroll_unmodeled",result.warnings[1].code)
		assert.matches("layout is unknown",result.warnings[1].message)
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
	it("preserves unknown sockets until an observed layout is supplied",function()
		newBuild()
		local model=sim.model(raw);local original=copyTable(model.initial)
		local state=sim.action(model,original,{method="vaal"},function() return 0.6 end)
		assert.is_true(state.socketLayoutUnknown);assert.same(original,model.initial);assert.is_nil(sim.itemText(model,state))
		for _,draw in ipairs({0.3,0.9}) do local known=sim.action(model,original,{method="vaal"},function() return draw end);assert.is_nil(known.socketLayoutUnknown);assert.is_not_nil(sim.itemText(model,known)) end
		local reason=sim.methodReason(model,state,"tainted_chromatic");assert.matches("unknown socket layout",reason)
		assert.is_false(require("Modules.CraftingAvailability").check("tainted_chromatic",state,model))
		assert.has_error(function() sim.matches(state,{},nil,model,{links=4}) end)
		local checkpoint=require("Modules.CraftingCheckpoint").validate(raw,require("Modules.CraftingInventory").run(state))
		assert.is_true(checkpoint.state.socketLayoutUnknown)
		local continued=sim.perform(raw,{method="tainted_chaos"},1,state)
		assert.is_true(continued.state.socketLayoutUnknown);assert.is_nil(continued.itemText)
		local found=false;for _,warning in ipairs(continued.warnings) do if warning.code=="socket_layout_unknown" then found=true end end;assert.is_true(found)
		local recipe={steps={{method="tainted_exalt"}},targets={},requirements={minAffixes=0},initialState=state}
		local result=sim.simulate(raw,recipe,{trials=1,maxActions=1,retainSuccesses=1})
		assert.is_true(result.sampleState.socketLayoutUnknown);assert.is_nil(result.sampleItem);assert.is_nil(result.retainedSuccesses[1].itemText)
		local socketRecipe={steps={{method="tainted_exalt"}},targets={},requirements={links=4},initialState=state}
		assert.has_error(function() sim.simulate(raw,socketRecipe,{trials=1,maxActions=1}) end)
		local saved;local controls=require("Classes.CraftingSocketControl").Open(model,state,function(value) saved=value end)
		controls.use:Click();assert.is_nil(saved.socketLayoutUnknown);assert.is_not_nil(sim.itemText(model,saved));assert.is_nil(sim.methodReason(model,saved,"tainted_chromatic"))
		main.popups={}
	end)
end)
