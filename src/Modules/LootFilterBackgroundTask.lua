-- Manage a per-user Windows task from the PoB desktop. The task owns no filter
-- policy and calls the same native worker as the on-demand command.
local M = {}
local sync = require("Modules.LootFilterDailySync")
local market = require("Modules.LootFilterEconomy")
local sha = require("sha1")

-- Run registration away from the UI. Windows PowerShell is resolved from the
-- system directory and invoked directly, with no command interpreter or PATH lookup.
local registerScript = [=[
local enable, taskName, workingDirectory, endpoint, executionSeconds = ...
local ok, result = pcall(function()
	local inspecting = enable=="inspect"
	assert(inspecting or type(enable)=="boolean", "Invalid background task request")
	local windows = require("Modules.LootFilterWindowsProcess")
	local literal = windows.literal
	local script = "$ErrorActionPreference = 'Stop'; $name = " .. literal(taskName) .. [[

$description = 'Path of Building AI Edition loot filter background sync'
try {
    $task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
} catch {
    if ($_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
    $task = $null
}
if ($task -and $task.Description -ne $description) { exit 11 }
]]
	if enable then
		assert(type(executionSeconds)=="number" and executionSeconds>0 and executionSeconds==math.floor(executionSeconds), "Invalid task execution limit")
		script = script .. "$executionSeconds = "..executionSeconds.."\n"
		script = script .. "$dir = [IO.Path]::GetFullPath("..literal(workingDirectory).."); "..
			"$exe = Join-Path $dir 'Path of Building.exe'; $launcher = Join-Path $dir 'PoBLootSync.exe'; "..
			"$arguments = "..literal(endpoint).."\n"
	end
	if inspecting then
		script = script .. [[
if (-not $task) { exit 10 }
if ($task.State -eq 'Disabled' -or -not $task.Settings.Enabled) { exit 12 }
if (@($task.Actions).Count -ne 1 -or $task.Actions[0].Execute -ne $launcher -or
    $task.Actions[0].WorkingDirectory -ne $dir -or $task.Actions[0].Arguments -cne $arguments) { exit 13 }
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
try {
    $actual = $task.Principal.UserId
    if (-not $actual.StartsWith('S-1-')) {
        $actual = ([System.Security.Principal.NTAccount]::new($actual)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    }
} catch { exit 14 }
if ($actual -ne $sid -or $task.Principal.LogonType -ne 'Interactive' -or $task.Principal.RunLevel -ne 'Limited') { exit 14 }
try {
    $trigger = $task.Triggers[0]
    if (@($task.Triggers).Count -ne 1 -or $trigger.CimClass.CimClassName -ne 'MSFT_TaskTimeTrigger' -or
        -not $trigger.Enabled -or $trigger.EndBoundary -or $trigger.Repetition.Duration -or
        [System.Xml.XmlConvert]::ToTimeSpan($trigger.Repetition.Interval).TotalMinutes -ne 5 -or
        $task.Settings.MultipleInstances -ne 'IgnoreNew' -or -not $task.Settings.StartWhenAvailable -or
        [System.Xml.XmlConvert]::ToTimeSpan($task.Settings.ExecutionTimeLimit).TotalSeconds -ne $executionSeconds) { exit 15 }
} catch { exit 15 }
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { exit 16 }
if ($task.State -eq 'Running') { exit 17 }
if ($task.State -ne 'Ready') { exit 18 }
exit 0
]]
	elseif enable then
		script = script .. [[

$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf) -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { exit 16 }
$action = New-ScheduledTaskAction -Execute $launcher -Argument $arguments -WorkingDirectory $dir
$principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds $executionSeconds)
Register-ScheduledTask -TaskName $name -TaskPath '\' -Description $description -Action $action -Principal $principal -Trigger $trigger -Settings $settings -Force | Out-Null
exit 0
]]
	else
		script = script .. [[

if ($task) { Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false }
exit 0
]]
	end
	local exitCode = windows.run(script,30000)
	if inspecting then
		assert(exitCode, "Windows Task Scheduler did not return a status")
		local states = {[0]="ready",[10]="missing",[11]="foreign",[12]="disabled",[13]="action_changed",
			[14]="account_changed",[15]="trigger_changed",[16]="executable_missing",[17]="running",[18]="unavailable"}
		return assert(states[exitCode], "Could not read the Windows task. Check permissions for the current user.")
	end
	assert(exitCode == 0, "Windows Task Scheduler did not accept the change. Check permissions for the current user.")
end)
return ok, result
]=]

local function launchTaskCheck(mode)
	local taskName = "PoB AI Loot Sync " .. sha(main.userPath:lower()):sub(1,16)
	local endpoint = mode and assert(market.endpoint, market.endpointError) or ""
	return LaunchSubScript(registerScript, "", "", mode, taskName, GetRuntimePath(), (endpoint:gsub("/$", "")), sync.taskExecutionSeconds)
end

function M.inspect(callback)
	assert(require("ffi").os=="Windows", "Background sync requires Windows")
	assert(not M.busy, "Wait for the current background sync check")
	local id = assert(launchTaskCheck("inspect"), "Could not start Windows task inspection")
	M.busy = true
	launch:RegisterSubScript(id,function(ok,state)
		M.busy = false
		callback(ok,state)
	end)
end

function M.change(enabled, callback, profileId)
	assert(require("ffi").os == "Windows", "Background sync requires Windows")
	assert(not M.busy, "Wait for the current background sync setup")
	profileId = profileId or "default"
	local release = sync.acquireBackgroundSetup()
	local ok, problem = pcall(function()
		local config = assert(sync.configuration(profileId,false), "Enable daily sync first")
		if enabled then sync.assertPriceSource(config) end
		if not enabled then
			for _, entry in ipairs(sync.profiles()) do
				if entry.id ~= profileId then
					local other = sync.configuration(entry.id,false)
					if other and other.backgroundEnabled then
						sync.setBackground(false, config.revision, profileId)
						release()
						return false
					end
				end
			end
		end
		local id = assert(launchTaskCheck(enabled), "Could not start background sync setup")
		M.busy = true
		launch:RegisterSubScript(id, function(passed, why)
			M.busy = false
			if passed then passed, why = pcall(sync.setBackground, enabled, config.revision, profileId) end
			release()
			callback(passed, why)
		end)
		return true
	end)
	if not ok then release(); error(problem,0) end
	if not problem then callback(true) end
end

return M
