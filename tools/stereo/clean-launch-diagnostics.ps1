function Set-CleanLaunchDiagnostics {
    param([Parameter(Mandatory)][string] $ModRoot,
          [Parameter(Mandatory)][hashtable] $Saved,
          [bool] $ResourceHandleTrace = $false,
          [bool] $CopyProbe = $false, [bool] $TransportProbe = $false,
          [bool] $PerformanceProfile = $false, [bool] $PerformancePassTrace = $false)
    # Presence-gated native flags must be removed, not written as "disabled".
    $remove = @()
    if (-not $ResourceHandleTrace) { $remove += 'darktidevr_resource_handle_trace.flag' }
    if (-not $CopyProbe) { $remove += 'darktidevr_streamline_copy_probe.flag' }
    if (-not $TransportProbe) { $remove += 'darktidevr_streamline_transport_probe.flag' }
    $disable = @('darktidevr_body_ik_trace.flag','darktidevr_weapon_pose_trace.flag')
    if (-not $PerformanceProfile) { $disable += 'darktidevr_performance_profile.flag' }
    if (-not $PerformancePassTrace) { $disable += 'darktidevr_performance_pass_trace.flag' }
    foreach ($name in @($remove) + @($disable)) {
        $path = Join-Path $ModRoot $name
        if (Test-Path -LiteralPath $path -PathType Container) { throw "Diagnostic flag is a directory: $name" }
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        if (-not $exists) { continue }
        if (-not $Saved.ContainsKey($path)) { $Saved[$path] = [IO.File]::ReadAllBytes($path) }
        if ($name -in $remove) { Remove-Item -LiteralPath $path }
        else { [IO.File]::WriteAllText($path,"disabled`r`n",[Text.Encoding]::ASCII) }
    }
}

function Restore-CleanLaunchDiagnostics {
    param([Parameter(Mandatory)][hashtable] $Saved)
    $failures = @()
    foreach ($path in $Saved.Keys) {
        try { [IO.File]::WriteAllBytes($path,$Saved[$path]) }
        catch { $failures += $_.Exception.Message }
    }
    if ($failures.Count) { throw ($failures -join '; ') }
}
