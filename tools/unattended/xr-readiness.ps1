function Assert-XrReadiness {
    param([int] $StreamerCount, [string] $Runtime, [string[]] $PowerLines,
          [int] $PowerExitCode)
    if ($StreamerCount -lt 1) { throw 'Virtual Desktop Streamer is not running.' }
    if (-not $Runtime -or (Split-Path $Runtime -Leaf) -ine 'virtualdesktop-openxr.json' -or
        -not (Test-Path -LiteralPath $Runtime -PathType Leaf)) {
        throw 'Select the installed Virtual Desktop OpenXR runtime (VDXR).'
    }
    if ($PowerExitCode -ne 0) { throw 'ADB could not read Quest power state.' }
    $power = $PowerLines -join "`n"
    if ($power -notmatch 'mWakefulness=Awake\b' -or
        $power -notmatch 'mHoldingDisplaySuspendBlocker=true\b') {
        throw 'Quest is not awake with its display held on; reapply the proximity override.'
    }
}
