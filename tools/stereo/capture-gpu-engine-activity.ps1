[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $OutputPath,
    [Parameter(Mandatory)] [string] $StopPath,
    [ValidateRange(1,1500)] [int] $MaximumSeconds = 900,
    [ValidateRange(1,30)] [int] $IntervalSeconds = 5
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Observational only: never stops a measured process or changes VD settings.
# An absent/failed counter is unknown, not zero GPU utilisation.
$deadline = [DateTime]::UtcNow.AddSeconds($MaximumSeconds)
$writer = [IO.StreamWriter]::new($OutputPath, $false, [Text.UTF8Encoding]::new($false))
$writer.AutoFlush = $true
try {
    while ([DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $StopPath)) {
        $began = [DateTime]::UtcNow
        $record = [ordered]@{schema=1; utc=$began.ToString('o'); status='unavailable'; processes=@(); engines=@(); error=$null}
        try {
            $processes = @(Get-Process -Name Darktide,VirtualDesktop.Streamer,VirtualDesktop.Service,darktidevr-xr-harness -ErrorAction SilentlyContinue)
            $names = @{}
            foreach ($measured in $processes) {
                $names[$measured.Id] = $measured.ProcessName
                $record.processes += @{id=$measured.Id; name=$measured.ProcessName}
            }
            $counter = Get-Counter -Counter '\GPU Engine(*)\Utilization Percentage' -MaxSamples 1 -ErrorAction Stop
            $record.utc = $counter.Timestamp.ToUniversalTime().ToString('o')
            $engines = @()
            foreach ($sample in $counter.CounterSamples) {
                if ($sample.InstanceName -notmatch '^pid_(\d+)_(.+)_engtype_(.+)$') { continue }
                $measuredId = [int]$Matches[1]
                $engineType = $Matches[3]
                if (-not $names.ContainsKey($measuredId)) { continue }
                $value = [double]$sample.CookedValue
                $valid = $sample.Status -in @(0,1) -and -not [double]::IsNaN($value) -and -not [double]::IsInfinity($value) -and $value -ge 0
                $engines += @{process_id=$measuredId; process_name=$names[$measuredId]; instance=$sample.InstanceName;
                    type=$engineType; valid=$valid; percent=$(if ($valid) {$value} else {$null})}
            }
            $record.status = 'sampled'
            $record.engines = $engines
        } catch { $record.error = $_.Exception.Message }
        $record['capture_ms'] = ([DateTime]::UtcNow-$began).TotalMilliseconds
        $writer.WriteLine(($record | ConvertTo-Json -Depth 6 -Compress))
        $next = $began.AddSeconds($IntervalSeconds)
        while ([DateTime]::UtcNow -lt $next -and [DateTime]::UtcNow -lt $deadline -and -not (Test-Path -LiteralPath $StopPath)) {
            Start-Sleep -Milliseconds 200
        }
    }
} finally { $writer.Dispose() }
