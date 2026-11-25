describe("Atlas planner control explanations", function()
	before_each(function() newBuild(); main.popups = {} end)
	after_each(function() main.popups = {} end)
	it("explains unavailable actions and the starting node", function()
		local atlas = require("Modules.AtlasPlanner")
		local version = "3.30.0c"
		local plan = { id = "atlas-help", title = "Mapping", version = version, budget = atlas.tree(version).maxPoints, nodes = {}, notes = "" }
		local controls = require("Classes.AtlasPlannerControl").Open(build, plan)
		controls.canvas.focus = nil
		assert.is_false(controls.allocate:IsEnabled()); assert.matches("Select a node", controls.allocate.tooltipText())
		assert.is_false(controls.remove:IsEnabled()); assert.matches("Select an allocated", controls.remove.tooltipText())
		assert.is_false(controls.avoid:IsEnabled()); assert.matches("Select an unallocated", controls.avoid.tooltipText())
		assert.is_false(controls.clearAvoid:IsEnabled()); assert.matches("No nodes", controls.clearAvoid.tooltipText())
		assert.is_false(controls.undo:IsEnabled()); assert.matches("no changes", controls.undo.tooltipText())
		assert.is_false(controls.redo:IsEnabled()); assert.matches("no changes", controls.redo.tooltipText())
		controls.canvas.focus = controls.canvas.tree.start
		assert.matches("already connected", controls.allocate.tooltipText())
		assert.matches("cannot be avoided", controls.avoid.tooltipText())
	end)
end)
