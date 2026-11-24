$ErrorActionPreference = 'Stop'

# Parse the command installed in Windows Task Scheduler and exercise its cutoff comparison.
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
        $node.Name -in 'Get-AdjustedCutoffs', 'Count-ChangedCutoffs'
}, $false)
if ($functions.Count -ne 2) { throw 'The Windows cutoff comparison functions are missing' }
. ([scriptblock]::Create(($functions.Extent.Text -join [Environment]::NewLine)))

function Assert-Count($before, $after, [int]$expected) {
    $observed = Count-ChangedCutoffs ([pscustomobject]@{changes=$before}) ([pscustomobject]@{changes=$after})
    if ($observed -ne $expected) { throw "Expected $expected changed managed cutoffs, received $observed" }
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
$highlight.highlights = @{firstStack=20}
Assert-Count @() @([pscustomobject]$highlight) 0
Assert-Count @([pscustomobject]$currency) @([pscustomobject]$highlight) 1

Write-Output 'Background cutoff notifications distinguish area, map, and gem variants and ignore unchanged highlights or quote evidence.'
