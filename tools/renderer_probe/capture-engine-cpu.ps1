[CmdletBinding()]
param(
    [Parameter(Mandatory)][int] $GameProcessId,
    [Parameter(Mandatory)][string] $GameExe,
    [Parameter(Mandatory)][string] $OutputPath,
    [ValidateRange(5, 60)][int] $Seconds = 20
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$gamePath = (Resolve-Path -LiteralPath $GameExe).Path
$output = [IO.Path]::GetFullPath($OutputPath)
if ([IO.Path]::GetExtension($output) -ne '.etl' -or (Test-Path -LiteralPath $output)) {
    throw 'Select a new .etl output path.'
}
$game = Get-Process -Id $GameProcessId -ErrorAction Stop
if ($game.Path -ine $gamePath -or $game.ProcessName -ine 'Darktide') {
    throw 'The selected process is not the specified Darktide executable.'
}
$startedAt = $game.StartTime
$wpr = (Get-Command wpr.exe -ErrorAction Stop).Source
$status = @(& $wpr -status 2>&1)
if ($LASTEXITCODE -ne 0 -or ($status -join "`n") -notmatch 'WPR is not recording') {
    throw 'An existing or unknown WPR session must remain untouched.'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $output) -Force | Out-Null
$profile = (Join-Path $PSScriptRoot 'engine-cpu.wprp') + '!EngineCpu'
$instance = 'DarktideVR-' + [guid]::NewGuid().ToString('N')
$recording = $false
$begin = [DateTime]::UtcNow
try {
    & $wpr -start $profile -instancename $instance
    if ($LASTEXITCODE -ne 0) { throw 'WPR could not start the owned CPU capture.' }
    $recording = $true
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        Start-Sleep -Milliseconds 250
        $current = Get-Process -Id $GameProcessId -ErrorAction SilentlyContinue
        if (-not $current -or $current.StartTime -ne $startedAt) {
            throw 'The captured game process exited; saving the partial trace.'
        }
    } while ([DateTime]::UtcNow -lt $deadline)
} finally {
    if ($recording) {
        & $wpr -stop $output -skipPdbGen -instancename $instance
        if ($LASTEXITCODE -ne 0) {
            throw "CPU trace save failed; owned WPR instance is $instance. Do not cancel unrelated sessions."
        }
    }
}
[pscustomobject]@{
    output = $output; process_id = $GameProcessId
    process_start_utc = $startedAt.ToUniversalTime().ToString('o')
    capture_start_utc = $begin.ToString('o'); capture_end_utc = [DateTime]::UtcNow.ToString('o')
    executable_sha256 = (Get-FileHash -LiteralPath $gamePath).Hash
    trace_sha256 = (Get-FileHash -LiteralPath $output).Hash
    requested_seconds = $Seconds; buffer_budget_mib = 128
    scope = 'system_cpu_samples; filter analysis to recorded game process'
    readiness_verified = $false
} | ConvertTo-Json
