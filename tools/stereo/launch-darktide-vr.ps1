[CmdletBinding()]
param(
    [ValidateRange(5, 43200)]
    [int] $DurationSeconds = 28800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$startScript = Join-Path $PSScriptRoot 'start-darktide-vr.ps1'
$logDirectory = Join-Path $env:LOCALAPPDATA 'DarktideVR'
$logPath = Join-Path $logDirectory 'launcher.log'

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

try {
    if (-not (Test-Path -LiteralPath $startScript -PathType Leaf)) {
        throw "Darktide VR start script not found: $startScript"
    }
    if (Get-Process darktidevr-xr-harness -ErrorAction SilentlyContinue) {
        throw 'The Darktide VR bridge is already running.'
    }

    "$(Get-Date -Format o) Starting authenticated Darktide VR launch." |
        Add-Content -LiteralPath $logPath

    # Retain the ordinary Steam -> Fatshark launcher -> Darktide authentication
    # path. start-darktide-vr.ps1 invokes the launcher's normal Play control and
    # the bridge attaches automatically when the resulting game process starts.
    & $startScript `
        -DurationSeconds $DurationSeconds `
        -GameStartTimeoutSeconds 1800 `
        -EnableMenuInput 2>&1 |
        ForEach-Object {
            $line = [string] $_
            $line | Out-File -LiteralPath $logPath -Encoding utf8 -Append
            Write-Output $line
        }

    if ($LASTEXITCODE -ne 0) {
        throw "Darktide VR exited with code $LASTEXITCODE."
    }
}
catch {
    $message = "Darktide VR could not start.`r`n`r`n$($_.Exception.Message)`r`n`r`nLog: $logPath"
    "$(Get-Date -Format o) ERROR $($_.Exception)" |
        Add-Content -LiteralPath $logPath
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(
        $message,
        'Darktide VR',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
    exit 1
}
