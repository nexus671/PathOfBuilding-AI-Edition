-- Manage a per-user Windows task from the PoB desktop. The task owns no filter
-- policy and calls the same native worker as the on-demand command.
local M = {}
local sync = require("Modules.LootFilterDailySync")
local market = require("Modules.LootFilterEconomy")
local sha = require("sha1")

-- Run registration away from the UI. Windows PowerShell is resolved from the
-- system directory and invoked directly, with no command interpreter or PATH lookup.
local registerScript = [=[
local enable, taskName, workingDirectory, userPath, endpoint, executionSeconds = ...
local ok, result = pcall(function()
	local inspecting = enable=="inspect"
	assert(inspecting or type(enable)=="boolean", "Invalid background task request")
	local ffi = require("ffi")
	local base64 = require("base64")
	ffi.cdef[[
		typedef struct {
			uint32_t cb;
			uint16_t *reserved, *desktop, *title;
			uint32_t x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags;
			uint16_t showWindow, reservedSize;
			uint8_t *reservedData;
			void *standardInput, *standardOutput, *standardError;
		} PoBLootStartupInfo;
		typedef struct {
			void *process, *thread;
			uint32_t processId, threadId;
		} PoBLootProcessInfo;
		int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char *, int, uint16_t *, int);
		int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const uint16_t *, int, char *, int, const char *, int *);
		unsigned int __stdcall GetSystemDirectoryW(uint16_t *, unsigned int);
		int __stdcall CreateProcessW(const uint16_t *, uint16_t *, void *, void *, int, uint32_t, void *, const uint16_t *, PoBLootStartupInfo *, PoBLootProcessInfo *);
		uint32_t __stdcall WaitForSingleObject(void *, uint32_t);
		int __stdcall GetExitCodeProcess(void *, uint32_t *);
		int __stdcall TerminateProcess(void *, unsigned int);
		int __stdcall CloseHandle(void *);
	]]

	local function wide(value)
		local size = ffi.C.MultiByteToWideChar(65001, 8, value, #value, nil, 0)
		assert(size > 0, "Invalid Windows command text")
		local buffer = ffi.new("uint16_t[?]", size + 1)
		assert(ffi.C.MultiByteToWideChar(65001, 8, value, #value, buffer, size) == size, "Could not encode Windows command text")
		return buffer, size
	end
	local function encode(value)
		local buffer, size = wide(value)
		return base64.encode(ffi.string(buffer, size * 2))
	end
	local function literal(value)
		return "'" .. value:gsub("'", "''") .. "'"
	end
	local system = ffi.new("uint16_t[?]", 32768)
	local length = ffi.C.GetSystemDirectoryW(system, 32768)
	assert(length > 0 and length < 32768, "Could not find the Windows system directory")
	local bytes = ffi.new("char[?]", length * 4)
	local count = ffi.C.WideCharToMultiByte(65001, 0, system, length, bytes, length * 4, nil, nil)
	assert(count > 0, "Could not read the Windows system directory")
	local powershell = ffi.string(bytes, count) .. "\\WindowsPowerShell\\v1.0\\powershell.exe"
	local command = '"%s" -NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand %s'
	local launchArguments = "-NoLogo -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand "
	local executable = workingDirectory .. "/Path of Building.exe"
	local worker = "$ErrorActionPreference = 'Stop'; $exe = " .. literal(executable) ..
		"; $dir = " .. literal(workingDirectory) ..
		"; $userPath = " .. literal(userPath) ..
		"; $env:POB_MARKET_CACHE_URL = " .. literal(endpoint or "") .. [[

$script:syncSettingsReadFailed = $false
function Read-JsonFile([string]$name) {
    try {
        $text = Get-Content -LiteralPath (Join-Path $userPath $name) -Raw -Encoding UTF8
        $prefix = if ($name -eq 'LootFilterSyncProfiles.json') { '[' } else { '{' }
        if ($null -eq $text -or -not $text.TrimStart().StartsWith($prefix)) {
            $script:syncSettingsReadFailed = $true
            return $null
        }
        return ConvertFrom-Json -InputObject $text
    } catch {
        if ($_.CategoryInfo.Category -ne 'ObjectNotFound') { $script:syncSettingsReadFailed = $true }
        return $null
    }
}
function Read-SyncProfiles {
    $profiles = @{}
    $legacy = Read-JsonFile 'LootFilterDailySync.json'
    if ($legacy) { $profiles['default'] = $legacy }
    foreach ($entry in (Read-JsonFile 'LootFilterSyncProfiles.json')) {
        if ($entry.id -is [string] -and [regex]::IsMatch($entry.id, '\A[a-f0-9]{40}\z')) {
            $config = Read-JsonFile ('LootFilterDailySync-' + $entry.id + '.json')
            if ($config) { $profiles[$entry.id] = $config }
        }
    }
    return $profiles
}
function Get-AdjustedCutoffs($review) {
    $cutoffs = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
    foreach ($change in $review.changes) {
        if ($null -eq $change.cutoff -or $change.old -eq $change.cutoff) { continue }
        $scope = $change.scope
        if (-not $scope) { $scope = if ($change.maps) { 'maps' } else { 'all' } }
        $conditions = @(
            $change.name, (@($change.classes | Sort-Object) -join ','),
            $scope, $change.old, $change.tier, $change.blighted, $change.ravaged,
            $change.gemLevel, $change.gemQuality, $change.corrupted
        )
        $key = ConvertTo-Json -InputObject $conditions -Compress
        if (-not $cutoffs.ContainsKey($key) -or $change.cutoff -gt $cutoffs[$key]) {
            $cutoffs[$key] = [int]$change.cutoff
        }
    }
    return ,$cutoffs
}
function Count-ChangedCutoffs($before, $after) {
    $old = Get-AdjustedCutoffs $before
    $new = Get-AdjustedCutoffs $after
    $count = 0
    foreach ($key in $old.Keys) {
        if (-not $new.ContainsKey($key) -or $old[$key] -ne $new[$key]) { $count++ }
    }
    foreach ($key in $new.Keys) {
        if (-not $old.ContainsKey($key)) { $count++ }
    }
    return $count
}
function Show-SyncNotification([string]$text, [bool]$failed) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $icon.BalloonTipTitle = 'PoB AI Edition loot filter'
        $icon.BalloonTipIcon = if ($failed) { 'Warning' } else { 'Info' }
        $icon.BalloonTipText = $text + ' Click to open PoB.'
        $script:openRequested = $false
        $icon.add_BalloonTipClicked({ $script:openRequested = $true })
        $icon.ShowBalloonTip(10000)
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while (-not $script:openRequested -and $clock.Elapsed.TotalSeconds -lt 12) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        if ($script:openRequested) { Start-Process -FilePath $exe -WorkingDirectory $dir }
    } finally {
        if ($icon) { $icon.Dispose() }
    }
}

$beforeProfiles = Read-SyncProfiles
$enabled = $beforeProfiles.Values | Where-Object { $_.enabled -and $_.backgroundEnabled -and -not $_.paused } | Select-Object -First 1
if (-not $enabled -and -not $script:syncSettingsReadFailed) { exit 0 }
# Let the native worker diagnose unreadable settings.
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { exit 1 }
$process = Start-Process -FilePath $exe -WorkingDirectory $dir -ArgumentList '--loot-filter-sync-scheduled' -WindowStyle Hidden -Wait -PassThru
try {
    $afterProfiles = Read-SyncProfiles
    $failures = 0
    $changed = 0
    foreach ($id in $afterProfiles.Keys) {
        $after = $afterProfiles[$id]
        $before = $beforeProfiles[$id]
        if (-not $before -or -not $after.backgroundEnabled -or -not $after.backgroundNotifications -or
            -not $after.enabled -or $after.paused -or $after.revision -ne $before.revision) { continue }
        if ($process.ExitCode -ne 0 -and $after.lastFailure -and $after.lastFailure.message -ne $before.lastFailure.message) {
            $failures++
        } elseif ($after.current -ne $before.current -and $after.lastSuccess -ne $before.lastSuccess) {
            $changed += Count-ChangedCutoffs $before.review $after.review
        }
    }
    if ($failures -gt 0) { Show-SyncNotification 'A scheduled update failed. Review the last attempt in Daily price sync.' $true }
    elseif ($changed -ge 5) { Show-SyncNotification "$changed managed cutoffs changed after checking protected drops." $false }
} catch {
    # Notification handling cannot change the native worker's result.
}
exit $process.ExitCode
]]
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
		script = script .. "$powershell = "..literal(powershell).."\n"
		if inspecting then
			local arguments = launchArguments..encode(worker)
			script = script .. "$argumentHash = "..literal(require("sha1")(arguments)).."; $exe = "..literal(executable).."\n"
		else
			-- Encode the worker in PowerShell to avoid nested base64 on the Windows command line.
			script = script .. "$arguments = "..literal(launchArguments)..
				" + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("..literal(worker).."))\n"
		end
	end
	if inspecting then
		script = script .. [[
if (-not $task) { exit 10 }
if ($task.State -eq 'Disabled' -or -not $task.Settings.Enabled) { exit 12 }
if (@($task.Actions).Count -ne 1 -or $task.Actions[0].Execute -ne $powershell) { exit 13 }
$sha = [System.Security.Cryptography.SHA1]::Create()
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$task.Actions[0].Arguments)
    $actualHash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
} finally { $sha.Dispose() }
if ($actualHash -cne $argumentHash) { exit 13 }
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
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { exit 16 }
if ($task.State -eq 'Running') { exit 17 }
if ($task.State -ne 'Ready') { exit 18 }
exit 0
]]
	elseif enable then
		script = script .. [[

$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
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
	local startup = ffi.new("PoBLootStartupInfo")
	startup.cb = ffi.sizeof(startup)
	local process = ffi.new("PoBLootProcessInfo")
	local executablePath = wide(powershell)
	local parameters = wide(command:format(powershell, encode(script)))
	assert(ffi.C.CreateProcessW(executablePath, parameters, nil, nil, 0, 0x08000000, nil, nil, startup, process) ~= 0,
		"Could not start Windows Task Scheduler setup")
	ffi.C.CloseHandle(process.thread)
	local waited = ffi.C.WaitForSingleObject(process.process, 30000)
	local exitCode = ffi.new("uint32_t[1]", 1)
	local observed = waited==0 and ffi.C.GetExitCodeProcess(process.process,exitCode)~=0
	if waited == 258 then ffi.C.TerminateProcess(process.process, 1) end
	ffi.C.CloseHandle(process.process)
	if inspecting then
		assert(observed, "Windows Task Scheduler did not return a status")
		local states = {[0]="ready",[10]="missing",[11]="foreign",[12]="disabled",[13]="action_changed",
			[14]="account_changed",[15]="trigger_changed",[16]="executable_missing",[17]="running",[18]="unavailable"}
		return assert(states[tonumber(exitCode[0])], "Could not read the Windows task. Check permissions for the current user.")
	end
	assert(observed and exitCode[0] == 0, "Windows Task Scheduler did not accept the change. Check permissions for the current user.")
end)
return ok, result
]=]

local function launchTaskCheck(mode)
	local taskName = "PoB AI Loot Sync " .. sha(main.userPath:lower()):sub(1,16)
	local endpoint = mode and assert(market.endpoint, market.endpointError) or ""
	return LaunchSubScript(registerScript, "", "", mode, taskName, GetRuntimePath(), main.userPath, (endpoint:gsub("/$", "")), sync.taskExecutionSeconds)
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
		local config = assert(sync.configuration(profileId), "Enable daily sync first")
		if enabled then sync.assertPriceSource(config) end
		if not enabled then
			for _, entry in ipairs(sync.profiles()) do
				if entry.id ~= profileId then
					local other = sync.configuration(entry.id)
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
