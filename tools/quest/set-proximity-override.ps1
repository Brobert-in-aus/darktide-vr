param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Disable', 'Enable', 'Status')]
    [string] $Action,

    [string] $Device
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    $adbCommand = Get-Command adb -ErrorAction SilentlyContinue
    if (-not $adbCommand) {
        throw 'adb.exe was not found in the Android SDK or PATH'
    }
    $adb = $adbCommand.Source
}
if (-not $Device) {
    $devices = @(
        & $adb devices |
            ForEach-Object {
                if ($_ -match '^([^\s]+)\s+device(?:\s|$)') { $Matches[1] }
            }
    )
    if ($devices.Count -ne 1) {
        throw "Expected exactly one authorized ADB device; found $($devices.Count). Use -Device explicitly."
    }
    $Device = $devices[0]
}

$model = (& $adb -s $Device shell getprop ro.product.model).Trim()
if ($LASTEXITCODE -ne 0 -or $model -notmatch '^Quest') {
    throw "ADB target '$Device' is not an authorized Meta Quest device"
}

switch ($Action) {
    'Disable' {
        & $adb -s $Device shell am broadcast `
            -a com.oculus.vrpowermanager.prox_close
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to apply the Quest proximity override'
        }
        Write-Output "Quest proximity automation disabled on $model ($Device)."
        Write-Output 'Restore with -Action Enable or by rebooting the headset.'
    }
    'Enable' {
        & $adb -s $Device shell am broadcast `
            -a com.oculus.vrpowermanager.automation_disable
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to restore Quest proximity automation'
        }
        Write-Output "Quest proximity automation restored on $model ($Device)."
    }
    'Status' {
        Write-Output "Quest target: $model ($Device)"
        & $adb -s $Device shell dumpsys power |
            Select-String -Pattern `
                'mWakefulness=|mProximityPositive=|mHoldingDisplaySuspendBlocker=' `
                -CaseSensitive:$false
        Write-Output 'Quest does not expose a durable query for the broadcast override; reapply Disable before unattended testing if uncertain.'
    }
}
