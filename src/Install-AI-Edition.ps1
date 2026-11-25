param(
    [string]$Destination,
    [string]$ShortcutDirectory = [Environment]::GetFolderPath('Programs')
)
$ErrorActionPreference = 'Stop'
$source = $PSScriptRoot
[xml]$manifest = Get-Content -LiteralPath (Join-Path $source 'manifest.xml') -Raw
$version = $manifest.PoBVersion.Version
if ($version.platform -ne 'win32' -or $version.branch -notin @('dev','main')) { throw 'This is not a verified Windows package.' }
$info = Get-Content -LiteralPath (Join-Path $source 'PACKAGE-INFO.txt') -Raw
if ($info -notmatch '(?m)^Commit: ([a-f0-9]{40})\r?$') { throw 'Package commit is missing.' }
$commit = $Matches[1]
if (-not $Destination) { $Destination = Join-Path $env:LOCALAPPDATA ("Programs\Path of Building AI Edition\" + $commit) }
$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$sourcePath = [IO.Path]::GetFullPath($source).TrimEnd('\')
if ($destinationPath.StartsWith($sourcePath + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $sourcePath.StartsWith($destinationPath + '\', [StringComparison]::OrdinalIgnoreCase) -or
    $destinationPath -eq $sourcePath -or (Test-Path -LiteralPath $destinationPath)) {
    throw 'Choose a new installation directory outside the extracted package.'
}
$entries = @{}
foreach ($file in $manifest.PoBVersion.File) {
    if ($file.platform -and $file.platform -ne 'win32') { continue }
    $name = $file.name.Replace('{space}',' ')
    if ([IO.Path]::IsPathRooted($name) -or $name -match '(^|[/\\])\.\.?([/\\]|$)' -or $name -match '[:*?"<>|]') { throw 'Unsafe package path.' }
    $key = $name.ToLowerInvariant()
    if ($entries.ContainsKey($key)) { throw 'Duplicate package path.' }
    $path = Join-Path $source $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA1).Hash -ine $file.sha1) { throw "Package verification failed: $name" }
    $entries[$key] = $name
}
foreach ($required in @('path of building.exe','launch.lua','assets/ai-edition.ico')) {
    if (-not $entries.ContainsKey($required)) { throw "Package is missing $required" }
}
New-Item -ItemType Directory -Path $destinationPath | Out-Null
foreach ($name in $entries.Values) {
    $target = Join-Path $destinationPath $name
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source $name) -Destination $target
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA1).Hash -ine (Get-FileHash -LiteralPath (Join-Path $source $name) -Algorithm SHA1).Hash) { throw "Install verification failed: $name" }
}
foreach ($name in @('manifest.xml','PACKAGE-INFO.txt','Launch.cfg')) { Copy-Item -LiteralPath (Join-Path $source $name) -Destination (Join-Path $destinationPath $name) }
New-Item -ItemType File -Path (Join-Path $destinationPath 'installed.cfg') | Out-Null
New-Item -ItemType Directory -Path $ShortcutDirectory -Force | Out-Null
$shortcutPath = Join-Path $ShortcutDirectory 'Path of Building AI Edition.lnk'
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $destinationPath 'Path of Building.exe'
$shortcut.WorkingDirectory = $destinationPath
$shortcut.IconLocation = (Join-Path $destinationPath 'Assets\AI-Edition.ico') + ',0'
$shortcut.Description = 'Path of Building AI Edition'
$shortcut.Save()
$check = $shell.CreateShortcut($shortcutPath)
if ($check.TargetPath -ne $shortcut.TargetPath -or $check.IconLocation -ne $shortcut.IconLocation) { throw 'Shortcut verification failed.' }
Write-Output "Installed Path of Building AI Edition at $destinationPath"
