-- Run from src with a build XML path. The build is loaded in memory and never saved.
local fixture = assert(arg[1], "Supply a build XML path")
local cycles = tonumber(arg[2]) or 5
assert(cycles >= 1 and cycles <= 20 and cycles == math.floor(cycles))
arg = {}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave = true
local file = assert(io.open(fixture, "rb"))
local raw = file:read("*a")
file:close()
loadBuildFromXML(raw, "Read-only tree UI benchmark")
assert(not main.popups[1], "The supplied build requires conversion")
local bridge = require("Modules.DesktopBuildBridge")
local revision = bridge.revision(build)
local ui = require("Modules.HeadlessUI").install({width=1280,height=720})
build.viewMode = "TREE"
ui:bind(build)
local viewer = build.treeTab.viewer
local originalDraw, viewport = viewer.Draw
viewer.Draw = function(self, host, rect, events)
	viewport = rect
	return originalDraw(self, host, rect, events)
end
ui:frame()
local selected
for _, node in pairsSortByKey(build.spec.nodes) do
	if not node.alloc and node.type == "Normal" and not node.isMultipleChoiceOption
		and not node.ascendancyName and node.path and #node.path == 1 and node.rsq
		and not node.isProxy and node.group and not node.group.isProxy then
		selected = node
		break
	end
end
assert(selected, "No visible adjacent normal passive found")
viewer:Focus(selected.x, selected.y, viewport, build)
ui:frame()
local x, y = viewport.x + viewport.width / 2, viewport.y + viewport.height / 2
local rows = {}
for _ = 1, cycles do
	local start = os.clock()
	ui.cursorX, ui.cursorY = x, y
	ui:frame()
	local hovered = os.clock()
	ui:dispatch(build, {{type="KeyDown",key="LEFTBUTTON"}})
	local pressed = os.clock()
	ui:dispatch(build, {{type="KeyUp",key="LEFTBUTTON"}})
	local clicked = os.clock()
	assert(selected.alloc, "Click did not allocate the intended passive")
	ui:frame()
	local updated = os.clock()
	ui:clickAt(x,y)
	assert(not selected.alloc, "Second click did not remove the passive")
	ui:frame()
	rows[#rows+1] = { hoverMs=(hovered-start)*1000, pressMs=(pressed-hovered)*1000,
		releaseMs=(clicked-pressed)*1000, updateFrameMs=(updated-clicked)*1000 }
end
assert(bridge.revision(build) == revision, "The benchmark did not restore the build revision")
print("TREE_UI_RESPONSIVENESS " .. require("dkjson").encode({node=selected.id,cycles=rows,restored=true,
	limitations="Headless CPU timings include draw-command capture, not desktop rendering or frame rate."}))
