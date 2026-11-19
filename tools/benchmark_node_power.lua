-- Measure node-power work in a synthetic or explicitly supplied build without saving it.
local fixture = assert(arg[1], "Supply a build XML path")
local frames = tonumber(arg[2]) or 30
assert(frames >= 1 and frames <= 1000 and frames == math.floor(frames), "Frame count must be 1 to 1000")
arg = {}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave = true
local file = assert(io.open(fixture, "rb"))
local raw = file:read("*a")
file:close()
loadBuildFromXML(raw, "Read-only node power benchmark")
assert(not main.popups[1], "The supplied build requires conversion")
local ui = require("Modules.HeadlessUI").install({width=1280, height=720, interactiveRecovery=true,
	clock=function() return os.clock()*1000 end})
build.viewMode = "TREE"
ui:bind(build)
ui:frame()
build.treeTab.viewer.showHeatMap = true
build.calcsTab.powerBuildFlag = true
local tab, slices, frameTimes = build.calcsTab, {}, {}
local original = tab.BuildPower
function tab:BuildPower(...)
	local start = os.clock()
	local result = original(self, ...)
	slices[#slices+1] = (os.clock()-start)*1000
	return result
end
for i = 1, frames do
	local start = os.clock()
	ui:frame()
	frameTimes[i] = (os.clock()-start)*1000
end
print("NODE_POWER_RESPONSIVENESS " .. require("dkjson").encode({slicesMs=slices, framesMs=frameTimes,
	completed=tab.powerBuilder == nil and not tab.powerBuildFlag,
	limitations="CPU clock measures headless work, including draw-command capture; it is not desktop rendering or frame rate."}))
