[CmdletBinding()]
param(
    # vr: patch the executable, install the d3d12 proxy, add the mod to the
    # load order. flat: restore the original executable, remove the proxy,
    # remove the load-order line. status: report without changing anything.
    # restore-settings: put back the newest settings backup the mod took at a
    # sound launch (after a crash destroyed user_settings.config).
    [ValidateSet('vr', 'flat', 'status', 'restore-settings')]
    [string] $Mode = 'status',

    # Defaults to the game folder two levels above this script.
    [string] $GameRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modName = 'darktidevr'
$modRoot = $PSScriptRoot
if (-not $GameRoot) {
    $GameRoot = Split-Path -Parent (Split-Path -Parent $modRoot)
}
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$gameExe = Join-Path $GameRoot 'binaries\Darktide.exe'
$proxyDestination = Join-Path $GameRoot 'binaries\d3d12.dll'
$proxySource = Join-Path $modRoot 'bin\d3d12.dll'
$loadOrderPath = Join-Path $GameRoot 'mods\mod_load_order.txt'
$viewerPath = Join-Path $modRoot 'bin\darktidevr-xr-harness.exe'
$nativePath = Join-Path $modRoot 'bin\darktidevr_native_capture.dll'

# The patch tool ships inside the mod; a repository checkout keeps it under
# tools\stereo instead.
$patchTool = Join-Path $modRoot 'tools\set-skinner-assert-patch.ps1'
if (-not (Test-Path -LiteralPath $patchTool -PathType Leaf)) {
    $patchTool = Join-Path (Split-Path -Parent (Split-Path -Parent $modRoot)) 'tools\stereo\set-skinner-assert-patch.ps1'
}

# Separate settings per mode: the game keeps video, audio, input bindings and
# the rest in one file, so the switch keeps one copy per mode and swaps them.
# The first switch into a mode starts that mode's copy from the current file.
# The Microsoft Store / Game Pass build keeps them under
# Fatshark\MicrosoftStore\Darktide; its game folder is a GDK package, which
# carries MicrosoftGame.config beside binaries.
$storeBuild = Test-Path -LiteralPath (Join-Path $GameRoot 'MicrosoftGame.config') -PathType Leaf
$settingsDirectory = if ($storeBuild) { Join-Path $env:APPDATA 'Fatshark\MicrosoftStore\Darktide' } else { Join-Path $env:APPDATA 'Fatshark\Darktide' }
$settingsPath = Join-Path $settingsDirectory 'user_settings.config'
$profileDirectory = Join-Path $env:LOCALAPPDATA 'DarktideVR'
$profileMarker = Join-Path $profileDirectory 'settings-profile.txt'
# The mod copies a sound settings file here at each launch (newest by name).
$backupDirectory = Join-Path $profileDirectory 'settings-backups'

function Get-NewestSettingsBackup {
    if (-not (Test-Path -LiteralPath $backupDirectory -PathType Container)) { return $null }
    return Get-ChildItem -LiteralPath $backupDirectory -File -Filter 'user_settings.2*.config' |
        Sort-Object Name -Descending | Select-Object -First 1
}

function Get-SettingsProfile {
    if (Test-Path -LiteralPath $profileMarker -PathType Leaf) {
        $value = (Get-Content -LiteralPath $profileMarker -Raw).Trim()
        if ($value -in @('vr', 'flat')) { return $value }
    }
    return 'flat'
}

# A crash while the game writes user_settings.config leaves it truncated or
# zero-filled, and the game then rewrites it from defaults. Such a file must
# never replace a saved profile: the saved copy is what the player restores
# from. The same tests as the mod's own launch backup (settings_backup.cpp),
# with the shrink measured against the copy it would replace.
function Test-SettingsSound([string] $Path, [string] $Against) {
    try { $bytes = [IO.File]::ReadAllBytes($Path) } catch { return $false }
    if ($bytes.Length -lt 2048 -or [Array]::IndexOf($bytes, [byte] 0) -ge 0) { return $false }
    if ([Text.Encoding]::ASCII.GetString($bytes).IndexOf('mods_settings', [StringComparison]::Ordinal) -lt 0) { return $false }
    if ($Against -and (Test-Path -LiteralPath $Against -PathType Leaf)) {
        if ($bytes.Length -lt (Get-Item -LiteralPath $Against).Length * 0.7) { return $false }
    }
    return $true
}

# Written beside the destination and renamed over it, so an interruption
# leaves either the old file or the new one, never part of one.
function Copy-FileWhole([string] $Source, [string] $Destination) {
    $partial = "$Destination.partial"
    Copy-Item -LiteralPath $Source -Destination $partial -Force
    Move-Item -LiteralPath $partial -Destination $Destination -Force
}

function Switch-SettingsProfile([string] $Target) {
    $current = Get-SettingsProfile
    if ($current -eq $Target) {
        Write-Output "Settings: already the $Target profile."
        return
    }
    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        Write-Output "Settings: no user_settings.config yet; nothing to swap."
        return
    }
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
    $savedCurrent = Join-Path $profileDirectory "user_settings.$current.config"
    $savedTarget = Join-Path $profileDirectory "user_settings.$Target.config"
    $saved = Test-SettingsSound $settingsPath $savedCurrent
    if ($saved) {
        Copy-FileWhole $settingsPath $savedCurrent
    } else {
        Write-Output "Settings: the current user_settings.config looks damaged or reset (too small, or much smaller than the saved $current profile); the saved $current profile is kept as it was."
    }
    # The marker goes first: if the swap below is interrupted, the next switch
    # must not save this mode's file under the other mode's name.
    Set-Content -LiteralPath $profileMarker -Value $Target -Encoding ascii
    if (Test-Path -LiteralPath $savedTarget -PathType Leaf) {
        Copy-FileWhole $savedTarget $settingsPath
        Write-Output "Settings: $(if ($saved) { "$current profile saved, " })$Target profile restored."
    } elseif ($saved) {
        Write-Output "Settings: $current profile saved; the $Target profile starts from the current settings."
    }
}

