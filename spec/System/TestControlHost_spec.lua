describe("Control host tooltip focus", function()
	it("only blocks other tooltips when the focused control is hovered or open", function()
		local host = new("ControlHost"):ControlHost()
		local blocked
		local focused = { hasFocus = true, IsMouseOver = function() return false end, IsShown = function() return true end, Draw = function() end }
		local other = { IsShown = function() return true end, Draw = function(_, _, value) blocked = not not value end }
		host.controls = { focused, other }; host.selControl = focused
		host:DrawControls({}); assert.is_false(blocked)
		focused.IsMouseOver = function() return true end
		host:DrawControls({}); assert.is_true(blocked)
		focused.IsMouseOver = function() return false end; focused.dropped = true
		host:DrawControls({}); assert.is_true(blocked)
	end)
end)
