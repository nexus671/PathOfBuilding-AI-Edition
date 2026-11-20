-- Run from src with a build XML path. The build is loaded in memory and never saved.
local fixture = assert(arg[1], "Supply a build XML path")
local cycles = tonumber(arg[2]) or 5
assert(cycles >= 1 and cycles <= 20 and cycles == math.floor(cycles))
local allowed = {["deferred-recovery"]=true,["desktop-recovery"]=true,["skill-profile"]=true,["no-capture"]=true,["full-profile"]=true,["include-all"]=true,["convert-latest"]=true}
local flags = {}
for i = 3, #arg do local flag=arg[i];assert(allowed[flag] and not flags[flag], "Unknown or repeated benchmark option: "..tostring(flag));flags[flag]=true end
assert(not (flags["deferred-recovery"] and flags["desktop-recovery"]), "Choose one recovery mode")
local forcedRecovery = flags["deferred-recovery"] or false
local desktopRecovery = forcedRecovery or flags["desktop-recovery"] or false
local profileSkills = flags["skill-profile"] or false
local noCapture = flags["no-capture"] or false
local profileFull = flags["full-profile"] or false
local includeAll = flags["include-all"] or false
local convertLatest = flags["convert-latest"] or false
arg = {}
dofile("HeadlessWrapper.lua")
main.disableDevAutoSave = true
local file = assert(io.open(fixture, "rb"))
local raw = file:read("*a")
file:close()
loadBuildFromXML(raw, "Read-only tree UI benchmark")
assert(not main.popups[1], "The supplied build requires conversion")
if convertLatest then build.treeTab:ConvertToVersion(latestTreeVersion,true,false) end
if includeAll then
	for _,group in ipairs(build.skillsTab.socketGroupList) do
		if group.enabled ~= false then group.includeInFullDPS = true end
	end
	build.buildFlag=true;runCallback("OnFrame")
end
if forcedRecovery then
	build.configTab.input.simulateRecovery = true
	build.configTab.input.recoverySimulationTrials = 32
	build.configTab.input.recoverySimulationWindow = 60
end
local bridge = require("Modules.DesktopBuildBridge")
local revision = bridge.revision(build)
local ui = require("Modules.HeadlessUI").install({width=1280,height=720,interactiveRecovery=desktopRecovery})
-- Suppress captured draw calls only for CPU profiling. This is not a renderer benchmark.
if noCapture then
	DrawImage = function() end
	DrawImageQuad = function() end
	DrawString = function() end
end
local recoveryStarted=false
local recoverySlices
if desktopRecovery then
	local tasks = require("Modules.RecoveryTasks")
	local tick = tasks.tick
	tasks.tick = function(tab, ...)
		local active = tab.recoveryJob ~= nil
		local start = os.clock()
		local result = tick(tab, ...)
		if active and recoverySlices then
			local elapsed = (os.clock() - start) * 1000
			recoverySlices.count = recoverySlices.count + 1
			recoverySlices.totalMs = recoverySlices.totalMs + elapsed
			recoverySlices.worstMs = math.max(recoverySlices.worstMs, elapsed)
		end
		return result
	end
	local buildOutput=build.calcsTab.BuildOutput
	build.calcsTab.BuildOutput=function(self,...)
		local result=buildOutput(self,...);recoveryStarted=recoveryStarted or self.recoveryJob~=nil;return result
	end
end
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
	if not node.alloc and (node.type == "Normal" or node.type == "Notable") and not node.isMultipleChoiceOption
		and not node.ascendancyName and node.path and #node.path == 1 and node.rsq
		and not node.isProxy and node.group and not node.group.isProxy then
		selected = node
		break
	end
end
assert(selected, "No visible adjacent small or notable passive found")
viewer:Focus(selected.x, selected.y, viewport, build)
ui:frame()
local x, y = viewport.x + viewport.width / 2, viewport.y + viewport.height / 2
local rows = {}
local function finishRecovery()
	if not desktopRecovery or not build.configTab.input.simulateRecovery then return nil end
	local count, total, worst = 0, 0, 0
	while build.calcsTab.recoveryJob do
		assert(count < 10000, "Recovery worker did not complete")
		local start = os.clock()
		ui:frame()
		local elapsed = (os.clock() - start) * 1000
		count, total, worst = count + 1, total + elapsed, math.max(worst, elapsed)
	end
	for _, env in ipairs({ build.calcsTab.mainEnv, build.calcsTab.calcsEnv }) do
		assert(not env.player.output.RecoverySimulationPending, "Recovery result is still pending")
		assert(not env.player.output.RecoverySimulationUnsupported, "Recovery simulation failed or is unsupported")
		assert(env.player.recoverySimulationResults, "Recovery worker completed without results")
	end
	return { frames=count, totalFrameMs=total, worstFrameMs=worst, workerSlices=recoverySlices }