function Get-FileSha256([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ExeState {
    if (-not (Test-Path -LiteralPath $patchTool -PathType Leaf)) { return 'patch-tool-missing' }
    # The tool's refusals arrive on stderr. Under 'Stop' a redirected stderr
    # line from a native command is a terminating error here, which made every
    # mode -- flat included -- abort on a game build the tool did not know.
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patchTool -Action Inspect -GameExe $gameExe 2>$null)
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    $state = ($lines | Where-Object { "$_" -like 'state=*' } | Select-Object -First 1)
    if (-not $state) {
        # Unknown hash or an unexpected byte: the tool refuses this build.
        return 'unsupported'
    }
    return ("$state" -replace '^state=', '')
}

function Get-LoadOrderState {
    if (-not (Test-Path -LiteralPath $loadOrderPath -PathType Leaf)) { return 'missing' }
    $listed = Get-Content -LiteralPath $loadOrderPath | Where-Object { $_.Trim() -eq $modName }
    if ($listed) { return 'listed' }
    return 'absent'
}

# This mod's proxies carry the mod's name in their embedded paths (as wide
# strings). An installed d3d12.dll with that marker but different bytes is an
# earlier build of ours, left by a previous version: replace or remove it.
# One without the marker belongs to something else and is never touched.
function Test-ProxyMarker([string] $Path) {
    try { $bytes = [IO.File]::ReadAllBytes($Path) } catch { return $false }
    foreach ($encoding in @([Text.Encoding]::Unicode, [Text.Encoding]::ASCII)) {
        $text = $encoding.GetString($bytes)
        if ($text.IndexOf('darktidevr', [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Get-ProxyState {
    $installed = Get-FileSha256 $proxyDestination
    if (-not $installed) { return 'absent' }
    $ours = Get-FileSha256 $proxySource
    if ($ours -and $installed -eq $ours) { return 'installed' }
    if (Test-ProxyMarker $proxyDestination) { return 'outdated' }
    return 'foreign'
}

function Write-Status {
    Write-Output "game=$GameRoot"
    Write-Output "store=$(if ($storeBuild) { 'microsoft' } else { 'steam' })"
    Write-Output "executable=$(Get-ExeState)"
    Write-Output "d3d12_proxy=$(Get-ProxyState)"
    Write-Output "load_order=$(Get-LoadOrderState)"
    Write-Output "viewer=$(if (Test-Path -LiteralPath $viewerPath -PathType Leaf) { 'present' } else { 'missing' })"
    Write-Output "native=$(if (Test-Path -LiteralPath $nativePath -PathType Leaf) { 'present' } else { 'missing' })"
    Write-Output "dmf=$(if (Test-Path -LiteralPath (Join-Path $GameRoot 'mods\dmf') -PathType Container) { 'present' } else { 'missing' })"
    Write-Output "settings_profile=$(Get-SettingsProfile)"
    $backup = Get-NewestSettingsBackup
    Write-Output "settings_backup=$(if ($backup) { $backup.Name } else { 'none' })"
}

if (-not (Test-Path -LiteralPath $gameExe -PathType Leaf)) {
    throw "Darktide executable not found: $gameExe (run this from mods\$modName inside the game folder, or pass -GameRoot)"
}
if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Close Darktide before switching modes.'
}

if ($Mode -eq 'status') {
    Write-Status
    exit 0
}

if ($Mode -eq 'restore-settings') {
    $backup = Get-NewestSettingsBackup
    if (-not $backup) {
        throw 'No settings backup yet: the mod takes one each time Darktide starts with sound settings.'
    }
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $kept = Join-Path $backupDirectory "user_settings.before-restore-$stamp.config"
        Copy-Item -LiteralPath $settingsPath -Destination $kept -Force
        Write-Output "Settings: the current file is kept as $kept."
    }
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    Copy-FileWhole $backup.FullName $settingsPath
    Write-Output "Settings: restored from $($backup.Name)."
    Write-Status
    exit 0
}

if ($Mode -eq 'vr') {
    foreach ($required in @($proxySource, $nativePath, $viewerPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Mod file missing: $required. Reinstall the mod folder."
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'mods\dmf') -PathType Container)) {
        throw 'The Darktide Mod Framework is not installed (mods\dmf). Install the Darktide Mod Loader and Framework first.'
    }
    $exeState = Get-ExeState
    switch ($exeState) {
        'patched' { Write-Output 'Executable: already patched.' }
        'original' {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patchTool -Action Apply -GameExe $gameExe
            if ($LASTEXITCODE -ne 0) { throw 'The executable patch failed.' }
            Write-Output 'Executable: patched (pristine copy kept under %LOCALAPPDATA%\DarktideVR).'
        }
        'patch-tool-missing' { throw "Patch tool not found: $patchTool" }
        default {
            throw 'This Darktide build is not supported yet: its executable hash is unknown to the patch tool. Wait for a mod update.'
        }
    }
    $proxyState = Get-ProxyState
    if ($proxyState -eq 'foreign') {
        throw "binaries\d3d12.dll exists and is not this mod's proxy. Remove or rename it first."
    }
    if ($proxyState -eq 'outdated') {
        Copy-Item -LiteralPath $proxySource -Destination $proxyDestination -Force
        Write-Output 'd3d12 proxy: updated from an earlier version.'
    } elseif ($proxyState -ne 'installed') {
        Copy-Item -LiteralPath $proxySource -Destination $proxyDestination -Force
        Write-Output 'd3d12 proxy: installed.'
    } else {
        Write-Output 'd3d12 proxy: already installed.'
    }
    if ((Get-LoadOrderState) -eq 'listed') {
        Write-Output 'Load order: already listed.'
    } else {
        if (-not (Test-Path -LiteralPath $loadOrderPath -PathType Leaf)) {
            throw "mods\mod_load_order.txt not found. Install the Darktide Mod Loader first."
        }
        $content = [IO.File]::ReadAllText($loadOrderPath)
        if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) { $content += "`r`n" }
        [IO.File]::WriteAllText($loadOrderPath, $content + $modName + "`r`n")
        Write-Output 'Load order: added.'
    }
    Switch-SettingsProfile 'vr'
    Write-Output "VR mode is on. Launch Darktide as usual$(if ($storeBuild) { ' from the Xbox app' } else { ' through Steam' })."
    Write-Status
    exit 0
}

# flat
$exeState = Get-ExeState
if ($exeState -eq 'patched') {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $patchTool -Action Restore -GameExe $gameExe
    if ($LASTEXITCODE -ne 0) { throw 'Restoring the original executable failed.' }
    Write-Output 'Executable: original restored.'
} else {
    Write-Output "Executable: $exeState (left as is)."
}
switch (Get-ProxyState) {
    'installed' { Remove-Item -LiteralPath $proxyDestination -Force; Write-Output 'd3d12 proxy: removed.' }
    'outdated' { Remove-Item -LiteralPath $proxyDestination -Force; Write-Output 'd3d12 proxy: removed (earlier version).' }
    'absent' { Write-Output 'd3d12 proxy: not installed.' }
    default { Write-Output 'd3d12 proxy: a different d3d12.dll is present; left as is.' }
}
if ((Get-LoadOrderState) -eq 'listed') {
    # @(): with this mod the only line, the filter yields nothing and a null
    # array made WriteAllLines throw after the executable was already restored.
    $kept = @([IO.File]::ReadAllLines($loadOrderPath) | Where-Object { $_.Trim() -ne $modName })
    [IO.File]::WriteAllLines($loadOrderPath, [string[]] $kept)
    Write-Output 'Load order: removed.'
} else {
    Write-Output 'Load order: not listed.'
}
Switch-SettingsProfile 'flat'
Write-Output 'Flat mode is on. Other mods and the mod folder are untouched.'
Write-Status
