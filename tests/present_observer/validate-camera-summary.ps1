[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Summarizer,
    [Parameter(Mandatory)] [string] $Fixture
)

$ErrorActionPreference = 'Stop'
$summary = & $Summarizer -LogPath $Fixture | ConvertFrom-Json
if ($summary.schema_version -ne 1 -or
    $summary.sample_count -ne 2 -or
    $summary.unique_position_count -ne 2 -or
    $summary.viewports[0] -ne 'player1' -or
    $summary.last_sample.vertical_fov_rad -ne 1.1) {
    throw 'Camera probe summary contract failed'
}
