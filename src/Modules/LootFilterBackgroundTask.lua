-- Manage a per-user Windows task from the PoB desktop. The task owns no filter
-- policy and calls the same native worker as the on-demand command.
local M = {}
local sync = require("Modules.LootFilterDailySync")
local sha = require("sha1")

-- Run registration away from the UI. Windows PowerShell is resolved from the
-- system directory and invoked directly, with no command interpreter or PATH lookup.
local registerScript = [=[
local enable, taskName, workingDirectory, userPath = ...
local ok, result = pcall(function()
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
		"; $configFile = " .. literal(userPath .. "LootFilterDailySync.json") .. [[

function Read-SyncSettings {
    try { return Get-Content -LiteralPath $configFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return $null }
}
function Get-AdjustedCutoffs($review) {
    $cutoffs = @{}
    foreach ($change in $review.changes) {
        $key = $change.source + '|' + $change.name + '|' + ($change.classes -join ',') + '|' + $change.maps + '|' + $change.old
        $cutoffs[$key] = $change.cutoff
    }
    return $cutoffs
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

$before = Read-SyncSettings
if (-not $before.enabled -or -not $before.backgroundEnabled -or $before.paused) { exit 0 }
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { exit 1 }
$process = Start-Process -FilePath $exe -WorkingDirectory $dir -ArgumentList '--loot-filter-sync-scheduled' -WindowStyle Hidden -Wait -PassThru
$after = Read-SyncSettings
if ($after.backgroundEnabled -and $after.backgroundNotifications -and $after.enabled -and -not $after.paused -and
    $after.revision -eq $before.revision) {
    try {
        if ($process.ExitCode -ne 0 -and $after.lastFailure -and $after.lastFailure.message -ne $before.lastFailure.message) {
            Show-SyncNotification 'A scheduled update failed. Review the last attempt in Daily price sync.' $true
        } elseif ($process.ExitCode -eq 0 -and $after.current -ne $before.current -and $after.lastSuccess -ne $before.lastSuccess) {
            $old = Get-AdjustedCutoffs $before.review
            $new = Get-AdjustedCutoffs $after.review
            $changed = 0
            foreach ($key in (@($old.Keys) + @($new.Keys) | Select-Object -Unique)) {
                if ($old[$key] -ne $new[$key]) { $changed++ }
            }
            if ($changed -ge 5) { Show-SyncNotification "$changed managed cutoffs changed after checking protected drops." $false }
        }
    } catch {
        # A disabled notification surface cannot change the sync result.
    }
}
exit $process.ExitCode
]]
	local script = "$ErrorActionPreference = 'Stop'; $name = " .. literal(taskName) .. [[

$description = 'Path of Building AI Edition loot filter background sync'
$task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
if ($task -and $task.Description -ne $description) { exit 1 }
]]
	if enable then
		script = script .. "$powershell = " .. literal(powershell) ..
			"; $arguments = " .. literal(launchArguments .. encode(worker)) .. [[

$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments
$principal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Limited
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 7)
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
	if waited == 0 then ffi.C.GetExitCodeProcess(process.process, exitCode) end
	if waited == 258 then ffi.C.TerminateProcess(process.process, 1) end
	ffi.C.CloseHandle(process.process)
	assert(waited == 0 and exitCode[0] == 0, "Windows Task Scheduler did not accept the change. Check permissions for the current user.")
end)
return ok, result
]=]

function M.change(enabled, callback)
	assert(require("ffi").os == "Windows", "Background sync requires Windows")
	assert(not M.busy, "Wait for the current background sync setup")
	local config = assert(sync.configuration(), "Enable daily sync first")
	local directory = GetRuntimePath()
	local taskName = "PoB AI Loot Sync " .. sha(main.userPath:lower()):sub(1,16)
	local id = assert(LaunchSubScript(registerScript, "", "", enabled, taskName, directory, main.userPath),
		"Could not start background sync setup")
	M.busy = true
	launch:RegisterSubScript(id, function(ok, why)
		M.busy = false
		if ok then ok, why = pcall(sync.setBackground, enabled, config.revision) end
		callback(ok, why)
	end)
end

return M
