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
		assert.equal("X" .. "life", search.buf)
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
		assert.equal(50001, DrawStringCursorIndex(16, "VAR", string.rep("a", 50000), 1000000, 0))
		main.popups = { }; ui:restore()
	end)

	it("measures unsupported Unicode using native code-point placeholders", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 480 })
		-- Liberation Sans uses its 12-pixel font for placeholders at height 16.
		assert.equal(43, DrawStringWidth(16, "VAR", "é"))
		assert.equal(49, DrawStringWidth(16, "VAR", "🙂"))
		assert.equal(1, DrawStringCursorIndex(16, "VAR", "éa", 43, 0))
		assert.equal(3, DrawStringCursorIndex(16, "VAR", "éa", 44, 0))
		main.popups = { }; ui:restore()
	end)

	it("measures tab stops using the space glyph", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 480 })
		local space = DrawStringWidth(16, "FIXED", " ")
		local tab = DrawStringWidth(16, "FIXED", "\t")
		assert.equal(space * 4, tab)
		assert.equal(1, DrawStringCursorIndex(16, "FIXED", "\ta", tab, 0))
		assert.equal(2, DrawStringCursorIndex(16, "FIXED", "\ta", tab + 1, 0))
		main.popups = { }; ui:restore()
	end)

	it("rounds text height and cursor coordinates like the native binding at standard scale", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 480 })
		assert.equal(DrawStringWidth(16, "VAR", "Readable text"), DrawStringWidth(15, "VAR", "Readable text"))
		assert.equal(DrawStringWidth(18, "VAR", "é"), DrawStringWidth(17, "VAR", "é"))
		DrawString(0, 0, "LEFT", 15, "VAR", "Test")
		assert.equal(16, ui.commands[#ui.commands].height)
		main.popups = { }; ui:restore()
	end)

	it("measures long text and ignores complete colour escapes", function()
		newBuild(); main.popups = { }
		local ui = require("Modules.HeadlessUI").install({ width = 640, height = 480 })
		assert.equal(DrawStringWidth(16, "VAR", "abé"), DrawStringWidth(16, "VAR", "a^xFFFFFFb^1é"))
		assert.equal(50000 * DrawStringWidth(16, "VAR", "a"), DrawStringWidth(16, "VAR", string.rep("a", 50000)))
		DrawString(0, 0, "LEFT", 16, "VAR", string.rep("a", 50000) .. "^1")
		local r,g,b = GetDrawColor()
		assert.equal(1, r); assert.equal(0, g); assert.equal(0, b)
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
