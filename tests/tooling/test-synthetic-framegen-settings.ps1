$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/stereo/synthetic-framegen-settings.ps1')
$source = "detected_user_settings = {`r`n`tmaster_render_settings = {`r`n`t`tdlss_g = 3`r`n`t}`r`n}`r`nmaster_render_settings = {`r`n`tdlss_g = 1`r`n`tdlss = 5`r`n}`r`nrender_settings = {`r`n`tdlss_g_enabled = true`r`n`tdlss_g_frames_to_generate = 2`r`n}`r`n"
$off = ConvertTo-SyntheticFramegenSettings -Settings $source -Enabled $false
if ($off -notmatch '(?m)^\t\tdlss_g = 3\r?$' -or $off -notmatch '(?m)^\tdlss_g = 0\r?$' -or
    $off -notmatch 'dlss_g_enabled = false' -or $off -notmatch 'dlss_g_frames_to_generate = 1' -or
    $off -notmatch '(?m)^\tdlss = 5\r?$') { throw 'Off changed unrelated settings or failed to select Off.' }
$on = ConvertTo-SyntheticFramegenSettings -Settings $off -Enabled $true
if ($on -notmatch '(?m)^\tdlss_g = 1\r?$' -or $on -notmatch 'dlss_g_enabled = true') { throw 'On failed.' }
foreach ($invalid in @($source.Replace("`tdlss_g = 1",'missing = 1'),($source+"`tdlss_g_enabled = true`r`n"))) {
    $rejected = $false
    try { ConvertTo-SyntheticFramegenSettings -Settings $invalid -Enabled $true | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Ambiguous/missing settings accepted.' }
}
$capped = $source+"`tnv_reflex_framerate_cap = 6`r`n`tnv_framerate_cap = 120`r`n`t`tnv_reflex_framerate_cap = 6`r`n"
$unlimited = ConvertTo-SyntheticFramegenSettings -Settings $capped -Enabled $true -FrameRateLimit Unlimited
if ($unlimited -notmatch '(?m)^\tnv_reflex_framerate_cap = 0\r?$' -or
    $unlimited -notmatch '(?m)^\tnv_framerate_cap = 0\r?$' -or
    $unlimited -notmatch '(?m)^\t\tnv_reflex_framerate_cap = 6\r?$') { throw 'Unlimited altered the wrong cap.' }
if ((ConvertTo-SyntheticFramegenSettings -Settings $capped -Enabled $false) -notmatch 'nv_framerate_cap = 120') { throw 'Default did not preserve cap.' }
'synthetic_framegen_settings=pass cache_preserved=1 unrelated_preserved=1 invalid_rejected=2 explicit_cap_control=1'
