param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Baseline,
    [Parameter(Mandatory)][string]$Candidate,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$BaselineHash,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$CandidateHash,
    [Parameter(Mandatory)][string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$exePath = (Resolve-Path -LiteralPath $Executable).Path
$exeHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
$versions = @(
    @{name='baseline';source=(Resolve-Path -LiteralPath $Baseline).Path;hash=$BaselineHash},
    @{name='candidate';source=(Resolve-Path -LiteralPath $Candidate).Path;hash=$CandidateHash}
)
foreach ($version in $versions) {
    if ((Get-FileHash -LiteralPath $version.source -Algorithm SHA256).Hash -ne $version.hash) {
        throw "Source hash mismatch: $($version.name)"
    }
}
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $outputRoot) { throw 'Output directory must be new.' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$savedOverrides = @(Get-ChildItem Env: | Where-Object Name -Like 'DARKTIDEVR_*')
$rows = @()
$menuDigest = $null
$process = $null
try {
    foreach ($override in $savedOverrides) { [Environment]::SetEnvironmentVariable($override.Name, $null, 'Process') }
    for ($trial=0; $trial -lt 5; $trial++) {
        $order = if ($trial % 2 -eq 0) { @(0,1) } else { @(1,0) }
        foreach ($index in $order) {
            $version = $versions[$index]
            $run = Join-Path $outputRoot ($version.name + '-' + $trial)
            New-Item -ItemType Directory -Path $run | Out-Null
            $copy = Join-Path $run 'darktidevr_native_capture.dll'
            Copy-Item -LiteralPath $version.source -Destination $copy
            if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $version.hash) { throw 'Copied DLL hash mismatch.' }
            $env:TEMP = $run
            $env:TMP = $run
            $stdout = Join-Path $run 'result.log'
            $stderr = Join-Path $run 'stderr.log'
            $process = Start-Process -FilePath $exePath -ArgumentList ('"' + $copy + '"') -WorkingDirectory $run -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            if (-not $process.WaitForExit(60000)) {
                $process.Kill()
                $process.WaitForExit()
                throw "Benchmark timed out: $run"
            }
            if ($process.ExitCode -ne 0) { throw "Benchmark failed: $run (exit $($process.ExitCode))" }
            $lines = @(Get-Content -LiteralPath $stdout)
            if ($lines -notcontains 'PASS recorded_only=1 gpu_submissions=0') { throw "Missing completion marker: $run" }
            $seen = @{}
            foreach ($line in $lines) {
                if ($line -match '^workload=([0-2]) pairs=20000 barriers=40000 record_ms=([0-9.]+)$') {
                    $workload = [int]$Matches[1]
                    $duration = [double]::Parse($Matches[2], [cultureinfo]::InvariantCulture)
                    if ($seen.ContainsKey($workload) -or [double]::IsNaN($duration) -or [double]::IsInfinity($duration) -or $duration -lt 0) { throw 'Invalid workload result.' }
                    $seen[$workload] = $true
                    $rows += @{version=$version.name;trial=$trial;workload=$workload;record_ms=$duration}
                }
            }
            if ($seen.Count -ne 3) { throw "Incomplete workloads: $run" }
            $menuLines = @(Get-Content -LiteralPath (Join-Path $run 'darktidevr-menu-resources.log'))
            if ($menuLines.Count -ne 4096) { throw 'Menu diagnostic entry budget differs.' }
            $normalized = @($menuLines | ForEach-Object {
                if ($_ -notmatch '^MENU_RESOURCE\s' -or $_ -notmatch 'name=0x0123456789abcdef$') { throw 'Unexpected diagnostic payload.' }
                $_ -replace '(?<=CL=)[0-9A-Fa-f]+', 'COMMANDS' -replace '(?<=resource=)[0-9A-Fa-f]+', 'RESOURCE'
            }) -join "`n"
            $hasher = [Security.Cryptography.SHA256]::Create()
            try { $digest = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))).Replace('-', '') }
            finally { $hasher.Dispose() }
            if ($menuDigest -and $menuDigest -ne $digest) { throw 'Diagnostic entries changed beyond process-local addresses.' }
            $menuDigest = $digest
            $process.Dispose()
            $process = $null
        }
    }
    foreach ($version in $versions) {
        if ((Get-FileHash -LiteralPath $version.source -Algorithm SHA256).Hash -ne $version.hash) { throw 'Source changed during comparison.' }
    }
    if ((Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash -ne $exeHash) { throw 'Benchmark executable changed during comparison.' }
    $summary = @()
    foreach ($workload in 0..2) {
        foreach ($version in $versions) {
            $values = @($rows | Where-Object { $_.workload -eq $workload -and $_.version -eq $version.name } | ForEach-Object record_ms | Sort-Object)
            $summary += @{workload=$workload;version=$version.name;median_ms=$values[2];minimum_ms=$values[0];maximum_ms=$values[4]}
        }
    }
    $report = @{schema_version=1;status='passed';recorded_only=$true;gpu_submissions=0;baseline_hash=$BaselineHash;candidate_hash=$CandidateHash;executable_hash=$exeHash;diagnostic_entries_per_run=4096;normalized_menu_log_sha256=$menuDigest;rows=$rows;summary=$summary}
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'comparison.json') -Encoding utf8
    $report.summary | ForEach-Object { [pscustomobject]$_ } | Format-Table workload,version,median_ms,minimum_ms,maximum_ms
} finally {
    if ($process) {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    foreach ($override in $savedOverrides) { [Environment]::SetEnvironmentVariable($override.Name, $override.Value, 'Process') }
}
