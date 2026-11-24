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
end)
