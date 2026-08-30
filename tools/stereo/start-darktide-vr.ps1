[CmdletBinding()]
param(
    [ValidateRange(5, 43200)]
    [int] $DurationSeconds = 28800,

    [ValidateRange(5, 1800)]
    [int] $GameStartTimeoutSeconds = 600,

    [string] $GameRoot =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE',

    [switch] $FreshPsoCache,

    [switch] $EnableMenuInput,

    [switch] $EnableMenuTestControls,

    [switch] $SyntheticControllerPath,

    [switch] $SyntheticGameplayInput,

    [switch] $SyntheticBodyPath,

    [switch] $SyntheticHeadSweep,

    [switch] $SyntheticNeckPivotPath,

    [switch] $SyntheticCrouchPath,

    [switch] $EnterPsykhanium,

    [switch] $AutoEnterHub,

    [switch] $AutoAdvanceSplash,

    [ValidateRange(-2.0, 2.0)]
    [double] $ProjectionTranslationScale = 1.0,

    [switch] $SkipDeploymentSync,

    [switch] $DoNotOpenLauncher,

    [switch] $ManualLauncherPlay
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'run-darktide-shared-eyes.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "XR runner not found: $runner"
}
$luaSourceCheck = Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1'
if (-not (Test-Path -LiteralPath $luaSourceCheck -PathType Leaf)) {
    throw "Lua source check not found: $luaSourceCheck"
}
& $luaSourceCheck

if (-not $SkipDeploymentSync) {
    $sync = Join-Path $PSScriptRoot 'sync-darktide-vr-dev.ps1'
    if (-not (Test-Path -LiteralPath $sync -PathType Leaf)) {
        throw "Development sync script not found: $sync"
    }
    if (Get-Process Darktide -ErrorAction SilentlyContinue) {
        Write-Warning 'Darktide is already running; deployment sync cannot update loaded files.'
    }
    else {
        & $sync -GameRoot $GameRoot -Configuration Release
    }
}

if ($EnterPsykhanium) {
    if (Get-Process Darktide -ErrorAction SilentlyContinue) {
        throw 'Psykhanium entry must be armed before Darktide starts; close the game and retry.'
    }
    $psykhaniumFlag = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_enter_psykhanium.flag'
    if (-not (Test-Path -LiteralPath $psykhaniumFlag -PathType Leaf)) {
        throw "Psykhanium one-shot flag not found: $psykhaniumFlag"
    }
    Set-Content -LiteralPath $psykhaniumFlag -Value 'enter' -Encoding ascii
    Write-Output 'Psykhanium entry armed before launcher startup.'
}

if ($FreshPsoCache) {
    if (Get-Process -Name Darktide -ErrorAction SilentlyContinue) {
        throw 'Darktide must be fully closed before preserving its PSO cache.'
    }
    $cacheRoot = Join-Path $env:APPDATA 'Fatshark\Darktide'
    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) {
        throw "Darktide cache directory not found: $cacheRoot"
    }
    $resolvedCacheRoot = (Resolve-Path -LiteralPath $cacheRoot).Path
    if ($resolvedCacheRoot -ne $cacheRoot) {
        throw "Unexpected Darktide cache directory: $resolvedCacheRoot"
    }
    $cacheFiles = @(@(
        Join-Path $cacheRoot 'shader_library.pso_lib'
        Join-Path $cacheRoot 'state_stream_library.pso_lib'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($cacheFiles.Count -gt 0) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = Join-Path $cacheRoot "pso-cache-backup-$stamp"
        New-Item -ItemType Directory -Path $backup | Out-Null
        foreach ($cacheFile in $cacheFiles) {
            Move-Item -LiteralPath $cacheFile -Destination $backup
        }
        Write-Output "Preserved the prior PSO cache in $backup"
    }
}

if (-not $DoNotOpenLauncher) {
    $expectedLauncherPath = Join-Path $GameRoot 'launcher\Launcher.exe'
    if (-not (Test-Path -LiteralPath $expectedLauncherPath -PathType Leaf)) {
        throw "Fatshark launcher not found: $expectedLauncherPath"
    }
    $expectedLauncherPath =
        (Resolve-Path -LiteralPath $expectedLauncherPath).Path
    $runningDarktideLaunchers = @(Get-Process Launcher `
            -ErrorAction SilentlyContinue |
        Where-Object {
            try {
                $_.Path -eq $expectedLauncherPath
            }
            catch {
                $false
            }
        })
    if ($runningDarktideLaunchers.Count -ne 0) {
        throw 'A launcher process is already running; close it before a clean authenticated launch.'
    }
    # Preserve the supported Steam -> Fatshark launcher path. The launcher has
    # no autoplay command-line switch, so the guarded helper invokes its normal
    # Play control after verifying process identity and window geometry.
    Start-Process 'steam://rungameid/1361210'
    if (-not $ManualLauncherPlay) {
        $launcherPlayHelper = Join-Path $PSScriptRoot `
            'invoke-darktide-launcher-play.ps1'
        if (-not (Test-Path -LiteralPath $launcherPlayHelper -PathType Leaf)) {
            throw "Launcher Play helper not found: $launcherPlayHelper"
        }
        & $launcherPlayHelper `
            -TimeoutSeconds $GameStartTimeoutSeconds `
            -GameRoot $GameRoot
    }
}

if ($AutoEnterHub -or $AutoAdvanceSplash) {
    $advanceHelper = Join-Path $PSScriptRoot 'advance-darktide-to-hub.ps1'
    if (-not (Test-Path -LiteralPath $advanceHelper -PathType Leaf)) {
        throw "Darktide hub advance helper not found: $advanceHelper"
    }
    $powershell = (Get-Process -Id $PID).Path
    $advanceArguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        "`"$advanceHelper`"",
        '-TimeoutSeconds',
        $GameStartTimeoutSeconds
    )
    if ($AutoAdvanceSplash -and -not $AutoEnterHub) {
        $advanceArguments += '-StopAtCharacterSelect'
    }
    Start-Process -FilePath $powershell -WindowStyle Hidden `
        -ArgumentList $advanceArguments
    if ($AutoEnterHub) {
        Write-Output 'Armed state-gated Space/Enter automation through character select.'
    }
    else {
        Write-Output 'Armed state-gated Space automation to character select.'
    }
}

Write-Output 'Waiting for the Darktide splash window; XR will start as soon as it exists.'
$runnerArguments = @{
    DurationSeconds = $DurationSeconds
    WaitForGameSeconds = $GameStartTimeoutSeconds
    ProjectionTranslationScale = $ProjectionTranslationScale
    GameExe = Join-Path $GameRoot 'binaries\Darktide.exe'
}
if ($EnableMenuInput) {
    $runnerArguments.EnableMenuInput = $true
}
if ($EnableMenuTestControls) {
    $runnerArguments.EnableMenuTestControls = $true
}
if ($SyntheticControllerPath) {
    $runnerArguments.SyntheticControllerPath = $true
}
if ($SyntheticGameplayInput) {
    $runnerArguments.SyntheticGameplayInput = $true
}
if ($SyntheticBodyPath) {
    $runnerArguments.SyntheticBodyPath = $true
}
if ($SyntheticHeadSweep) {
    $runnerArguments.SyntheticHeadSweep = $true
}
if ($SyntheticNeckPivotPath) {
    $runnerArguments.SyntheticNeckPivotPath = $true
}
if ($SyntheticCrouchPath) {
    $runnerArguments.SyntheticCrouchPath = $true
}
& $runner @runnerArguments
