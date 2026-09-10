function ConvertTo-SyntheticFramegenSettings {
    param([Parameter(Mandatory)] [string] $Settings, [Parameter(Mandatory)] [bool] $Enabled,
        [ValidateSet('Preserve','Unlimited','30','40','60','72','90','120')] [string] $FrameRateLimit = 'Preserve',
        [ValidateRange(0,16)] [int] $WorkerThreads = 0,
        [ValidateSet('Preserve','Quality','Performance')] [string] $DlssQuality = 'Preserve',
        [ValidateSet('Preserve','On','Off')] [string] $Reflex = 'Preserve')
    if ($Enabled -and $Reflex -eq 'Off') { throw 'The Reflex-off control requires frame generation off.' }
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
    if ($DlssQuality -ne 'Preserve') {
        # Require an already enabled DLSS configuration; do not switch upscalers.
        foreach ($required in @(
            '(?m)^\tdlss_enabled[ \t]*=[ \t]*true[ \t]*\r?$',
            '(?m)^\tdlss_master[ \t]*=[ \t]*"on"[ \t]*\r?$',
            '(?m)^\tupscaling_mode[ \t]*=[ \t]*"dlss"[ \t]*\r?$'
        )) {
            if ([regex]::Matches($Settings,$required).Count -ne 1) { throw 'DLSS quality trial requires active DLSS.' }
        }
        # Stock render_settings.lua maps Performance to selection 3, Quality to 5.
        $selection = if ($DlssQuality -eq 'Quality') { '5' } else { '3' }
        foreach ($change in @(
            @('(?m)^(\tdlss[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)', $selection),
            @('(?m)^(\tupscaling_quality[ \t]*=[ \t]*)"[^"]+"(?=[ \t]*\r?$)', ('"'+$DlssQuality.ToLowerInvariant()+'"'))
        )) {
            if ([regex]::Matches($Settings,$change[0]).Count -ne 1) { throw 'Expected one active DLSS quality setting.' }
            $Settings = [regex]::Replace($Settings,$change[0],'${1}'+$change[1])
        }
    }
    if ($Reflex -ne 'Preserve') {
        if ($Reflex -eq 'Off' -and [regex]::Matches($Settings,'(?m)^\treflex_warp_enabled[ \t]*=[ \t]*false[ \t]*\r?$').Count -ne 1) {
            throw 'The Reflex-off control requires Reflex Warp already disabled.'
        }
        $on = $Reflex -eq 'On'
        foreach ($change in @(
            @('(?m)^(\tnv_reflex_low_latency[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)', [string][int]$on),
            @('(?m)^(\tnv_low_latency_mode[ \t]*=[ \t]*)(true|false)(?=[ \t]*\r?$)', $on.ToString().ToLowerInvariant()),
            @('(?m)^(\tnv_low_latency_boost[ \t]*=[ \t]*)(true|false)(?=[ \t]*\r?$)', 'false')
        )) {
            if ([regex]::Matches($Settings,$change[0]).Count -ne 1) { throw 'Expected one active Reflex setting.' }
            $Settings = [regex]::Replace($Settings,$change[0],'${1}'+$change[1])
        }
    }
    return $Settings
}
