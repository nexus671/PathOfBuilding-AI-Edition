-- Fast headless coverage for comparison-baseline regressions. The complete
-- Busted suite remains authoritative; this runs two existing cases early.
local selection = arg[1] or "all"
assert(selection == "all" or selection == "timings" or selection == "jewel", "Choose all, timings or jewel")
arg = {}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave = true

local nativeAssert = assert
local checks = setmetatable({}, { __call = function(_, ...) return nativeAssert(...) end })
function checks.equal(expected, actual) nativeAssert(expected == actual, tostring(expected).." ~= "..tostring(actual)) end
function checks.is_true(value, message) nativeAssert(value == true, message or "Expected true") end
function checks.is_truthy(value, message) nativeAssert(value, message or "Expected a value") end
assert = checks

local targets = {
	["reports the individual native calculation passes"] = selection ~= "jewel" and true or nil,
	["AddItemTooltip emits a remove-comparison block for an equipped Timeless jewel"] = selection ~= "timings" and true or nil,
}
local setup, cleanup, count
count = 0
function describe(_, fn) setup, cleanup = nil, nil; fn() end
function before_each(fn) setup = fn end
function after_each(fn) cleanup = fn end
function teardown(_) end
function it(name, fn)
	if targets[name] == nil then return end
	nativeAssert(targets[name] == true, "Duplicate comparison contract case: "..name)
	if setup then setup() end
	local ok, err = pcall(fn)
	if cleanup then cleanup() end
	nativeAssert(ok, err)
	targets[name] = false
	count = count + 1
	print("PASS "..name)
end

dofile("../spec/System/TestPlanningFlows_spec.lua")
dofile("../spec/System/TestRadiusJewelStatDiff_spec.lua")
nativeAssert(count == (selection == "all" and 2 or 1), "A comparison contract case is missing")
print("COMPARISON_CONTRACT_OK "..count)
