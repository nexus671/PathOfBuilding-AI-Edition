$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('pob-ai-install-test-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $root 'package'
$destination = Join-Path $root 'installed'
$shortcuts = Join-Path $root 'shortcuts'
New-Item -ItemType Directory -Path (Join-Path $source 'Assets') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\src\Install-AI-Edition.ps1') -Destination $source
Set-Content -LiteralPath (Join-Path $source 'Path of Building.exe') -Value 'launcher' -NoNewline
Set-Content -LiteralPath (Join-Path $source 'Launch.lua') -Value 'program' -NoNewline
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\src\Assets\AI-Edition.ico') -Destination (Join-Path $source 'Assets\AI-Edition.ico')
$entries = foreach ($name in @('Path of Building.exe','Launch.lua','Assets/AI-Edition.ico')) {
    $digest = (Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA1).Hash.ToLowerInvariant()
    '<File part="program" name="' + $name.Replace(' ','{space}') + '" sha1="' + $digest + '" />'
}
Set-Content -LiteralPath (Join-Path $source 'manifest.xml') -Value ('<PoBVersion><Version number="test" platform="win32" branch="dev" />' + ($entries -join '') + '</PoBVersion>')
Set-Content -LiteralPath (Join-Path $source 'PACKAGE-INFO.txt') -Value ('Commit: ' + ('a' * 40))
Set-Content -LiteralPath (Join-Path $source 'Launch.cfg') -Value ''
$installer = Join-Path $source 'Install-AI-Edition.ps1'
& $installer -Destination $destination -ShortcutDirectory $shortcuts
if (-not (Test-Path -LiteralPath (Join-Path $destination 'installed.cfg'))) { throw 'Installed mode marker missing.' }
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $shortcuts 'Path of Building AI Edition.lnk'))
if ($shortcut.TargetPath -ne (Join-Path $destination 'Path of Building.exe') -or $shortcut.IconLocation -notmatch 'AI-Edition\.ico') { throw 'Wrong installed shortcut.' }
$rejected = $false
try { & $installer -Destination $destination -ShortcutDirectory $shortcuts } catch { $rejected = $true }
if (-not $rejected) { throw 'Existing installations must not be overwritten.' }
Set-Content -LiteralPath (Join-Path $source 'Launch.lua') -Value 'tampered' -NoNewline
$rejected = $false
try { & $installer -Destination (Join-Path $root 'tampered') -ShortcutDirectory $shortcuts } catch { $rejected = $true }
if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $root 'tampered'))) { throw 'Tampered packages must be rejected before installation.' }
Write-Output 'Installer verifies payload, installed mode, shortcut and overwrite protection.'
