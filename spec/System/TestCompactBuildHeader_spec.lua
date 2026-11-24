describe("Compact build header", function()
	it("keeps controls reachable across the layout breakpoint and in the planner", function()
		for _, width in ipairs({ 640, 800, 960, 1169, 1170, 1280 }) do
			newBuild(); main.popups = { }
			local ui = require("Modules.HeadlessUI").install({ width = width, height = width == 640 and 480 or 720 })
			ui:bind(build); ui:frame()
			local boxes = { }
			for _, key in ipairs({ "back", "save", "saveAs", "pointDisplay", "levelScalingButton", "characterLevel", "classDrop", "ascendDrop", "secondaryAscendDrop", "buildLoadouts" }) do
				local control = build.controls[key]
				local x, y = control:GetPos(); local w, h = control:GetSize()
				assert.is_true(x >= 0 and x + w <= width, key .. " is outside the window at " .. width)
				boxes[#boxes + 1] = { key = key, x = x, y = y, w = w, h = h }
			end
			for index, a in ipairs(boxes) do for j = index + 1, #boxes do
				local b = boxes[j]
				assert.is_false(a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h, a.key .. " overlaps " .. b.key .. " at " .. width)
			end end
			for _, key in ipairs({ "classDrop", "ascendDrop", "secondaryAscendDrop", "buildLoadouts" }) do
				local control = build.controls[key]
				local x = control:GetPos()
				assert.is_true(x + control.droppedWidth <= width, key .. " menu is outside the window at " .. width)
			end
			local old = build.characterLevelAutoMode
			ui:click("levelScalingButton")
			assert.is_true(build.characterLevelAutoMode ~= old)
			ui:click("classDrop"); ui:key("ESCAPE")
			ui:click("aiBuild"); ui:frame()
			assert.equal("PLANNER", build.viewMode)
			assert.is_false(build.controls.levelScalingButton:IsShown())
			assert.equal(32, build.planningWorkspace.viewport.y)
			main.popups = { }; ui:restore()
		end
	end)

	it("reflows the same build when the window is resized", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 1280, height = 720 })
		ui:bind(build); ui:frame()
		local _, wideY = build.controls.pointDisplay:GetPos()
		assert.equal(4, wideY)
		ui:resize(640, 480); ui:frame()
		local _, compactY = build.controls.pointDisplay:GetPos()
		assert.equal(32, compactY)
		local loadouts = build.controls.buildLoadouts
		assert.is_true(loadouts:GetPos() + loadouts.droppedWidth <= 640)
		local old = build.characterLevelAutoMode
		ui:click("levelScalingButton")
		assert.is_true(build.characterLevelAutoMode ~= old)
		ui:resize(1280, 720); ui:frame()
		local _, restoredY = build.controls.pointDisplay:GetPos()
		assert.equal(4, restoredY)
		main.popups = { }; ui:restore()
	end)
end)