end
local skillProfile
if profileSkills then
	skillProfile={count=0,totalMs=0,worstMs=0,components={}}
	local calcs=build.calcsTab.calcs;local previous=calcs.buildActiveSkill
	local depth=0
	local function pack(...) return {n=select("#",...),...} end
	calcs.buildActiveSkill=function(...)
		depth=depth+1;local start=os.clock();local result=pack(previous(...));local elapsed=(os.clock()-start)*1000;depth=depth-1
		skillProfile.count=skillProfile.count+1;skillProfile.totalMs=skillProfile.totalMs+elapsed;skillProfile.worstMs=math.max(skillProfile.worstMs,elapsed)
		return unpack(result,1,result.n)
	end
	for _,name in ipairs({"initEnv","buildModListForNodeList","buildActiveSkillModList","defence","offence"}) do
		local fn=calcs[name]
		calcs[name]=function(...)
			local measured=depth>0;local start=measured and os.clock();local result=pack(fn(...))
			if measured then
				local elapsed=(os.clock()-start)*1000;local row=skillProfile.components[name] or {count=0,totalMs=0,worstMs=0}
				row.count=row.count+1;row.totalMs=row.totalMs+elapsed;row.worstMs=math.max(row.worstMs,elapsed);skillProfile.components[name]=row
			end
			return unpack(result,1,result.n)
		end
	end
end
local fullProfile
if profileFull then
	fullProfile={components={}}
	local calcs=build.calcsTab.calcs
	local originalFull,originalOutput,originalMisc=calcs.calcFullDPS,calcs.buildOutput,calcs.getMiscCalculator
	local phase="other"
	local function pack(...) return {n=select("#",...),...} end
	calcs.calcFullDPS=function(...)
		local start=os.clock();local result=pack(originalFull(...));local elapsed=(os.clock()-start)*1000
		local row=fullProfile.components[phase] or {count=0,totalMs=0,worstMs=0}
		row.count=row.count+1;row.totalMs=row.totalMs+elapsed;row.worstMs=math.max(row.worstMs,elapsed);fullProfile.components[phase]=row
		return unpack(result,1,result.n)
	end
	calcs.buildOutput=function(buildArg,mode,...)
		local previous=phase;phase=mode;local result=pack(originalOutput(buildArg,mode,...));phase=previous
		return unpack(result,1,result.n)
	end
	calcs.getMiscCalculator=function(...)
		local previous=phase;phase="comparison setup";local calculator,base=originalMisc(...);phase=previous
		return function(...)
			local previousPhase=phase;phase="comparison evaluation";local result=pack(calculator(...));phase=previousPhase
			return unpack(result,1,result.n)
		end,base
	end
end
local performance=require("Modules.PlanningPerformance")
performance.clear(build)
for _ = 1, cycles do
	recoveryStarted=false
	recoverySlices={count=0,totalMs=0,worstMs=0}
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
	if desktopRecovery and build.configTab.input.simulateRecovery then assert(recoveryStarted, "Tree update did not start deferred recovery") end
	local recovery = finishRecovery()
	recoveryStarted=false
	recoverySlices={count=0,totalMs=0,worstMs=0}
	ui:clickAt(x,y)
	assert(not selected.alloc, "Second click did not remove the passive")
	ui:frame()
	if desktopRecovery and build.configTab.input.simulateRecovery then assert(recoveryStarted, "Tree removal did not start deferred recovery") end
	finishRecovery()
	rows[#rows+1] = { hoverMs=(hovered-start)*1000, pressMs=(pressed-hovered)*1000,
		releaseMs=(clicked-pressed)*1000, updateFrameMs=(updated-clicked)*1000, recovery=recovery }
end
assert(bridge.revision(build) == revision, "The benchmark did not restore the build revision")
print("TREE_UI_RESPONSIVENESS " .. require("dkjson").encode({node=selected.id,cycles=rows,components=performance.rows(build),skillProfile=skillProfile,fullProfile=fullProfile,includeAll=includeAll,convertedToLatest=convertLatest,treeVersion=build.spec.treeVersion,restored=true,
	recoveryMode=forcedRecovery and "deferred" or desktopRecovery and "desktop with saved settings" or "build configuration",
	drawCapture=not noCapture,
	limitations=noCapture and "Headless CPU timings omit drawing calls and do not measure desktop rendering or frame rate."
		or "Headless CPU timings include draw-command capture, not desktop rendering or frame rate."}))
