# cspell:ignore pscustomobject pshome
$ErrorActionPreference = 'Stop'

# Parse the command installed in Windows Task Scheduler and exercise its managed rule comparison.
$sourcePath = Join-Path $PSScriptRoot '../src/Modules/LootFilterBackgroundTask.lua'
$source = Get-Content -LiteralPath $sourcePath -Raw
$worker = [regex]::Match($source, '\$env:POB_MARKET_CACHE_URL = " \.\. literal\(endpoint or ""\) \.\. \[\[(?<script>[\s\S]*?)\r?\n\]\]')
if (-not $worker.Success) { throw 'The Windows task action could not be extracted' }
$tokens = $null
$errors = $null
$parsed = [System.Management.Automation.Language.Parser]::ParseInput(
    $worker.Groups['script'].Value, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw ($errors -join [Environment]::NewLine) }
$functions = $parsed.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -in 'Get-ManagedChanges', 'Count-ChangedManagedRules'
}, $false)
if ($functions.Count -ne 2) { throw 'The Windows managed rule comparison functions are missing' }
. ([scriptblock]::Create(($functions.Extent.Text -join [Environment]::NewLine)))

function Assert-Count($before, $after, [int]$expected) {
    $observed = Count-ChangedManagedRules ([pscustomobject]@{changes=$before}) ([pscustomobject]@{changes=$after})
    if ($observed -ne $expected) { throw "Expected $expected changed managed rules, received $observed" }
}

$map = @{name='Tier-wide'; classes=@('Maps'); scope='maps'; maps=$true; old=1; cutoff=0; source='Map'}
$gem = @{name='Added Cold Damage Support'; classes=@('Support Gems'); scope='all'; old=1; cutoff=0; gemLevel=20; gemQuality=20; source='SkillGem'}
$currency = @{name='Orb of Alteration'; classes=@('Stackable Currency'); scope='all'; old=6; cutoff=3; source='Currency'}
$rows = @(
    [pscustomobject]($map + @{tier=15; blighted=$false; ravaged=$false})
    [pscustomobject]($map + @{tier=16; blighted=$false; ravaged=$false})
    [pscustomobject]($map + @{tier=16; blighted=$true; ravaged=$false})
    [pscustomobject]($map + @{tier=16; blighted=$true; ravaged=$true})
    [pscustomobject]($gem + @{corrupted=$false})
    [pscustomobject]($gem + @{corrupted=$true})
    [pscustomobject]$currency
)
$nextCurrency = $currency.Clone()
$nextCurrency.scope = 'campaign'
$rows += [pscustomobject]$nextCurrency
Assert-Count @() $rows 8
Assert-Count $rows @() 8
Assert-Count $rows $rows 0
Assert-Count @() ($rows + $rows) 8

$retained = $currency.Clone()
$retained.source = $null
$retained.retainedReason = 'Missing quote'
Assert-Count @([pscustomobject]$currency) @([pscustomobject]$retained) 0
$retained.cutoff = 2
Assert-Count @([pscustomobject]$currency) @([pscustomobject]$retained) 1

$highlight = $currency.Clone()
$highlight.cutoff = $highlight.old
$highlight.highlights = @([pscustomobject]@{firstStack=20; icon='1 Yellow Circle'})
Assert-Count @() @([pscustomobject]$highlight) 1
Assert-Count @([pscustomobject]$currency) @([pscustomobject]$highlight) 1
Assert-Count @([pscustomobject]$highlight) @([pscustomobject]$highlight) 0
$strong = [pscustomobject]@{firstStack=40; icon='0 Orange Star'; actions=[pscustomobject]@{sound=4; fontSize=40}}
$twoStyles = $highlight.Clone()
$twoStyles.highlights = @($highlight.highlights[0], $strong)
Assert-Count @([pscustomobject]$highlight) @([pscustomobject]$twoStyles) 1
$reordered = $twoStyles.Clone()
$reordered.highlights = @($strong, $highlight.highlights[0])
Assert-Count @([pscustomobject]$twoStyles) @([pscustomobject]$reordered) 0
$equivalent = $twoStyles.Clone()
$equivalent.highlights = @($highlight.highlights[0], [pscustomobject]@{
    firstStack=40; icon='0 Orange Star'; actions=[pscustomobject]@{sound=4; volume=50; fontSize=40}
})
Assert-Count @([pscustomobject]$twoStyles) @([pscustomobject]$equivalent) 0
foreach ($style in @(
    @{firstStack=39; icon='0 Orange Star'; actions=$strong.actions}
    @{firstStack=40; icon='0 Red Circle'; actions=$strong.actions}
    @{firstStack=40; icon='0 Orange Star'; actions=[pscustomobject]@{sound=4; volume=0; fontSize=40}}
    @{firstStack=40; icon='0 Orange Star'; actions=[pscustomobject]@{sound=4; fontSize=45}}
)) {
    $different = $twoStyles.Clone()
    $different.highlights = @($highlight.highlights[0], [pscustomobject]$style)
    Assert-Count @([pscustomobject]$twoStyles) @([pscustomobject]$different) 1
}
$both = $twoStyles.Clone()
$both.cutoff = 2
Assert-Count @([pscustomobject]$highlight) @([pscustomobject]$both) 1
$unique = $highlight.Clone()
$unique.uniqueBase = $true
Assert-Count @([pscustomobject]$highlight) @([pscustomobject]$unique) 2

