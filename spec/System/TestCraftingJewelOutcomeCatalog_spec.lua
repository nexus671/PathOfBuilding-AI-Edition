describe("Corruption-exclusive jewel outcome catalogue",function()
	local catalog=require("Modules.CraftingJewelCorruption")
	it("finds matching current bundled jewel sources without including legacy or replica entries",function()
		for _,case in ipairs({{"Cobalt Jewel","Powerlessness"},{"Crimson Jewel","Fragility"},{"Viridian Jewel","Pacifism"}}) do
			local seen={};local previous=""
			for _,entry in ipairs(catalog.candidates(case[1])) do
				assert.equal(case[1],entry.baseName);assert.is_nil(seen[entry.title]);assert.is_true(entry.title>=previous)
				seen[entry.title]=true;previous=entry.title
				local item=catalog.item(case[1],entry.title,83,123)
				assert.equal(case[1],item.baseName);assert.equal(entry.title,item.title);assert.is_true(item.corrupted,entry.title);assert.equal(83,item.itemLevel)
				for _,line in ipairs(item.explicitModLines or {}) do assert.not_equal("Corrupted",line.line,entry.title) end
			end
			assert.is_true(seen[case[2]]);assert.is_nil(seen["Replica "..case[2]])
		end
		assert.same({},catalog.candidates("Searching Eye Jewel"))
	end)
	it("validates a transformed jewel as a distinct reproducible state",function()
		local model=require("Modules.CraftingSimulator").model("Rarity: NORMAL\nCobalt Jewel\nItem Level: 83")
		local state={origin=model.initial.origin,rarity="UNIQUE",corrupted=true,affixes={},uniqueTitle="Powerlessness",uniqueSeed=123}
		local restored=catalog.validateState(model,state)
		assert.same(state,restored)
		local simulator=require("Modules.CraftingSimulator");assert.same(state,simulator.validateState(model,state))
		assert.equal("Powerlessness",simulator.toItem(model,state).title);assert.matches("Corrupted",simulator.itemText(model,state))
		assert.equal(catalog.item("Cobalt Jewel",state.uniqueTitle,83,123).raw,catalog.item("Cobalt Jewel",state.uniqueTitle,83,123).raw)
		state.uniqueTitle="Replica Powerlessness";assert.has_error(function() catalog.validateState(model,state) end)
	end)
	it("preserves a selected unique outcome after a Vaal action",function()
		local simulator=require("Modules.CraftingSimulator")
		local model=simulator.model("Rarity: NORMAL\nCobalt Jewel\nItem Level: 83")
		local state=simulator.action(model,model.initial,{method="vaal"},function() return 0.8 end)
		assert.equal("UNIQUE",state.rarity);assert.is_true(state.corrupted);assert.is_truthy(state.uniqueTitle)
		local restored=simulator.validateState(model,state);local item=simulator.toItem(model,restored)
		assert.equal(state.uniqueTitle,item.title);assert.is_true(item.corrupted);assert.equal(83,item.itemLevel)
		local checkpoint=require("Modules.CraftingCheckpoint").validate(model.raw,{schemaVersion=1,state=state,initial=model.initial,history={},actions={},sequence=0})
		assert.same(state,checkpoint.state);assert.equal(item.raw,simulator.toItem(model,checkpoint.state).raw)
		local inventory=require("Modules.CraftingInventory");local saved=inventory.capture({title="Jewel",slot="Jewel 1",startingItem=model.raw},state)
		local reopened=inventory.project(saved);assert.same(state,reopened.run.state);assert.same({corrupted=true},reopened.run.requirements)
		assert.is_false(require("Modules.CraftingAvailability").check("vaal",state,model))
		assert.is_false(simulator.matches(state,{},"RARE",model,{corrupted=true}))
		assert.is_true(simulator.matches(state,{},nil,model,{corrupted=true}))
		assert.is_true(simulator.matches(state,{},"UNIQUE",model,{uniqueName=state.uniqueTitle}))
		assert.is_false(simulator.matches(state,{},"UNIQUE",model,{uniqueName="Other Jewel"}))
		assert.is_false(simulator.matches(model.initial,{},nil,model,{uniqueName=state.uniqueTitle}))
		assert.has_error(function() simulator.matches(state,{},nil,model,{minAffixes=1}) end)
	end)
	it("counts unique outcomes in a bounded corruption simulation",function()
		local simulator=require("Modules.CraftingSimulator")
		local raw="Rarity: NORMAL\nCobalt Jewel\nItem Level: 83"
		local recipe={steps={{method="vaal"}},targets={},requirements={corrupted=true}}
		local result=simulator.simulate(raw,recipe,{trials=32,maxActions=1,seed=123})
		assert.equal(32,result.successes);assert.is_true(result.uniqueTrials>0);assert.is_true(result.uniqueTrials<32)
		local unique=simulator.simulate(raw,{steps={{method="vaal"}},targets={},rarity="UNIQUE",requirements={corrupted=true}},{trials=32,maxActions=1,seed=123})
		assert.equal(unique.uniqueTrials,unique.successes)
		assert.has_error(function() simulator.simulate(raw,{steps={{method="vaal"}},targets={},requirements={minAffixes=2}},{trials=1,maxActions=1,seed=123}) end)
	end)
	it("keeps and reopens an exact unique-name target",function()
		main.popups={};local saved
		local editor=require("Classes.CraftingTargetControl").Open({},nil,nil,function(_,value) saved=value end)
		editor.uniqueName:SetText("Powerlessness",true);editor.keep:Click();assert.equal("Powerlessness",saved.uniqueName)
		editor=require("Classes.CraftingTargetControl").Open({},saved,nil,function() end)
		assert.equal("Powerlessness",editor.uniqueName.buf);editor.close:Click();main.popups={}
	end)
end)
