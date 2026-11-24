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

	it("maps line, colour and Unicode positions to UTF-8 byte indices", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 480 })
		local width = DrawStringWidth(16, "VAR", "a")
		assert.equal(1, DrawStringCursorIndex(16, "VAR", "ab", width, 0))
		assert.equal(3, DrawStringCursorIndex(16, "VAR", "^1ab", 0, 0))
		assert.equal(3, DrawStringCursorIndex(16, "VAR", "a\nbc", 0, 17))
		assert.equal(2, DrawStringCursorIndex(16, "VAR", "aéz", width + 1, 0))
		assert.equal(5, DrawStringCursorIndex(16, "VAR", "aéz", 1000, 0))
		main.popups = { }; ui:restore()
	end)

	it("edits a later line before and after a Unicode character", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 960, height = 640 })
		local anchor = new("Control"):Control(nil, { 0, 0, 0, 0 })
		local controls = { }
		controls.edit = new("EditControl"):EditControl({ "TOPLEFT", anchor, "TOPLEFT" }, { 20, 40, 300, 100 }, "a\néz", nil, nil, 100, nil, 16)
		main:OpenPopup(340, 180, "Text test", controls); ui:frame()
		local edit = main.popups[1].controls.edit
		local x, y = edit:GetPos()
		ui:clickAt(x + 3, y + 20); ui:dispatch(ui:activeHost(), { { type = "Char", key = "X" } })
		assert.equal("a\nXéz", edit.buf)
		local after = DrawStringWidth(16, "VAR", "Xé")
		ui:clickAt(x + 2 + after + 1, y + 20); ui:dispatch(ui:activeHost(), { { type = "Char", key = "Y" } })
		assert.equal("a\nXéYz", edit.buf)
		main.popups = { }; ui:restore()
	end)
end)
