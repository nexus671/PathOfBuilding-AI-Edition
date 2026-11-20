describe("Bestiary flask suffixes",function()
	local sim=require("Modules.CraftingSimulator")
	local available=require("Modules.CraftingAvailability").check
	local function model(base,level) return sim.model("Rarity: NORMAL\n"..base.."\nItem Level: "..(level or 86)) end
	it("offers recovery and utility suffixes and retains them through item import",function()
		for _,case in ipairs({{"Small Life Flask",6},{"Small Mana Flask",6},{"Quicksilver Flask",5}}) do
			local m=model(case[1]);local options=sim.actionOptions(m,m.initial,"beast_flask")
			assert.equal(case[2],#options);assert.is_true(available("beast_flask",m.initial,m))
			for _,choice in ipairs(options) do
				local state=sim.action(m,m.initial,choice.action,function() return 0.5 end)
				assert.equal("MAGIC",state.rarity);assert.equal(choice.action.modId,state.affixes[1].id)
				assert.same(state,sim.validateState(m,state))
				local imported=sim.model(sim.toItem(m,state).raw);assert.equal(choice.action.modId,imported.initial.affixes[1].id)
			end
		end
	end)
	it("rejects incompatible flasks, suffixes and insufficient item level",function()
		local m=model("Small Life Flask");local action={method="beast_flask",modId="FlaskChillFreezeImmunity1"}
		local state=sim.action(m,m.initial,action,function() return 0.5 end)
		assert.is_false(available("beast_flask",state,m));assert.is_false(pcall(sim.action,m,state,action,function() return 0.5 end))
		assert.is_false(pcall(sim.action,m,m.initial,{method="beast_flask",modId="FlaskShockImmunityDuringEffect"},function() return 0.5 end))
		local low=model("Small Life Flask",1);assert.is_false(available("beast_flask",low.initial,low));assert.is_false(pcall(sim.action,low,low.initial,action,function() return 0.5 end))
		local hybrid=model("Small Hybrid Flask");assert.is_false(available("beast_flask",hybrid.initial,hybrid))
	end)
	it("keeps the selected suffix and unknown action cost in recipe simulations",function()
		local m=model("Small Life Flask");local action={method="beast_flask",modId="FlaskChillFreezeImmunity1"}
		local recipe={steps={action},targets={{anyOf={action.modId}}}}
		assert.is_truthy(sim.validateRecipe(recipe))
		local result=sim.simulate(m.raw,recipe,{trials=5,maxActions=1,seed=7})
		assert.equal("beast_flask_assumptions",result.warnings[1].code)
		assert.equal("beast_flask",sim.priceKey(action));assert.same({beast_any_red=1},sim.components(action,m.initial,m))
		local performed=sim.perform(m.raw,action,7);assert.equal(action.modId,performed.state.affixes[1].id)
		assert.equal("beast_flask_assumptions",performed.warnings[1].code)
		local catalog=sim.catalog(m.raw,"",10);assert.is_true(catalog.beastFlaskOptions.available);assert.equal(6,#catalog.beastFlaskOptions.choices)
		assert.equal("beast_flask",catalog.beastFlaskOptions.priceKey)
		assert.same({beast_any_red=1},catalog.beastFlaskOptions.components)
		local odds=sim.calculate(m.raw,action,recipe.targets,nil,{trials=20,seed=7})
		assert.equal(100,odds.successChance);assert.equal("beast_flask_assumptions",odds.warnings[1].code)
	end)
	it("adds a named suffix through the recipe browser",function()
		newBuild();main.popups={};local m=model("Small Life Flask");local kept
		local controls=require("Classes.CraftingRecipeControl").Open({steps={{method="transmute"}},targets={{anyOf={"FlaskChillFreezeImmunity1"}}}},{method="transmute"},function(value) kept=value end,m)
		controls.addCurrency:Click();local browser=main.popups[1].controls
		browser.search:SetText("convection",true);assert.equal("FlaskChillFreezeImmunity1",browser.results.list[1].entry.action.modId)
		browser.choose:Click();assert.is_true(controls.keep:IsShown());assert.is_true(controls.keep:IsEnabled());controls.keep:Click()
		assert.equal("beast_flask",kept.steps[2].method);assert.equal("FlaskChillFreezeImmunity1",kept.steps[2].modId);main.popups={}
	end)
	it("applies a chosen suffix in the workbench",function()
		newBuild();main.popups={}
		local project={id="beast-flask-test",title="Flask",slot="Flask 1",startingItem="Rarity: NORMAL\nSmall Life Flask\nItem Level: 86",goals={},steps={}}
		local controls=require("Classes.CraftingSimulatorControl").Open(build,project)
		controls.method:SelByValue("beast_flask","val");controls.method.selFunc()
		assert.equal(6,#controls.option.list);assert.is_true(controls.apply:IsEnabled())
		controls.apply:Click();assert.is_true(controls.undo:IsEnabled());assert.is_false(controls.apply:IsEnabled());main.popups={}
	end)
	it("preserves a flask guide through project save and reload",function()
		newBuild();local store=build.savers.CraftingProjects
		local action={method="beast_flask",modId="FlaskChillFreezeImmunity1"}
		local project={id="beast-flask-save",title="Flask suffix",slot="Flask 1",startingItem="Rarity: NORMAL\nSmall Life Flask\nItem Level: 86",goals={},steps={},nativeRecipe={steps={action},targets={{anyOf={action.modId}}}}}
		store:Upsert(project);local xml={};store:Save(xml)
		local reopened=require("Modules.CraftingProjects").new(build);reopened:Load(xml)
		assert.is_nil(reopened.warning);assert.equal(action.modId,reopened.projects[1].nativeRecipe.steps[1].modId)
		local outcome=sim.simulate(project.startingItem,reopened.projects[1].nativeRecipe,{trials=2,maxActions=1,seed=1});assert.equal(2,outcome.successes)
	end)
end)
