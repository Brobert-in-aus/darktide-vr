function ConvertTo-SyntheticFramegenSettings {
    param([Parameter(Mandatory)] [string] $Settings, [Parameter(Mandatory)] [bool] $Enabled,
        [ValidateSet('Preserve','Unlimited')] [string] $FrameRateLimit = 'Preserve')
    # One-tab fields belong to active settings; detected-user caches use two.
    foreach ($change in @(
        @('(?m)^(\tdlss_g[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)', [string][int]$Enabled),
        @('(?m)^(\tdlss_g_enabled[ \t]*=[ \t]*)(true|false)(?=[ \t]*\r?$)', $Enabled.ToString().ToLowerInvariant()),
        @('(?m)^(\tdlss_g_frames_to_generate[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)', '1')
    )) {
        if ([regex]::Matches($Settings,$change[0]).Count -ne 1) { throw 'Expected exactly one active frame-generation setting.' }
        $Settings = [regex]::Replace($Settings,$change[0],'${1}'+$change[1])
    }
    if ($FrameRateLimit -eq 'Unlimited') {
        foreach ($key in @('nv_reflex_framerate_cap','nv_framerate_cap')) {
            $pattern = '(?m)^(\t'+$key+'[ \t]*=[ \t]*)[0-9]+(?=[ \t]*\r?$)'
            if ([regex]::Matches($Settings,$pattern).Count -ne 1) { throw 'Expected one active frame-rate cap setting.' }
            $Settings = [regex]::Replace($Settings,$pattern,'${1}0')
        }
    }
    return $Settings
}
