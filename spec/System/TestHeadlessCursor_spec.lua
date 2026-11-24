describe("Headless text cursor", function()
	it("uses one-based cursor positions and types into an empty Calcs search", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 480 })
		ui:bind(build); ui:frame(); ui:click("modeCalcs"); ui:frame()
		assert.equal(1, DrawStringCursorIndex(16, "VAR", "", 0, 0))
		assert.equal(1, DrawStringCursorIndex(16, "VAR", "abc", -1, 0))
		assert.equal(4, DrawStringCursorIndex(16, "VAR", "abc", 1000, 0))
		local search = build.calcsTab.controls.search
		local x, y = search:GetPos()
		ui:clickAt(x + 35, y + 10)
		for char in ("life"):gmatch(".") do ui:dispatch(ui:activeHost(), { { type = "Char", key = char } }) end
		assert.equal("life", search.buf)
		ui:clickAt(x + 2, y + 10)
		ui:dispatch(ui:activeHost(), { { type = "Char", key = "X" } })
		assert.equal("Xlife", search.buf)
		main.popups = { }; ui:restore()
	end)
end)
