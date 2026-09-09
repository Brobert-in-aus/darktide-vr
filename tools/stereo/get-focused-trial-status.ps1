[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]] $PlanPaths,
    [Parameter(Mandatory)][string] $GameRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath $GameRoot).Path
if (-not (Test-Path -LiteralPath $game -PathType Container)) { throw 'GameRoot must be a directory.' }
function Resolve-TrialPath([string] $Root, [string] $Relative) {
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative)) {
        throw 'Trial paths must be nonempty relative paths.'
    }
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $absolute = [IO.Path]::GetFullPath((Join-Path $rootPath $Relative))
    if (-not $absolute.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw 'Trial path escapes its root.' }
    $cursor = $absolute
    while ($cursor -ne $rootPath) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Trial path contains a reparse point.' }
            if ($cursor -ne $absolute -and -not $item.PSIsContainer) { throw 'Trial parent is not a directory.' }
        }
        $cursor = Split-Path -Parent $cursor
    }
    return $absolute
}
function Read-TrialHash([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Trial file path is a directory.' }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
$seenPlans = @{}
$destinations = @{}
$trials = @()
foreach ($path in $PlanPaths) {
    $planPath = (Resolve-Path -LiteralPath $path).Path
    if ($seenPlans.ContainsKey($planPath)) { throw 'Duplicate trial plan.' }
    $seenPlans[$planPath] = $true
    $planRoot = Split-Path -Parent $planPath
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if ($plan.schema_version -ne 1 -or $plan.kind -ne 'selective_trial_plan' -or
        $plan.status -ne 'staged_not_deployed' -or @($plan.entries).Count -eq 0) {
        throw 'Unsupported or empty staged trial plan.'
    }
    $rows = @()
    $seenDestinations = @{}
    foreach ($entry in $plan.entries) {
        if ($entry.ExpectedSourceHash -notmatch '^[0-9a-fA-F]{64}$' -or
            ($null -ne $entry.ExpectedDestinationHash -and
             $entry.ExpectedDestinationHash -notmatch '^[0-9a-fA-F]{64}$')) {
            throw 'Invalid trial hash precondition.'
        }
        $source = Resolve-TrialPath $planRoot $entry.Source
        $destination = Resolve-TrialPath $game $entry.Destination
        if ($seenDestinations.ContainsKey($destination)) { throw 'Duplicate trial destination.' }
        $seenDestinations[$destination] = $true
        $sourceHash = Read-TrialHash $source
        $destinationHash = Read-TrialHash $destination
        $rows += [pscustomobject]@{
            destination = $entry.Destination
            source_matches = $sourceHash -eq $entry.ExpectedSourceHash
            baseline_matches = $destinationHash -eq $entry.ExpectedDestinationHash
            actual_source_hash = $sourceHash
            actual_destination_hash = $destinationHash
        }
        if (-not $destinations.ContainsKey($destination)) { $destinations[$destination] = @() }
        $destinations[$destination] += $planPath
    }
    $trials += [pscustomobject]@{
        plan = $planPath
        reviewed_revision = $plan.reviewed_revision
        hashes_match = @($rows | Where-Object { -not $_.source_matches -or -not $_.baseline_matches }).Count -eq 0
        entries = $rows
    }
}
$overlaps = @($destinations.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } |
    Sort-Object Key | ForEach-Object { [pscustomobject]@{ destination=$_.Key; plans=$_.Value } })
[pscustomobject]@{
    schema_version = 1
    kind = 'read_only_trial_status'
    all_hashes_match = @($trials | Where-Object { -not $_.hashes_match }).Count -eq 0
    readiness_verified = $false
    trials = $trials
    overlapping_destinations = $overlaps
}
