$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dtvr-launch-' + [guid]::NewGuid())
$previousAppData = $env:APPDATA
New-Item -ItemType Directory -Path $fixture | Out-Null
$modDirectory = Join-Path $fixture 'mods/darktidevr_stereo_probe'
New-Item -ItemType Directory -Path $modDirectory -Force | Out-Null
$scriptsDirectory = Join-Path $modDirectory 'scripts'
$scriptsModsDirectory = Join-Path $scriptsDirectory 'mods'
$luaDirectory = Join-Path $scriptsModsDirectory 'darktidevr_stereo_probe'
New-Item -ItemType Directory -Path $luaDirectory -Force | Out-Null
$luaSource = Join-Path $luaDirectory 'darktidevr_stereo_probe.lua'
$descriptor = Join-Path $modDirectory 'darktidevr_stereo_probe.mod'
# Pass installed compilation so this fixture still reaches its intended cache
# setup failure. These chunks must never execute or start a mod/game session.
[IO.File]::WriteAllText($luaSource, 'error("Early-failure fixture Lua must only compile")')
[IO.File]::WriteAllText($descriptor, 'error("Early-failure fixture descriptor must only compile")')
$binaryDirectory = Join-Path $fixture 'binaries'
New-Item -ItemType Directory -Path $binaryDirectory | Out-Null
New-Item -ItemType File -Path (Join-Path $binaryDirectory 'Darktide.exe') | Out-Null
try {
    $env:APPDATA = $fixture
    # Prevent this source-level scenario from observing an unrelated live game.
    function Get-Process { param($Name) return @() }
    function Get-CimInstance { param($ClassName) return [pscustomobject]@{ NumberOfCores = 8 } }
    $failed = $false
    try {
        & (Join-Path $repo 'tools/stereo/start-darktide-vr.ps1') `
            -GameRoot $fixture -SkipDeploymentSync -EnterPsykhanium `
            -FreshPsoCache -DoNotOpenLauncher
    } catch {
        # Worker auto-configuration now runs before PSO preservation. Either
        # missing prerequisite must fail before arming the one-shot range flag.
        if ($_.Exception.Message -notmatch '(cache directory|settings file) not found') { throw }
        $failed = $true
    }
    if (-not $failed -or (Test-Path (Join-Path $fixture 'mods/darktidevr_stereo_probe/darktidevr_enter_psykhanium.flag'))) {
        throw 'Early setup failure must not arm a later Psykhanium entry'
    }
    Write-Output 'launcher_early_failure=pass'
} finally {
    $env:APPDATA = $previousAppData
    # Only remove this exact empty fixture; never recurse through game paths.
    $flag = Join-Path $modDirectory 'darktidevr_enter_psykhanium.flag'
    if (Test-Path $flag) { Remove-Item -LiteralPath $flag }
    Remove-Item -LiteralPath $luaSource
    Remove-Item -LiteralPath $descriptor
    Remove-Item -LiteralPath $luaDirectory
    Remove-Item -LiteralPath $scriptsModsDirectory
    Remove-Item -LiteralPath $scriptsDirectory
    Remove-Item -LiteralPath $modDirectory
    Remove-Item -LiteralPath (Join-Path $fixture 'mods')
    Remove-Item -LiteralPath (Join-Path $binaryDirectory 'Darktide.exe')
    Remove-Item -LiteralPath $binaryDirectory
    Remove-Item -LiteralPath $fixture
}
