[CmdletBinding()]
param(
    [ValidateRange(5, 43200)]
    [int] $DurationSeconds = 28800,

    [ValidateRange(5, 1800)]
    [int] $GameStartTimeoutSeconds = 600,

    [string] $GameRoot =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE',

    [switch] $FreshPsoCache,

    [switch] $DiagnosticRenderHooks,

    [switch] $EnableMenuInput,

    [switch] $EnableMenuTestControls,

    [switch] $SyntheticControllerPath,

    [switch] $SyntheticGameplayInput,

    [switch] $SyntheticWeaponAimMatrix,

    [switch] $SyntheticMovementReferencePath,

    [switch] $EnableGameplayReticle,

    [switch] $EnableHudPanel,

    [switch] $SyntheticBodyPath,

    [switch] $SyntheticHeadSweep,

    [switch] $SyntheticBodyInspection,

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

if ($SyntheticWeaponAimMatrix) {
    # The matrix is a self-contained private-range gate: deterministic tracked
    # controls, Lua gameplay adapter, controller-authored aim and depth reticle.
    $SyntheticControllerPath = $true
    $SyntheticGameplayInput = $true
    $EnableGameplayReticle = $true
    $EnterPsykhanium = $true
}
if ($SyntheticMovementReferencePath) {
    $SyntheticControllerPath = $true
    $SyntheticGameplayInput = $true
}

if (-not $SkipDeploymentSync) {
    $sync = Join-Path $PSScriptRoot 'sync-darktide-vr-dev.ps1'
    if (-not (Test-Path -LiteralPath $sync -PathType Leaf)) {
        throw "Development sync script not found: $sync"
    }
    if (Get-Process Darktide -ErrorAction SilentlyContinue) {
        Write-Warning 'Darktide is already running; deployment sync cannot update loaded files.'
    }
    else {
        & $sync -GameRoot $GameRoot -Configuration Release `
            -DiagnosticRenderHooks:$DiagnosticRenderHooks
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

    # The in-game one-shot state machine deliberately waits for an
    # authenticated hub before opening the training-ground view.  Therefore
    # Psykhanium entry also owns the guarded splash/operative advance; without
    # it an unattended run can remain at character select until its timeout.
    $AutoEnterHub = $true
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

$xrLaunchOwnsGame = $false
$xrRunnerStarted = $false
$gameplayInputFlagPath = $null
$gameplayInputFlagOriginal = $null
$hudPanelFlagPath = $null
$hudPanelFlagOriginal = $null
$controllerAimFlagPath = $null
$controllerAimFlagOriginal = $null
try {
if ($EnableGameplayReticle) {
    $candidateControllerAimFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_controller_aim_test.flag'
    if (-not (Test-Path -LiteralPath $candidateControllerAimFlagPath -PathType Leaf)) {
        throw "Controller-aim test flag not found: $candidateControllerAimFlagPath"
    }
    $controllerAimFlagOriginal = Get-Content -LiteralPath `
        $candidateControllerAimFlagPath -Raw
    $controllerAimFlagPath = $candidateControllerAimFlagPath
    Set-Content -LiteralPath $controllerAimFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Controller aim enabled for this reticle run.'
}
if ($EnableHudPanel) {
    $candidateHudPanelFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_hud_panel.flag'
    if (-not (Test-Path -LiteralPath $candidateHudPanelFlagPath -PathType Leaf)) {
        throw "HUD-panel test flag not found: $candidateHudPanelFlagPath"
    }
    $hudPanelFlagOriginal = Get-Content -LiteralPath `
        $candidateHudPanelFlagPath -Raw
    $hudPanelFlagPath = $candidateHudPanelFlagPath
    Set-Content -LiteralPath $hudPanelFlagPath -Value 'enable' `
        -Encoding ascii
    Write-Output 'Fixed HUD panel enabled for this XR run.'
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
    $xrLaunchOwnsGame = $true
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
else {
    $xrLaunchOwnsGame = $true
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
    $candidateGameplayInputFlagPath = Join-Path $GameRoot `
        'mods\darktidevr_stereo_probe\darktidevr_gameplay_input_test.flag'
    if (-not (Test-Path -LiteralPath $candidateGameplayInputFlagPath -PathType Leaf)) {
        throw "Gameplay-input test flag not found: $candidateGameplayInputFlagPath"
    }
    $gameplayInputFlagOriginal = Get-Content -LiteralPath `
        $candidateGameplayInputFlagPath -Raw
    $gameplayInputFlagPath = $candidateGameplayInputFlagPath
    Set-Content -LiteralPath $gameplayInputFlagPath -Value 'enabled' `
        -Encoding ascii
    Write-Output 'Synthetic gameplay adapter enabled for this XR run.'
    $runnerArguments.SyntheticGameplayInput = $true
}
if ($SyntheticWeaponAimMatrix) {
    $runnerArguments.SyntheticWeaponAimMatrix = $true
}
if ($SyntheticMovementReferencePath) {
    $runnerArguments.SyntheticMovementReferencePath = $true
}
if ($EnableGameplayReticle) {
    $runnerArguments.EnableGameplayReticle = $true
}
if ($SyntheticBodyPath) {
    $runnerArguments.SyntheticBodyPath = $true
}
if ($SyntheticHeadSweep) {
    $runnerArguments.SyntheticHeadSweep = $true
}
if ($SyntheticBodyInspection) {
    $runnerArguments.SyntheticBodyInspection = $true
}
if ($SyntheticNeckPivotPath) {
    $runnerArguments.SyntheticNeckPivotPath = $true
}
if ($SyntheticCrouchPath) {
    $runnerArguments.SyntheticCrouchPath = $true
}
$xrRunnerStarted = $true
& $runner @runnerArguments
}
finally {
    if ($controllerAimFlagPath) {
        Set-Content -LiteralPath $controllerAimFlagPath `
            -Value $controllerAimFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior controller-aim test flag.'
    }
    if ($hudPanelFlagPath) {
        Set-Content -LiteralPath $hudPanelFlagPath `
            -Value $hudPanelFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior HUD-panel test flag.'
    }
    if ($gameplayInputFlagPath) {
        Set-Content -LiteralPath $gameplayInputFlagPath `
            -Value $gameplayInputFlagOriginal.Trim() -Encoding ascii
        Write-Output 'Restored the prior gameplay-input test flag.'
    }
    if ($xrLaunchOwnsGame) {
        # A supported launch must never leave an authenticated flat Darktide
        # process behind after its XR owner exits. Launcher Play can complete
        # just after its UI helper reports failure, so cover that late-process
        # race before returning the original error to the caller.
        $cleanupDeadline = if ($xrRunnerStarted) {
            Get-Date
        }
        else {
            (Get-Date).AddSeconds(30)
        }
        do {
            $orphanedGames = @(Get-Process -Name Darktide `
                    -ErrorAction SilentlyContinue)
            if ($orphanedGames.Count -gt 0) {
                $orphanedGames | Stop-Process -Force
                Write-Warning `
                    'XR owner exited; terminated the orphaned flat Darktide process.'
                break
            }
            if ((Get-Date) -ge $cleanupDeadline) {
                break
            }
            Start-Sleep -Milliseconds 500
        } while ($true)
    }
}
