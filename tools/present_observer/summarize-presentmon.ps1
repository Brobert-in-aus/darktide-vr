[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $CaptureCsv,

    [string] $OutputJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rows = @(Import-Csv -LiteralPath $CaptureCsv)
if ($rows.Count -eq 0) {
    throw "PresentMon capture contains no rows: $CaptureCsv"
}

$requiredColumns = @(
    'Application', 'ProcessID', 'SwapChainAddress', 'PresentRuntime',
    'PresentMode', 'MsBetweenPresents'
)
$columns = @($rows[0].PSObject.Properties.Name)
foreach ($requiredColumn in $requiredColumns) {
    if ($requiredColumn -notin $columns) {
        throw "PresentMon capture is missing required column '$requiredColumn'"
    }
}

$candidates = @(
    $rows |
        Group-Object Application, ProcessID, SwapChainAddress |
        ForEach-Object {
            $group = @($_.Group)
            $intervals = @(
                $group |
                    ForEach-Object {
                        $value = 0.0
                        if ([double]::TryParse(
                                $_.MsBetweenPresents,
                                [Globalization.NumberStyles]::Float,
                                [Globalization.CultureInfo]::InvariantCulture,
                                [ref] $value) -and $value -gt 0.0) {
                            $value
                        }
                    } |
                    Sort-Object
            )
            if ($intervals.Count -eq 0) {
                throw "Swapchain $($group[0].SwapChainAddress) has no valid intervals"
            }

            $mean = ($intervals | Measure-Object -Average).Average
            $lastIndex = $intervals.Count - 1
            [ordered]@{
                application = $group[0].Application
                process_id = [int] $group[0].ProcessID
                swapchain_address = $group[0].SwapChainAddress
                present_count = $group.Count
                present_runtime = @($group.PresentRuntime | Sort-Object -Unique)
                present_modes = [ordered]@{}
                mean_interval_ms = [math]::Round($mean, 4)
                p50_interval_ms = [math]::Round(
                    $intervals[[math]::Floor($lastIndex * 0.50)], 4)
                p95_interval_ms = [math]::Round(
                    $intervals[[math]::Floor($lastIndex * 0.95)], 4)
                p99_interval_ms = [math]::Round(
                    $intervals[[math]::Floor($lastIndex * 0.99)], 4)
            }
        }
)

for ($index = 0; $index -lt $candidates.Count; ++$index) {
    $candidateRows = @(
        $rows | Where-Object {
            $_.Application -eq $candidates[$index].application -and
            [int] $_.ProcessID -eq $candidates[$index].process_id -and
            $_.SwapChainAddress -eq $candidates[$index].swapchain_address
        }
    )
    foreach ($mode in @($candidateRows | Group-Object PresentMode)) {
        $candidates[$index].present_modes[$mode.Name] = $mode.Count
    }
}

$summary = [ordered]@{
    schema_version = 1
    source = 'Intel PresentMon ETW'
    capture_file = Split-Path -Leaf $CaptureCsv
    total_presents = $rows.Count
    candidate_count = $candidates.Count
    selection = if ($candidates.Count -eq 1) { 'selected' } else { 'ambiguous' }
    candidates = $candidates
}

$json = $summary | ConvertTo-Json -Depth 8
if ($OutputJson) {
    $parent = Split-Path -Parent $OutputJson
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputJson -Value $json -Encoding utf8
}
$json
