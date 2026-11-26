-- Compare only managed visibility and appearance, once per rule.
local json = require("dkjson")
local M = {}

local function nullable(value)
	if value == nil then return json.null end
	return value
end

local function managedChanges(review)
	local rules = {}
	for _, change in ipairs(review and review.changes or {}) do
		if change.cutoff ~= nil then
			local classes, seen = {}, {}
			for _, class in ipairs(change.classes or {}) do
				if not seen[class] then
					classes[#classes + 1], seen[class] = class, true
				end
			end
			table.sort(classes)
			local key = json.encode({change.name, classes, change.scope or (change.maps and "maps" or "all"),
				nullable(change.old), nullable(change.tier), nullable(change.blighted), nullable(change.ravaged),
				nullable(change.gemLevel), nullable(change.gemQuality), nullable(change.corrupted), not not change.uniqueBase})
			local outcomes = rules[key] or {}
			if change.old ~= change.cutoff then outcomes["cutoff:"..change.cutoff] = true end
			for _, highlight in ipairs(change.highlights or {}) do
				if highlight.firstStack ~= nil and highlight.icon then
					local actions = highlight.actions or {}
					local volume = actions.volume or (actions.sound ~= nil and 50 or json.null)
					outcomes[json.encode({highlight.firstStack, highlight.icon, nullable(actions.sound),
						volume, nullable(actions.fontSize)})] = true
				end
			end
			if next(outcomes) then rules[key] = outcomes end
		end
	end
	return rules
end

local function differs(first, second)
	if not second then return true end
	for key in pairs(first) do if not second[key] then return true end end
	for key in pairs(second) do if not first[key] then return true end end
	return false
end

function M.countChanges(before, after)
	local old, new = managedChanges(before), managedChanges(after)
	local count = 0
	for key, outcomes in pairs(old) do if differs(outcomes, new[key]) then count = count + 1 end end
	for key in pairs(new) do if not old[key] then count = count + 1 end end
	return count
end

function M.profile(sync, id)
	local config = sync.configuration(id, false)
	return config and config.enabled and config.backgroundEnabled and config.backgroundNotifications
		and not config.paused and config or nil
end

function M.summarize(sync, before, failed)
	local failures, changed = 0, 0
	for id, previous in pairs(before) do
		local current = M.profile(sync, id)
		if current and current.revision == previous.revision then
			if failed and current.lastFailure
				and current.lastFailure.message ~= (previous.lastFailure and previous.lastFailure.message) then
				failures = failures + 1
			elseif current.current ~= previous.current and current.lastSuccess ~= previous.lastSuccess
				and current.review and (current.review.protectedChecks or 0) > 0 then
				changed = changed + M.countChanges(previous.review, current.review)
			end
		end
	end
	if failures > 0 then return "A scheduled update failed. Review the last attempt in Daily price sync.", true end
	if changed >= 5 then return string.format("%d managed loot rules changed after checking protected drops.",changed), false end
end

function M.notify(text, failed)
	local windows = require("Modules.LootFilterWindowsProcess")
	local dir = GetRuntimePath()
	local script = "$ErrorActionPreference = 'Stop'; $dir = "..windows.literal(dir)..
		"; $exe = "..windows.literal(dir.."/Path of Building.exe")..[[

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

	]]
	script = script .. "Show-SyncNotification "..windows.literal(text).." $"..tostring(failed)
	windows.run(script,15000)
end

return M
