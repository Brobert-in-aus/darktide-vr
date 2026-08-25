[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $GameExe,

    [Parameter(Mandatory)]
    [string] $PresentMonPath,

    [ValidateRange(5, 3600)]
    [int] $DurationSeconds = 60,

    [string] $OutputDirectory = 'artifacts\phase0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$knownGameHash = 'e0f581d2c63b692c7d9f328e3edeb39c0f484956905569d38ba27bbb3fcc0aae'
$knownPresentMonHash = '9bec3083069f58f911e6a512f4806db51a27bd096103087bc1d05ef54c80a191'

$gameItem = Get-Item -LiteralPath $GameExe
$gameHash = (Get-FileHash -LiteralPath $gameItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($gameHash -ne $knownGameHash) {
    throw "Unknown Darktide executable identity; observation denied"
}

$presentMonItem = Get-Item -LiteralPath $PresentMonPath
$presentMonHash = (Get-FileHash -LiteralPath $presentMonItem.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($presentMonHash -ne $knownPresentMonHash) {
    throw "PresentMon hash does not match the approved 2.5.1 binary"
}
$signature = Get-AuthenticodeSignature -LiteralPath $presentMonItem.FullName
if ($signature.Status -ne 'Valid' -or
    $signature.SignerCertificate.Subject -notmatch '(^|, )O=Intel Corporation(,|$)') {
    throw "PresentMon must have a valid Intel Corporation signature"
}

$gameProcesses = @(Get-Process -Name $gameItem.BaseName -ErrorAction SilentlyContinue)
if ($gameProcesses.Count -ne 1) {
    throw "Expected exactly one running $($gameItem.Name) process; found $($gameProcesses.Count)"
}

$eacServices = @(Get-Service -Name 'EasyAntiCheat*' -ErrorAction SilentlyContinue)
$eacStatus = if ($eacServices.Count -eq 0) {
    'not_installed'
} elseif (@($eacServices | Where-Object Status -eq 'Running').Count -gt 0) {
    'running'
} else {
    'stopped'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$capturePath = Join-Path $OutputDirectory "darktide-present-$stamp.csv"
$summaryPath = Join-Path $OutputDirectory "darktide-present-$stamp.json"
$sessionName = "DarktideVRPhase0-$PID"

& $presentMonItem.FullName `
    --process_id $gameProcesses[0].Id `
    --timed $DurationSeconds `
    --terminate_after_timed `
    --output_file $capturePath `
    --no_console_stats `
    --session_name $sessionName
if ($LASTEXITCODE -ne 0) {
    throw "PresentMon failed with exit code $LASTEXITCODE"
}

$summarizer = Join-Path $PSScriptRoot 'summarize-presentmon.ps1'
$summary = & $summarizer -CaptureCsv $capturePath | ConvertFrom-Json
$result = [ordered]@{
    schema_version = 1
    observation = 'external_etw_metadata_only'
    game_sha256 = $gameHash
    presentmon_sha256 = $presentMonHash
    eac_service_status = $eacStatus
    process_id = $gameProcesses[0].Id
    capture_file = Split-Path -Leaf $capturePath
    candidate_count = $summary.candidate_count
    selection = $summary.selection
    candidates = $summary.candidates
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8
$result | ConvertTo-Json -Depth 10
