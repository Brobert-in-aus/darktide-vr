$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dtvr-launch-' + [guid]::NewGuid())
$previousAppData = $env:APPDATA
New-Item -ItemType Directory -Path $fixture | Out-Null
$modDirectory = Join-Path $fixture 'mods/darktidevr_stereo_probe'
New-Item -ItemType Directory -Path $modDirectory -Force | Out-Null
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
    Remove-Item -LiteralPath $modDirectory
    Remove-Item -LiteralPath (Join-Path $fixture 'mods')
    Remove-Item -LiteralPath $fixture
}
