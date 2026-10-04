param([string] $ScriptPath)
# The mode switch must tell this mod's proxy apart from a foreign d3d12.dll
# by a marker the proxy carries, not by being byte-identical to the copy in
# the mod folder: after a mod update the installed proxy is an earlier build
# of ours and must be replaced (VR) or removed (flat), never refused.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if (-not $ScriptPath) { $ScriptPath = Join-Path $repoRoot 'mods\darktidevr\darktidevr-mode.ps1' }

function Fail([string] $message) { Write-Error $message; exit 1 }

$root = Join-Path ([IO.Path]::GetTempPath()) ("darktidevr-mode-switch-" + [guid]::NewGuid().ToString('N'))
$profileRoot = Join-Path $root 'profile'
New-Item -ItemType Directory -Path (Join-Path $root 'game\binaries'), (Join-Path $root 'game\mods\dmf'),
    (Join-Path $root 'game\mods\darktidevr\bin'), (Join-Path $root 'game\mods\darktidevr\tools'), $profileRoot -Force | Out-Null
$game = Join-Path $root 'game'
$modRoot = Join-Path $game 'mods\darktidevr'
Copy-Item -LiteralPath $ScriptPath -Destination (Join-Path $modRoot 'darktidevr-mode.ps1')
# A fake executable: the patch tool reports it unsupported, which flat mode
# leaves alone and status reports; the proxy logic is what is under test.
[IO.File]::WriteAllBytes((Join-Path $game 'binaries\Darktide.exe'), [byte[]](1..64))
Set-Content -LiteralPath (Join-Path $modRoot 'tools\set-skinner-assert-patch.ps1') -Value 'param($Action,$GameExe) Write-Output "state=unsupported"' -Encoding ascii
Set-Content -LiteralPath (Join-Path $game 'mods\mod_load_order.txt') -Value "dmf`r`ndarktidevr`r`n" -Encoding ascii
# The mod's current proxy carries the marker as a wide string, like the real
# bootstrap does with its log and bin paths.
$marker = [Text.Encoding]::Unicode.GetBytes('..\mods\darktidevr\bin\')
$current = [byte[]](0x4D, 0x5A) + [byte[]](1..32) + $marker + [byte[]](7, 7, 7)
$earlier = [byte[]](0x4D, 0x5A) + [byte[]](33..64) + $marker + [byte[]](9, 9)
$foreign = [byte[]](0x4D, 0x5A) + [byte[]](1..128)
[IO.File]::WriteAllBytes((Join-Path $modRoot 'bin\d3d12.dll'), $current)
[IO.File]::WriteAllBytes((Join-Path $modRoot 'bin\darktidevr_native_capture.dll'), $current)
[IO.File]::WriteAllBytes((Join-Path $modRoot 'bin\darktidevr-xr-harness.exe'), $current)
$proxy = Join-Path $game 'binaries\d3d12.dll'

# Keep the test's settings profile away from the real one.
$env:APPDATA = Join-Path $profileRoot 'roaming'
$env:LOCALAPPDATA = Join-Path $profileRoot 'local'
New-Item -ItemType Directory -Path (Join-Path $env:APPDATA 'Fatshark\Darktide'), $env:LOCALAPPDATA -Force | Out-Null

function Invoke-Switch([string] $mode) {
    # The switch reports refusals on stderr with a non-zero exit; under Stop
    # those would terminate this script before the exit code is inspected.
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $modRoot 'darktidevr-mode.ps1') -Mode $mode -GameRoot $game 2>&1 | ForEach-Object { "$_" }
        return @{ exit = $LASTEXITCODE; lines = $lines }
    } finally {
        $ErrorActionPreference = 'Stop'
    }
}
function Proxy-State($result) { return ($result.lines | Where-Object { $_ -like 'd3d12_proxy=*' } | Select-Object -Last 1) -replace '^d3d12_proxy=', '' }

