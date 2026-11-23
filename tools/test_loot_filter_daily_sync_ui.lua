arg = {}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave = true

local sync = require("Modules.LootFilterDailySync")
local headless = require("Modules.HeadlessUI")
local selected = "C:/PoE/selected.filter"
local configured

function GetUserPath() return "C:/Users/QA/Documents" end
sync.selectedLocalFilter = function(dir)
	assert(dir == "C:/Users/QA/Documents/My Games/Path of Exile")
	return selected
end
sync.configuration = function()
	return {hour=9, minute=15}
end
sync.diagnosticReport = function()
	return '{"version":1}'
end
sync.configure = function(target, baseline, _, options)
	assert(target == selected and baseline == "C:/PoE/baseline.filter")
	assert(options.hour == 12 and options.minute == 37)
	configured = true
end

for _, size in ipairs({{1280,720}, {960,640}, {720,600}}) do
	newBuild()
	main.popups = {}
	configured = false
	local harness = headless.install({width=size[1], height=size[2]})
	harness:bind(build)
	require("Classes.LootFilterDailySyncControl").Open()
	assert(main.popups[1].controls.time.buf == "09:15")
	harness:click("detectTarget")
	assert(main.popups[1].controls.target.buf == selected)
	harness:text("baseline", "C:/PoE/baseline.filter")
	harness:text("time", "12:37")
	harness:click("enable")
	assert(configured and main.popups[1].title == "Daily filter sync")
	harness:click("copyReport")
	assert(harness.clipboard == '{"version":1}' and main.popups[1].title == "Sync diagnostics")
	harness:frame()
	print(string.format("Native setup and diagnostics controls passed at %dx%d.", unpack(size)))
end
