describe("Compact Calcs navigation", function()
	it("makes defence sections reachable with the horizontal scrollbar", function()
		for _, width in ipairs({ 640, 960, 1280 }) do
			newBuild(); main.popups = { }
			local ui = require("Modules.HeadlessUI").install({ width = width, height = width == 640 and 480 or 720 })
			ui:bind(build); ui:frame(); ui:click("modeCalcs"); ui:frame()
			local calcs = build.calcsTab
			local bar = calcs.controls.scrollBarH
			if width < 1264 then
				assert.is_true(bar.enabled)
				local x, y = bar:GetPos(); local w, h = bar:GetSize()
				ui:clickAt(x + w - 7, y + h / 2); ui:frame()
				assert.is_true(bar.offset > 0)
				bar:SetOffset(bar.offsetMax); ui:frame()
				local defence
				for _, section in ipairs(calcs.sectionList) do
					if section.enabled and not section.isOverlay and section.group == 2 and section.x >= 312 and section.x + section.width <= width then defence = section; break end
				end
				assert.is_truthy(defence)
				local toggle = defence.controls.toggle1
				local tx, ty = toggle:GetPos(); local tw, th = toggle:GetSize()
				local before = defence.subSection[1].collapsed
				ui:clickAt(tx + tw / 2, ty + th / 2); ui:frame()
				assert.is_true(defence.subSection[1].collapsed ~= before)
				ui:resize(1280, 720); ui:frame()
				assert.is_false(bar.enabled)
				assert.equal(0, bar.offset)
			else
				assert.is_false(bar.enabled)
			end
			main.popups = { }; ui:restore()
		end
	end)

	it("brings the recovery heading into view after horizontal panning", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 480 })
		ui:bind(build); ui:frame(); ui:click("modeCalcs"); ui:frame()
		local calcs = build.calcsTab
		calcs.controls.scrollBarH:SetOffset(calcs.controls.scrollBarH.offsetMax)
		calcs:ShowRecoverySimulation(); ui:frame()
		local found
		for _, section in ipairs(calcs.sectionList) do for index, subSection in ipairs(section.subSection) do
			if subSection.label == "Recovery over Time" then
				local _, y = section.controls["toggle" .. index]:GetPos()
				assert.is_true(section.x >= 312 and section.x < 640)
				assert.is_true(y >= 56 and y < 480)
				found = true
			end
		end end
		assert.is_true(found)
		main.popups = { }; ui:restore()
	end)

	it("allows horizontal navigation in a narrow portrait window", function()
		newBuild(); main.popups = { }
		local originalPortrait = main.portraitMode
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 800 })
		main.portraitMode = true
		ui:bind(build); ui:frame(); ui:click("modeCalcs"); ui:frame()
		local calcs = build.calcsTab
		local horizontal = calcs.controls.scrollBarH
		assert.is_true(horizontal.enabled)
		local defence
		for _, section in ipairs(calcs.sectionList) do
			if section.enabled and not section.isOverlay and section.group == 2 then defence = section; break end
		end
		assert.is_truthy(defence)
		horizontal:SetOffset(defence.x - 312)
		calcs.controls.scrollBar:SetOffset(defence.y - 90)
		ui:frame()
		assert.is_true(defence.x >= 312 and defence.x + defence.width <= 640)
		assert.is_true(defence.y >= 56 and defence.y < 800)
		main.portraitMode = originalPortrait
		main.popups = { }; ui:restore()
	end)
end)
