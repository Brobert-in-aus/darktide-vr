# Exercise the real sync orchestration only inside a process-owned fake repo/game.
# Process discovery and Lua compilation are fixtures; real Lua has its own gate.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ('darktidevr-sync-test-' + [Guid]::NewGuid().ToString('N'))
$repo = Join-Path $testRoot 'repository'
$game = Join-Path $testRoot 'game'
$tools = Join-Path $repo 'tools\stereo'
$modRelative = 'mods\darktidevr_stereo_probe'
$luaRelative = $modRelative + '\scripts\mods\darktidevr_stereo_probe'
$lock = $null
$global:DeploymentFixtureGateFailure = $false
function Get-Process {
    [CmdletBinding()]param([string] $Name)
    if ($Name -ne 'Darktide') { throw 'Unexpected process query in sync fixture.' }
}
function Write-Fixture([string] $Path, [string] $Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text)
}
function Get-InstallationSnapshot {
    $snapshot = @{}
    Get-ChildItem -LiteralPath $game -Recurse -File | ForEach-Object {
        $snapshot[$_.FullName.Substring($game.Length)] = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }
    return $snapshot
}
function Assert-Unchanged([hashtable] $Before) {
    $after = Get-InstallationSnapshot
    if ($after.Count -ne $Before.Count) { throw 'Installed file set changed after rejected sync.' }
    foreach ($key in $Before.Keys) {
        if ($after[$key] -ne $Before[$key]) { throw "Installed bytes changed after rejected sync: $key" }
    }
}
try {
    [IO.Directory]::CreateDirectory($tools) | Out-Null
    foreach ($name in @('sync-darktide-vr-dev.ps1', 'resolve-darktide-game-root.ps1', 'invoke-deployment-transaction.ps1', 'get-vr-mod-load-order.ps1', 'production-billboard-shader.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot ('..\..\tools\stereo\' + $name)) -Destination (Join-Path $tools $name)
    }
    Write-Fixture (Join-Path $tools 'test-darktide-lua-source.ps1') @'
param([string] $SourcePath)
if (-not (Test-Path -LiteralPath $SourcePath)) { throw 'Missing fixture source.' }
if ($global:DeploymentFixtureGateFailure) { throw 'fixture syntax gate failed' }
'@
    foreach ($name in @('darktidevr_stereo_probe.lua', 'module.lua')) {
        Write-Fixture (Join-Path $repo ($luaRelative + '\' + $name)) ('new-' + $name)
        Write-Fixture (Join-Path $game ($luaRelative + '\' + $name)) ('old-' + $name)
    }
    Write-Fixture (Join-Path $repo ($modRelative + '\darktidevr_stereo_probe.mod')) 'new-descriptor'
    Write-Fixture (Join-Path $game ($modRelative + '\darktidevr_stereo_probe.mod')) 'old-descriptor'
    foreach ($name in @('darktidevr_native_capture.dll', 'd3d12.dll')) {
        Write-Fixture (Join-Path $repo ('build\windows-vs2022\src\producer\Release\' + $name)) ('new-' + $name)
        Write-Fixture (Join-Path $game ('binaries\' + $name)) ('old-' + $name)
    }
    Write-Fixture (Join-Path $game 'binaries\Darktide.exe') 'fixture-only-not-executable'
    Write-Fixture (Join-Path $game ($modRelative + '\bin\darktidevr_native_capture.dll')) 'old-mod-native'
    $diagnostic = Join-Path $game ($modRelative + '\bin\billboard_shaders\ps-6020f2548f29fd47.dxil')
    Write-Fixture $diagnostic 'old-magenta-diagnostic'
    $lastFlag = Join-Path $game ($modRelative + '\darktidevr_weapon_presentation.flag')
    Write-Fixture $lastFlag 'original-flag'
    $before = Get-InstallationSnapshot
    $sync = Join-Path $tools 'sync-darktide-vr-dev.ps1'
    $lock = [IO.File]::Open($lastFlag, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $failed = $false
    try { & $sync -GameRoot $game -BillboardShaderSubstitution:$false | Out-Null }
    catch { $failed = $_.Exception.Message.Contains('Status=rolled_back') }
    $lock.Dispose(); $lock = $null
    if (-not $failed) { throw 'Late sync failure did not roll back.' }
    Assert-Unchanged $before
    & $sync -GameRoot $game -BillboardShaderSubstitution:$false | Out-Null
    if ([IO.File]::ReadAllText((Join-Path $game ($luaRelative + '\module.lua'))) -ne 'new-module.lua') { throw 'Module was not deployed.' }
    if ([IO.File]::ReadAllText((Join-Path $game ($modRelative + '\bin\darktidevr_native_capture.dll'))) -ne 'new-darktidevr_native_capture.dll') { throw 'Native module was not deployed.' }
    if (Test-Path -LiteralPath $diagnostic) { throw 'Stale magenta shader survived successful sync.' }
    foreach ($pair in @(@('darktidevr_gameplay_input_test.flag', 'enabled'), @('darktidevr_controller_aim_test.flag', 'enabled'),
            @('darktidevr_full_body_experimental.flag', 'disabled'), @('darktidevr_weapon_presentation.flag', 'disabled'))) {
        $path = Join-Path $game ($modRelative + '\' + $pair[0])
        if ([IO.File]::ReadAllText($path) -cne ($pair[1] + [Environment]::NewLine)) { throw "Runtime flag disagrees: $path" }
    }
    $before = Get-InstallationSnapshot
    $global:DeploymentFixtureGateFailure = $true
    $failed = $false
    try { & $sync -GameRoot $game -BillboardShaderSubstitution:$false | Out-Null }
    catch { $failed = $_.Exception.Message.Contains('fixture syntax gate failed') }
    if (-not $failed) { throw 'Sync bypassed the Lua gate.' }
    Assert-Unchanged $before
    $global:DeploymentFixtureGateFailure = $false
    # A separate fixture has a loader/framework but no VR directories.
    $game = Join-Path $testRoot 'clean-game'
    foreach ($required in @('binaries\Darktide.exe', 'binaries\mod_loader', 'mods\base\mod_manager.lua', 'mods\dmf\dmf.mod')) {
        Write-Fixture (Join-Path $game $required) 'fixture-dependency'
    }
    $orderPath = Join-Path $game 'mods\mod_load_order.txt'
    Write-Fixture $orderPath "-- Existing user list`ncustom_hud"
    $before = Get-InstallationSnapshot
    $failed = $false
    try { & $sync -GameRoot $game -BillboardShaderSubstitution:$false | Out-Null }
    catch { $failed = $_.Exception.Message.Contains('Installed Darktide VR directory not found') }
    if (-not $failed) { throw 'Ordinary sync unexpectedly initialized a new installation.' }
    Assert-Unchanged $before
    $framework = Join-Path $game 'mods\dmf\dmf.mod'
    Remove-Item -LiteralPath $framework
    $withoutFramework = Get-InstallationSnapshot
    $failed = $false
    try { & $sync -GameRoot $game -BillboardShaderSubstitution:$false -InitializeInstall | Out-Null }
    catch { $failed = $_.Exception.Message.Contains('Install the Darktide Mod Loader and Framework first') }
    if (-not $failed) { throw 'Clean installation bypassed framework prerequisites.' }
    Assert-Unchanged $withoutFramework
    Write-Fixture $framework 'fixture-dependency'
    $lock = [IO.File]::Open($orderPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $failed = $false
    try { & $sync -GameRoot $game -BillboardShaderSubstitution:$false -InitializeInstall | Out-Null }
    catch { $failed = $_.Exception.Message.Contains('Status=rolled_back') }
    $lock.Dispose(); $lock = $null
    if (-not $failed) { throw 'Clean installation failure did not roll back.' }
    Assert-Unchanged $before
    if (Test-Path -LiteralPath (Join-Path $game $modRelative)) { throw 'New VR tree survived clean-install rollback.' }
    & $sync -GameRoot $game -BillboardShaderSubstitution:$false -InitializeInstall | Out-Null
    if ([IO.File]::ReadAllText($orderPath) -cne "-- Existing user list`ncustom_hud`ndarktidevr_stereo_probe`n") { throw 'Mod load order changed unexpectedly.' }
    $before = Get-InstallationSnapshot
    & $sync -GameRoot $game -BillboardShaderSubstitution:$false -InitializeInstall | Out-Null
    Assert-Unchanged $before
    # No compiler/build script exists here: the package path must use only the
    # verified shader and refuse mismatched production identities before writes.
    $shader = Join-Path $repo 'build\generated\billboard_shaders\vs-42e436fb1ef1b392.dxil'
    $shaderSource = Join-Path $tools 'particle-horizon-lock.vs.hlsl'
    Write-Fixture $shader 'production-shader-fixture'
    Write-Fixture $shaderSource 'production-source-fixture'
    $shaderManifestPath = Join-Path (Split-Path -Parent $shader) 'production-shader.json'
    $shaderManifest = @{schema_version=1;profile='production';scale=1;zero_spin=1;cylindrical=1;
        source_sha256=(Get-FileHash -LiteralPath $shaderSource -Algorithm SHA256).Hash;
        shader_sha256=(Get-FileHash -LiteralPath $shader -Algorithm SHA256).Hash}
    $shaderManifest | ConvertTo-Json | Set-Content -LiteralPath $shaderManifestPath -Encoding UTF8
    & $sync -GameRoot $game -InitializeInstall -UsePrebuiltProductionShader | Out-Null
    $installedShader = Join-Path $game ($modRelative + '\bin\billboard_shaders\vs-42e436fb1ef1b392.dxil')
    if ([IO.File]::ReadAllText($installedShader) -ne 'production-shader-fixture') { throw 'Prebuilt shader was not installed.' }
    $before = Get-InstallationSnapshot
    foreach ($case in @('diagnostic', 'stale-source', 'damaged-shader', 'missing-manifest')) {
        if ($case -eq 'diagnostic') { $shaderManifest.profile = 'diagnostic' }
        else { $shaderManifest.profile = 'production' }
        $shaderManifest | ConvertTo-Json | Set-Content -LiteralPath $shaderManifestPath -Encoding UTF8
        if ($case -eq 'stale-source') { Write-Fixture $shaderSource 'changed-source' }
        if ($case -eq 'damaged-shader') { Write-Fixture $shader 'changed-shader' }
        if ($case -eq 'missing-manifest') { Remove-Item -LiteralPath $shaderManifestPath }
        $failed = $false
        try { & $sync -GameRoot $game -InitializeInstall -UsePrebuiltProductionShader | Out-Null }
        catch { $failed = $_.Exception.Message -match 'Prebuilt (particle|production) shader' }
        if (-not $failed) { throw "Invalid prebuilt shader accepted: $case" }
        Assert-Unchanged $before
        Write-Fixture $shaderSource 'production-source-fixture'
        Write-Fixture $shader 'production-shader-fixture'
    }
    Write-Output 'deployment_sync=pass complete_copy flags diagnostic_removal late_failure_rollback Lua_gate clean_install prebuilt_shader'
} finally {
    if ($lock) { $lock.Dispose() }
    Remove-Variable -Name DeploymentFixtureGateFailure -Scope Global -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolved).StartsWith('darktidevr-sync-test-')) {
        throw 'Refusing cleanup outside the test-owned temporary directory.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
