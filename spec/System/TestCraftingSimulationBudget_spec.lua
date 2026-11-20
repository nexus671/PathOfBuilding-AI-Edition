describe("Crafting action simulation budget", function()
	local simulator = require("Modules.CraftingSimulator")
	local tasks = require("Modules.CraftingTasks")
	local raw = "Rarity: NORMAL\nPlate Vest\nItem Level: 86"
	before_each(function() newBuild() end)
	after_each(function() tasks.cancel(); main.popups = {} end)
	it("explains why empty crafting actions are unavailable", function()
		local project = { id = "empty-ui", title = "Empty", slot = "Body Armour", startingItem = raw, goals = {}, steps = {} }
		local controls = require("Classes.CraftingSimulatorControl").Open(build, project)
		assert.is_false(controls.keepRecipe:IsEnabled())
		assert.is_truthy(controls.keepRecipe.tooltipText():find("Apply an action first", 1, true))
		assert.is_false(controls.history:IsEnabled())
		assert.is_truthy(controls.history.tooltipText():find("Apply an action first", 1, true))
		assert.is_false(controls.distribution:IsEnabled())
		assert.is_truthy(controls.distribution.tooltipText():find("Run a simulation first", 1, true))
	end)
	it("uses the full selected budget when repeating an action", function()
		local rare = simulator.perform(raw, { method = "alchemy" }, 1).state
		local project = { id = "budget-ui", title = "Budget", slot = "Body Armour", startingItem = raw, goals = {}, steps = {}, preferredMethod = "chaos", nativeRecipe = { initialState = rare, steps = {}, targets = {}, requirements = { minQuality = 20 } } }
		local controls = require("Classes.CraftingSimulatorControl").Open(build, project)
		controls.page:SelByValue("Simulate recipe"); controls.page.selFunc()
		controls.trials:SetText("1"); controls.budget:SetText("250")
		controls.simulate:Click()
		for i = 1, 10000 do if not tasks.job then break end; tasks.tick(build) end
		assert.is_nil(tasks.job)
		local result = build.craftingAnalyses[project.id].results.simulation
		assert.is_truthy(result)
		assert.are.equal(250, result.context.recipe.steps[1].maxAttempts)
		assert.are.equal(250, result.context.options.maxActions)
		assert.are.equal(250, result.result.meanExecutedActions)
	end)
end)
