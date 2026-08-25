[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Summarizer,
    [Parameter(Mandatory)] [string] $Fixture
)

$ErrorActionPreference = 'Stop'
$summary = & $Summarizer -CaptureCsv $Fixture | ConvertFrom-Json
if ($summary.schema_version -ne 1 -or
    $summary.total_presents -ne 3 -or
    $summary.candidate_count -ne 1 -or
    $summary.selection -ne 'selected' -or
    $summary.candidates[0].mean_interval_ms -ne 20.0 -or
    $summary.candidates[0].present_modes.'Hardware Composed: Independent Flip' -ne 2) {
    throw 'PresentMon summary contract failed'
}
