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
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'mode_switch=pass proxy_states=absent,installed,outdated,foreign'
