describe("Headless UI clock", function()
	it("accepts a running clock and restores the previous clock", function()
		newBuild()
		local previous = GetTime
		local now = 123
		local ui = require("Modules.HeadlessUI").install({ clock = function() return now end })
		local ok, err = pcall(function()
			assert.are.equal(123, GetTime())
			now = 135
			assert.are.equal(135, GetTime())
		end)
		ui:restore()
		assert.is_true(ok, err)
		assert.are.equal(previous, GetTime)
	end)
end)
