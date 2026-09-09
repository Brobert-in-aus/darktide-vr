# Execute only real launcher/preflight prefixes, before live setup. All selected
# packages, sync and settings effects belong to this process-owned fixture.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('darktidevr-installed-gate-' + [guid]::NewGuid().ToString('N'))
$fixtureRepo = Join-Path $fixture 'repository'
$fixtureGame = Join-Path $fixture 'game'
$relativeLua = 'mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua'
$relativeDescriptor = 'mods/darktidevr_stereo_probe/darktidevr_stereo_probe.mod'
$global:InstalledGateCompiler = Join-Path $repo 'tools/stereo/test-darktide-lua-source.ps1'
$global:InstalledGateFixtureSource = Join-Path $fixtureRepo $relativeLua
$global:InstalledGateFixtureCalls = [Collections.Generic.List[string]]::new()
$global:InstalledGateFixtureEffects = [Collections.Generic.List[string]]::new()
$global:InstalledGateFixtureBreakSync = $false
function Write-Fixture([string] $Path, [string] $Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text)
}
function Get-Process {
    [CmdletBinding()]param([string] $Name)
    if ($Name -ne 'Darktide') { throw 'Unexpected process query.' }
}
function Write-Prefix([string] $Relative, [string] $Boundary) {
    $text = [IO.File]::ReadAllText((Join-Path $repo $Relative))
    $end = $text.IndexOf($Boundary, [StringComparison]::Ordinal)
    if ($end -lt 0 -or $text.IndexOf($Boundary, $end + $Boundary.Length, [StringComparison]::Ordinal) -ge 0) {
        throw 'Live-boundary marker is missing or ambiguous.'
    }
    Write-Fixture (Join-Path $fixtureRepo $Relative) $text.Substring(0, $end)
}
Write-Prefix 'tools/stereo/start-darktide-vr.ps1' '$psykhaniumRequest = $null'
Write-Prefix 'tools/unattended/invoke-unattended-preflight.ps1' 'if (-not $OutputPath) {'
Write-Fixture (Join-Path $fixtureRepo 'tools/stereo/resolve-darktide-game-root.ps1') @'
function Resolve-DarktideGameRoot { param([string] $GameRoot) return $GameRoot }
'@
Write-Fixture (Join-Path $fixtureRepo 'tools/stereo/psykhanium-launch-request.ps1') '# No launch request in this prefix.'
Write-Fixture (Join-Path $fixtureRepo 'tools/stereo/run-darktide-shared-eyes.ps1') 'throw "XR runner must never execute"'
Write-Fixture (Join-Path $fixtureRepo 'tools/stereo/test-darktide-lua-source.ps1') @'
param([string] $SourcePath)
if (-not $SourcePath) { $SourcePath = $global:InstalledGateFixtureSource }
$global:InstalledGateFixtureCalls.Add([IO.Path]::GetFullPath($SourcePath))
& $global:InstalledGateCompiler -SourcePath $SourcePath
'@
Write-Fixture (Join-Path $fixtureRepo 'tools/stereo/set-vr-worker-threads.ps1') @'
param($Action)
$global:InstalledGateFixtureEffects.Add('tune')
'@
Write-Fixture (Join-Path $fixtureRepo 'tools/stereo/sync-darktide-vr-dev.ps1') @'
param($GameRoot,$Configuration,[switch]$UsePrebuiltProductionShader,[switch]$DiagnosticRenderHooks,[switch]$ClusterLightTrace,[bool]$ClusterLightVisibilityFix)
$global:InstalledGateFixtureEffects.Add('sync')
$value = if ($global:InstalledGateFixtureBreakSync) { 'local = invalid_sync' } else { 'return {}' }
[IO.File]::WriteAllText((Join-Path $GameRoot 'mods/darktidevr_stereo_probe/darktidevr_stereo_probe.mod'), $value)
'@
Write-Fixture $global:InstalledGateFixtureSource 'error("Source must only compile")'
Write-Fixture (Join-Path $fixtureRepo $relativeDescriptor) 'return {}'
Write-Fixture (Join-Path $fixtureGame $relativeLua) 'error("Installed Lua must only compile")'
$installedDescriptor = Join-Path $fixtureGame $relativeDescriptor
$launcher = Join-Path $fixtureRepo 'tools/stereo/start-darktide-vr.ps1'
$preflight = Join-Path $fixtureRepo 'tools/unattended/invoke-unattended-preflight.ps1'
function Invoke-Case([string] $Script, [hashtable] $Arguments, [bool] $Reject) {
    $global:InstalledGateFixtureCalls.Clear()
    $global:InstalledGateFixtureEffects.Clear()
    $failed = $false
    try { & $Script @Arguments 2>&1 | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch 'LuaJIT rejected|darktidevr_stereo_probe\.mod') { throw }
        $failed = $true
    }
    if ($failed -ne $Reject) { throw "Installed Lua gate outcome mismatch: expected rejection=$Reject" }
}
Write-Fixture $installedDescriptor 'local = invalid_installed_descriptor'
Invoke-Case $launcher @{GameRoot=$fixtureGame;SkipDeploymentSync=$true;TuneWorkerThreads=$true} $true
if ($global:InstalledGateFixtureEffects.Count) { throw 'Invalid installed package reached settings preparation.' }
Invoke-Case $preflight @{GameRoot=$fixtureGame;Mode='Ready'} $true
Invoke-Case $preflight @{GameRoot=$fixtureGame;Mode='Inventory'} $false
if ($global:InstalledGateFixtureCalls.Count -ne 1) { throw 'Inventory unexpectedly required installed Lua readiness.' }
Invoke-Case $launcher @{GameRoot=$fixtureGame;TuneWorkerThreads=$true} $false
if (($global:InstalledGateFixtureEffects -join ',') -ne 'sync,tune') { throw 'Sync/gate/settings ordering changed.' }
if ($global:InstalledGateFixtureCalls.Count -ne 2 -or
    $global:InstalledGateFixtureCalls[1] -ne [IO.Path]::GetFullPath((Join-Path $fixtureGame $relativeLua))) {
    throw 'Launcher did not validate the installed package after sync.'
}
$global:InstalledGateFixtureBreakSync = $true
Invoke-Case $launcher @{GameRoot=$fixtureGame;TuneWorkerThreads=$true} $true
if (($global:InstalledGateFixtureEffects -join ',') -ne 'sync') { throw 'Failed post-sync gate reached settings preparation.' }
Write-Fixture $installedDescriptor 'return {}'
Invoke-Case $launcher @{GameRoot=$fixtureGame;SkipDeploymentSync=$true} $false
Invoke-Case $preflight @{GameRoot=$fixtureGame;Mode='Ready'} $false
if ($global:InstalledGateFixtureCalls.Count -ne 2) { throw 'Ready did not check both source and installed packages.' }
Write-Output 'installed_lua_gates=pass skip_sync_and_post_sync=true ready=true inventory_observation_preserved=true live_setup_executed=false'
