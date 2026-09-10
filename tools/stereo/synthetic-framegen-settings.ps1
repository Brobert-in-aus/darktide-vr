function ConvertTo-SyntheticFramegenSettings {
    param([Parameter(Mandatory)] [string] $Settings, [Parameter(Mandatory)] [bool] $Enabled,
        [ValidateSet('Preserve','Unlimited','30','40','60','72','90','120')] [string] $FrameRateLimit = 'Preserve',
        [ValidateRange(0,16)] [int] $WorkerThreads = 0)
    # One-tab fields belong to active settings; detected-user caches use two.
    foreach ($change in @(
        @('(?m)^(\tdlss_g[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)', [string][int]$Enabled),
        @('(?m)^(\tdlss_g_enabled[ \t]*=[ \t]*)(true|false)(?=[ \t]*\r?$)', $Enabled.ToString().ToLowerInvariant()),
        @('(?m)^(\tdlss_g_frames_to_generate[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)', '1')
    )) {
        if ([regex]::Matches($Settings,$change[0]).Count -ne 1) { throw 'Expected exactly one active frame-generation setting.' }
        $Settings = [regex]::Replace($Settings,$change[0],'${1}'+$change[1])
    }
    if ($FrameRateLimit -ne 'Preserve') {
        # Keep the master UI selection and actual renderer value consistent.
        $capSelections = @{Unlimited=0; '30'=1; '40'=2; '60'=3; '72'=4; '90'=5; '120'=6}
        foreach ($key in @('nv_reflex_framerate_cap','nv_framerate_cap')) {
            $pattern = '(?m)^(\t'+$key+'[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)'
            if ([regex]::Matches($Settings,$pattern).Count -ne 1) { throw 'Expected one active frame-rate cap setting.' }
            $value = if($key -eq 'nv_reflex_framerate_cap') { $capSelections[$FrameRateLimit] }
                elseif($FrameRateLimit -eq 'Unlimited') { 0 } else { [int]$FrameRateLimit }
            $Settings = [regex]::Replace($Settings,$pattern,'${1}'+[string]$value)
        }
    }
    if ($WorkerThreads -gt 0) {
        # The active worker count is top-level; preserve detected-user cache.
        $workerPattern = '(?m)^(max_worker_threads[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)'
        if ([regex]::Matches($Settings,$workerPattern).Count -ne 1) { throw 'Expected one active worker-thread setting.' }
        $Settings = [regex]::Replace($Settings,$workerPattern,'${1}'+[string]$WorkerThreads)
    }
    return $Settings
}