try {
    $status = Invoke-Switch 'status'
    if ((Proxy-State $status) -ne 'absent') { Fail "Expected absent proxy, got: $($status.lines -join ' | ')" }

    [IO.File]::WriteAllBytes($proxy, $current)
    if ((Proxy-State (Invoke-Switch 'status')) -ne 'installed') { Fail 'Byte-identical proxy was not reported installed' }

    [IO.File]::WriteAllBytes($proxy, $earlier)
    if ((Proxy-State (Invoke-Switch 'status')) -ne 'outdated') { Fail 'An earlier build of our proxy was not reported outdated' }

    [IO.File]::WriteAllBytes($proxy, $foreign)
    if ((Proxy-State (Invoke-Switch 'status')) -ne 'foreign') { Fail 'A d3d12.dll without the marker was not reported foreign' }

    # Flat mode removes an earlier build of ours and leaves a foreign one.
    $flat = Invoke-Switch 'flat'
    if ($flat.exit -ne 0 -or -not (Test-Path -LiteralPath $proxy)) { Fail "Flat mode removed a foreign proxy or failed: $($flat.lines -join ' | ')" }
    [IO.File]::WriteAllBytes($proxy, $earlier)
    $flat = Invoke-Switch 'flat'
    if ($flat.exit -ne 0 -or (Test-Path -LiteralPath $proxy)) { Fail "Flat mode did not remove the earlier proxy: $($flat.lines -join ' | ')" }
    if (-not ($flat.lines -match 'earlier version')) { Fail 'Flat mode did not say it removed an earlier version' }

    # VR mode refuses a foreign proxy but replaces an earlier build of ours,
    # even though this fixture executable is unsupported (it stops there).
    [IO.File]::WriteAllBytes($proxy, $foreign)
    $vr = Invoke-Switch 'vr'
    if ($vr.exit -eq 0) { Fail 'VR mode accepted an unsupported executable' }
    if (-not ($vr.lines -match 'not supported')) { Fail "Unexpected VR failure: $($vr.lines -join ' | ')" }
    if (-not ([IO.File]::ReadAllBytes($proxy).Length -eq $foreign.Length)) { Fail 'VR mode touched a foreign proxy' }

    # Restoring settings: refused without a backup; otherwise the newest backup
    # replaces the file and the replaced file is kept.
    $settings = Join-Path $env:APPDATA 'Fatshark\Darktide\user_settings.config'
    Set-Content -LiteralPath $settings -Value 'reset to defaults' -Encoding ascii
    $none = Invoke-Switch 'restore-settings'
    if ($none.exit -eq 0 -or -not ($none.lines -match 'No settings backup')) { Fail "Restore without a backup: $($none.lines -join ' | ')" }
    $backups = Join-Path $env:LOCALAPPDATA 'DarktideVR\settings-backups'
    New-Item -ItemType Directory -Path $backups -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $backups 'user_settings.20260914-070000.config') -Value 'older' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $backups 'user_settings.20260915-080000.config') -Value 'newest' -Encoding ascii
    $restore = Invoke-Switch 'restore-settings'
    if ($restore.exit -ne 0) { Fail "Restore failed: $($restore.lines -join ' | ')" }
    if ((Get-Content -LiteralPath $settings -Raw).Trim() -ne 'newest') { Fail 'Restore did not use the newest backup' }
    $kept = Get-ChildItem -LiteralPath $backups -Filter 'user_settings.before-restore-*.config'
    if (-not $kept -or (Get-Content -LiteralPath $kept[0].FullName -Raw).Trim() -ne 'reset to defaults') { Fail 'The replaced settings file was not kept' }
    if (-not ($restore.lines -match '^settings_backup=user_settings.20260915-080000.config$')) { Fail 'Status did not name the newest backup' }

    # A game update: the patch tool refuses the executable on stderr and exits
    # non-zero (the shipped tool before 5 October 2026 threw "Unexpected
    # byte"). Every mode must still run -- above all flat, the way out.
    $toolPath = Join-Path $modRoot 'tools\set-skinner-assert-patch.ps1'
    Set-Content -LiteralPath $toolPath -Value 'param($Action,$GameExe) throw "Unexpected byte 0x38 at file offset 0x7a7586"' -Encoding ascii
    Remove-Item -LiteralPath $proxy -Force -ErrorAction SilentlyContinue
    $status = Invoke-Switch 'status'
    if ($status.exit -ne 0 -or -not ($status.lines -match '^executable=unsupported$')) { Fail "Status on a refused executable: $($status.lines -join ' | ')" }
    $vr = Invoke-Switch 'vr'
    if ($vr.exit -eq 0 -or -not ($vr.lines -match 'not supported yet')) { Fail "VR on a refused executable: $($vr.lines -join ' | ')" }

    # Flat with this mod the only load-order line, and a damaged settings file
    # while the VR profile is the current one: the saved VR profile survives.
    $loadOrder = Join-Path $game 'mods\mod_load_order.txt'
    Set-Content -LiteralPath $loadOrder -Value 'darktidevr' -Encoding ascii
    $profileDirectory = Join-Path $env:LOCALAPPDATA 'DarktideVR'
    $sound = 'mods_settings = { ' + ('x' * 4000) + ' }'
    Set-Content -LiteralPath (Join-Path $profileDirectory 'settings-profile.txt') -Value 'vr' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $profileDirectory 'user_settings.vr.config') -Value $sound -Encoding ascii
    Set-Content -LiteralPath (Join-Path $profileDirectory 'user_settings.flat.config') -Value ($sound + ' flat') -Encoding ascii
    Set-Content -LiteralPath $settings -Value 'reset to defaults' -Encoding ascii
    $flat = Invoke-Switch 'flat'
    if ($flat.exit -ne 0) { Fail "Flat on a refused executable failed: $($flat.lines -join ' | ')" }
    if (@(Get-Content -LiteralPath $loadOrder | Where-Object { $_.Trim() -eq 'darktidevr' }).Count -ne 0) { Fail 'Flat left the load-order line' }
    if ((Get-Content -LiteralPath (Join-Path $profileDirectory 'user_settings.vr.config') -Raw).Trim() -ne $sound) { Fail 'A damaged settings file replaced the saved VR profile' }
    if (-not ($flat.lines -match 'looks damaged or reset')) { Fail 'Flat did not report the damaged settings file' }
    if ((Get-Content -LiteralPath $settings -Raw).Trim() -ne ($sound + ' flat')) { Fail 'Flat did not restore the flat profile' }
    if (-not ($flat.lines -match '^settings_profile=flat$')) { Fail 'The profile marker did not move to flat' }

    # The shipped patch tool itself: an unknown executable is reported, not
    # thrown, so the switch does not depend on how stderr is handled.
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\stereo\set-skinner-assert-patch.ps1') -Destination $toolPath -Force
    $env:LOCALAPPDATA = Join-Path $profileRoot 'local'
    $ErrorActionPreference = 'Continue'
    $inspect = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $toolPath -Action Inspect -GameExe (Join-Path $game 'binaries\Darktide.exe') 2>&1 | ForEach-Object { "$_" })
    $inspectExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($inspectExit -ne 0 -or -not ($inspect -contains 'state=unsupported')) { Fail "Patch tool on an unknown executable: exit=$inspectExit $($inspect -join ' | ')" }
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'mode_switch=pass proxy_states=absent,installed,outdated,foreign restore_settings refused_executable damaged_settings'
