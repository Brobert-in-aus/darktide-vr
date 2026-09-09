[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$Library,
    [Parameter(Mandatory)][ValidatePattern('^[0-9A-Fa-f]{64}$')][string]$LibraryHash,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(3,31)][ValidateScript({ $_ % 2 -eq 1 })][int]$Trials=5
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$exe=(Resolve-Path -LiteralPath $Executable).Path
$dll=(Resolve-Path -LiteralPath $Library).Path
$exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ne $LibraryHash) { throw 'Library hash mismatch.' }
$root=[IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $root) { throw 'Output directory must be new.' }
New-Item -ItemType Directory -Path $root | Out-Null
$savedTemp=$env:TEMP
$savedTmp=$env:TMP
$savedOverrides=@(Get-ChildItem Env: | Where-Object Name -Like 'DARKTIDEVR_*')
$rows=@()
$adapter=$null
$process=$null
try {
    foreach($item in $savedOverrides) { [Environment]::SetEnvironmentVariable($item.Name,$null,'Process') }
    for($trial=0;$trial -lt $Trials;$trial++) {
        $order=if($trial%2 -eq 0){@(0,1)}else{@(1,0)}
        foreach($hooks in $order) {
            $run=Join-Path $root "hooks-$hooks-trial-$trial"
            New-Item -ItemType Directory -Path $run | Out-Null
            $copy=Join-Path $run 'darktidevr_native_capture.dll'
            Copy-Item -LiteralPath $dll -Destination $copy
            if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash -ne $LibraryHash) { throw 'Copy hash mismatch.' }
            $env:TEMP=$run
            $env:TMP=$run
            $mode=if($hooks){'--mapping'}else{'--mapping-control'}
            $stdout=Join-Path $run 'result.log'
            $process=Start-Process -FilePath $exe -ArgumentList ('"'+$copy+'" '+$mode) -WorkingDirectory $run -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError (Join-Path $run 'stderr.log')
            if (-not $process.WaitForExit(60000)) { throw 'Mapping measurement timed out.' }
            if ($process.ExitCode -ne 0) { throw "Mapping measurement failed: $run" }
            $lines=@(Get-Content -LiteralPath $stdout)
            if ($lines -notcontains 'PASS mapped_only=1 gpu_submissions=0') { throw 'Missing mapping completion marker.' }
            $identities=@($lines | Where-Object { $_ -match '^adapter_vendor=\d+ adapter_device=\d+ adapter_software=[01] driver_version=\d+$' })
            if ($identities.Count -ne 1) { throw 'Missing adapter identity.' }
            if ($adapter -and $adapter -ne $identities[0]) { throw 'Adapter or driver changed.' }
            $adapter=$identities[0]
            $seen=@{}
            foreach($line in $lines) {
                if ($line -match '^mapping_workload=([0-2]) hooks=([01]) pairs=10000 map_ms=([0-9.]+) maps=(\d+) matches=(\d+) unmaps=(\d+)$') {
                    $workload=[int]$Matches[1]
                    $elapsed=[double]::Parse($Matches[3],[cultureinfo]::InvariantCulture)
                    $expected=if($hooks){10000}else{0}
                    if ($seen.ContainsKey($workload) -or [int]$Matches[2] -ne $hooks -or
                        [double]::IsNaN($elapsed) -or [double]::IsInfinity($elapsed) -or $elapsed -lt 0 -or
                        [int]$Matches[4] -ne $expected -or [int]$Matches[5] -ne $expected -or [int]$Matches[6] -ne $expected) { throw 'Invalid mapping observation.' }
                    $seen[$workload]=$true
                    $rows+=@{hooks=$hooks;trial=$trial;workload=$workload;pairs=10000;map_ms=$elapsed}
                }
            }
            if ($seen.Count -ne 3) { throw 'Incomplete mapping workloads.' }
            $process.Dispose()
            $process=$null
        }
    }
    if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash -ne $LibraryHash -or
        (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -ne $exeHash) { throw 'Measurement inputs changed.' }
    $summary=@()
    foreach($hooks in @(0,1)) { foreach($workload in @(0,1,2)) {
        $values=@($rows | Where-Object { $_.hooks -eq $hooks -and $_.workload -eq $workload } | ForEach-Object map_ms | Sort-Object)
        $summary+=@{hooks=$hooks;workload=$workload;median_ms=$values[[int][Math]::Floor($values.Count/2)];min_ms=$values[0];max_ms=$values[-1]}
    } }
    @{schema_version=1;scope='CPU Map/Unmap calls; no GPU submission or XR session';trials=$Trials;library_sha256=$LibraryHash;executable_sha256=$exeHash;adapter=$adapter;rows=$rows;summary=$summary} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'comparison.json') -Encoding utf8
} finally {
    if ($process) { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }; $process.Dispose() }
    $env:TEMP=$savedTemp
    $env:TMP=$savedTmp
    foreach($item in $savedOverrides) { [Environment]::SetEnvironmentVariable($item.Name,$item.Value,'Process') }
}