Write-Output 'Windows alerts count managed visibility and highlight changes once per rule and ignore quote-only updates.'

# Execute the Windows runner against an isolated profile. Capture the notification request
# before WinForms and replace only the native process with a deterministic profile update.
$workerScript = $worker.Groups['script'].Value
$start = $workerScript.IndexOf('$script:syncSettingsReadFailed = $false')
$notification = $workerScript.IndexOf('function Show-SyncNotification')
$run = $workerScript.IndexOf('$beforeProfiles = Read-SyncProfiles')
$end = $workerScript.LastIndexOf('exit $process.ExitCode')
$testScript = [scriptblock]::Create(
    $workerScript.Substring($start, $notification - $start) +
    $workerScript.Substring($run, $end - $run).Replace('exit 0', 'return 0').Replace('exit 1', 'return 1') +
    'return $process.ExitCode'
)
$exe = Join-Path $PSHOME 'powershell.exe'
$userPath = Join-Path ([IO.Path]::GetTempPath()) ('pob-notification-test-' + [guid]::NewGuid().ToString('N'))
$fixture = Join-Path $userPath 'LootFilterDailySync.json'
New-Item -ItemType Directory -Path $userPath | Out-Null
$script:emitted = [System.Collections.Generic.List[object]]::new()

function Start-Process {
    ConvertTo-Json -InputObject $script:nextProfile -Depth 12 | Set-Content -LiteralPath $fixture -Encoding UTF8
    return [pscustomobject]@{ExitCode=$script:nextExit}
}
function Show-SyncNotification([string]$message, [bool]$failed) {
    $script:emitted.Add([pscustomobject]@{message=$message; failed=$failed})
}
function Assert-Notification($before, $after, [int]$exitCode, [string]$expected) {
    ConvertTo-Json -InputObject $before -Depth 12 | Set-Content -LiteralPath $fixture -Encoding UTF8
    $script:nextProfile = $after
    $script:nextExit = $exitCode
    $script:emitted.Clear()
    $result = & $testScript
    if ($result -ne $exitCode) { throw "The notification path changed the worker's exit result" }
    if ($expected -eq 'none') {
        if ($script:emitted.Count) { throw 'Unexpected Windows notification' }
    } elseif ($script:emitted.Count -ne 1 -or $script:emitted[0].failed -ne ($expected -eq 'failure') -or
        ($expected -eq 'change' -and $script:emitted[0].message -notmatch '^5 managed loot rules changed')) {
        throw "Expected one $expected notification"
    }
}

try {
    $baseline = @{enabled=$true; backgroundEnabled=$true; backgroundNotifications=$true;
        current='before'; lastSuccess=100; revision='same'; review=@{protectedChecks=600; changes=@()}}
    $appearanceOnly = @(1..5 | ForEach-Object {
        [pscustomobject]@{name="Fixture $_"; old=6; cutoff=6; classes=@('Stackable Currency');
            highlights=@([pscustomobject]@{firstStack=20; icon='0 Red Star'})}
    })
    $changed = $baseline.Clone()
    $changed.current = 'after'
    $changed.lastSuccess = 200
    $changed.review = @{protectedChecks=600; changes=$appearanceOnly}
    Assert-Notification $baseline $changed 0 'change'
    $changed.review = @{protectedChecks=600; changes=$appearanceOnly[0..3]}
    Assert-Notification $baseline $changed 0 'none'
    $changed.review = @{protectedChecks=0; changes=$appearanceOnly}
    Assert-Notification $baseline $changed 0 'none'
    $changed.review.protectedChecks = 600
    $changed.backgroundNotifications = $false
    Assert-Notification $baseline $changed 0 'none'
    $failed = $baseline.Clone()
    $failed.lastFailure = @{message='The provider is temporarily unavailable'}
    Assert-Notification $baseline $failed 1 'failure'
    Assert-Notification $failed $failed 1 'none'
    Assert-Notification $baseline $failed 0 'none'
    Write-Output 'Windows runner requests alerts only for protected updates above the threshold or a new failure.'
} finally {
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture }
    Remove-Item -LiteralPath $userPath
}
