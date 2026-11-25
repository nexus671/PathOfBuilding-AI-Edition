describe("Changing a crafting project's starting item",function()
	local sim=require("Modules.CraftingSimulator")
	local raw="Rarity: NORMAL\nIron Hat\nItem Level: 86"
	before_each(function() newBuild();main.popups={} end)
	after_each(function() main.popups={} end)
	it("confirms resetting dependent starts while preserving recipes and snapshots",function()
		local ui=require("Modules.HeadlessUI").install({width=960,height=640});ui:bind(build)
		local ok,err=pcall(function()
			local state=sim.model(raw).initial
			local recipe={steps={{method="alchemy"}},targets={},requirements={minQuality=1},initialState=state}
			local inventory={{id="snapshot",title="Snapshot",slot="Helmet",baseItem=raw,at=0,state=state}}
			local project={id="stateful",title="Stateful",slot="Helmet",startingItem=raw,goals={"Life"},steps={},nativeRecipe=recipe,recipeAlternatives={{name="Alternative",recipe=copyTable(recipe)}},run=require("Modules.CraftingInventory").run(state),inventory=inventory}
			build.savers.CraftingProjects:Upsert(project)
			require("Classes.CraftingProjectControl").Edit(build,build.savers.CraftingProjects.projects[1],nil,nil,nil)
			local wizard=main.popups[1].controls;local changed=raw.."\nQuality: 10"
			wizard.starting:SetText(changed);wizard.starting.changeFunc();wizard.wizardPage:SetSel(4);wizard.save:Click()
			assert.equal("Change starting item",main.popups[1].title);assert.equal(raw,build.savers.CraftingProjects.projects[1].startingItem)
			main:ClosePopup();assert.equal(changed,wizard.starting.buf);assert.is_truthy(build.savers.CraftingProjects.projects[1].run)
			wizard.save:Click();main.popups[1].controls.confirm:Click();local saved=build.savers.CraftingProjects.projects[1]
			assert.equal(changed,saved.startingItem);assert.is_nil(saved.run);assert.is_nil(saved.nativeRecipe.initialState);assert.is_nil(saved.recipeAlternatives[1].recipe.initialState)
			assert.equal("alchemy",saved.nativeRecipe.steps[1].method);assert.equal("alchemy",saved.recipeAlternatives[1].recipe.steps[1].method)
			assert.same({"Life"},saved.goals);assert.equal("snapshot",saved.inventory[1].id);assert.is_truthy(require("Classes.CraftingSimulatorControl").Open(build,saved))
		end)
		ui:restore();main.popups={};assert.is_true(ok,err)
	end)
	it("retains the working session when the starting item is unchanged",function()
		local state=sim.model(raw).initial
		local project={id="same",title="Same",slot="Helmet",startingItem=raw,goals={},steps={},run=require("Modules.CraftingInventory").run(state)}
		build.savers.CraftingProjects:Upsert(project);require("Classes.CraftingProjectControl").Edit(build,build.savers.CraftingProjects.projects[1],nil,nil,nil)
		local wizard=main.popups[1].controls;wizard.wizardPage:SetSel(4);wizard.save:Click()
		assert.is_truthy(build.savers.CraftingProjects.projects[1].run);assert.equal(raw,build.savers.CraftingProjects.projects[1].startingItem)
	end)
end)
