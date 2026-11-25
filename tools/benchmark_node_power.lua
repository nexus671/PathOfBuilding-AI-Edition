-- Measure node-power work in a synthetic or explicitly supplied build without saving it.
local fixture = assert(arg[1], "Supply a build XML path")
local frames = tonumber(arg[2]) or 30
local noCapture = arg[3] == "no-capture"
assert(not arg[3] or noCapture, "Third argument must be no-capture")
local metric = arg[4]
assert(not metric or metric == "life" or metric == "full-dps", "Fourth argument must be life or full-dps")
local includeAll = arg[5] == "include-all"
assert(not arg[5] or includeAll, "Fifth argument must be include-all")
local forceFull = arg[6] == "force-full"
assert(not arg[6] or forceFull, "Sixth argument must be force-full")
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
if noCapture then
	DrawImage = function() end
	DrawImageQuad = function() end
	DrawString = function() end
end
if includeAll then
	for _,group in ipairs(build.skillsTab.socketGroupList) do
		if group.enabled ~= false then group.includeInFullDPS = true end
	end
end
build.viewMode = "TREE"
if includeAll then build.buildFlag=true;runCallback("OnFrame") end
ui:bind(build)
ui:frame()
build.treeTab.viewer.showHeatMap = true
build.calcsTab.powerBuildFlag = true
if metric then build.calcsTab.powerStat = {stat=metric=="life" and "Life" or "FullDPS"} end
local tab, slices, frameTimes = build.calcsTab, {}, {}
local evaluations, getCalculator = 0, tab.GetMiscCalculator
function tab:GetMiscCalculator()
	local calculator,base = getCalculator(self)
	return function(override,fullDPS)
		evaluations = evaluations+1
		return calculator(override,forceFull and true or fullDPS)
	end,base
end
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
	completed=tab.powerBuilder == nil and not tab.powerBuildFlag, drawCapture=not noCapture,
	evaluations=evaluations, metric=metric or "saved", includeAll=includeAll, forceFull=forceFull,
	limitations=noCapture and "CPU clock measures headless work without drawing calls; it is not desktop rendering or frame rate."
		or "CPU clock measures headless work, including draw-command capture; it is not desktop rendering or frame rate."}))
