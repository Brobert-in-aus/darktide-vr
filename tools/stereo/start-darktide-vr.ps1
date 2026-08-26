[CmdletBinding()]
param(
    [ValidateRange(5, 3600)]
    [int] $DurationSeconds = 3600,

    [ValidateRange(5, 1800)]
    [int] $GameStartTimeoutSeconds = 600,

    [switch] $FreshPsoCache,

    [switch] $DoNotOpenLauncher
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runner = Join-Path $PSScriptRoot 'run-darktide-shared-eyes.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "XR runner not found: $runner"
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
    # The Fatshark launcher remains mandatory for authentication. Steam opens
    # it; this wrapper deliberately does not bypass or automate its Play action.
    Start-Process 'steam://rungameid/1361210'
}

Write-Output 'Waiting for the Darktide splash window; XR will start as soon as it exists.'
& $runner `
    -DurationSeconds $DurationSeconds `
    -WaitForGameSeconds $GameStartTimeoutSeconds
