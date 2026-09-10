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
foreach($selection in @(@('30',1),@('40',2),@('60',3),@('72',4),@('90',5),@('120',6))) {
    $limited = ConvertTo-SyntheticFramegenSettings -Settings $capped -Enabled $true -FrameRateLimit $selection[0]
    if($limited -notmatch ('(?m)^\tnv_reflex_framerate_cap = '+$selection[1]+'\r?$') -or
       $limited -notmatch ('(?m)^\tnv_framerate_cap = '+$selection[0]+'\r?$') -or
       $limited -notmatch '(?m)^\t\tnv_reflex_framerate_cap = 6\r?$') { throw 'Explicit cap mapping failed.' }
}
'synthetic_framegen_settings=pass cache_preserved=1 unrelated_preserved=1 invalid_rejected=2 explicit_cap_control=1'
$workers = $source + "max_worker_threads = 13`r`n`tmax_worker_threads = 13`r`n"
$limitedWorkers = ConvertTo-SyntheticFramegenSettings -Settings $workers -Enabled $false -WorkerThreads 8
if ($limitedWorkers -notmatch '(?m)^max_worker_threads = 8\r?$' -or
    $limitedWorkers -notmatch '(?m)^\tmax_worker_threads = 13\r?$') { throw 'Worker trial changed the detected cache or failed.' }
if ((ConvertTo-SyntheticFramegenSettings -Settings $workers -Enabled $false) -notmatch '(?m)^max_worker_threads = 13\r?$') { throw 'Worker default was not preserved.' }
foreach ($invalid in @($source,($workers+"max_worker_threads = 8`r`n"))) {
    $rejected = $false
    try { ConvertTo-SyntheticFramegenSettings -Settings $invalid -Enabled $false -WorkerThreads 8 | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Ambiguous/missing worker setting accepted.' }
}
'synthetic_worker_settings=pass'
$dlssSource = $source + "`tdlss_enabled = true`r`n`tdlss_master = `"on`"`r`n`tupscaling_mode = `"dlss`"`r`n`tupscaling_quality = `"quality`"`r`n`t`tdlss = 5`r`n`t`tupscaling_quality = `"quality`"`r`n"
$performance = ConvertTo-SyntheticFramegenSettings -Settings $dlssSource -Enabled $false -DlssQuality Performance
if ($performance -notmatch '(?m)^\tdlss = 3\r?$' -or
    $performance -notmatch '(?m)^\tupscaling_quality = "performance"\r?$' -or
    $performance -notmatch '(?m)^\t\tdlss = 5\r?$' -or
    $performance -notmatch '(?m)^\t\tupscaling_quality = "quality"\r?$') { throw 'DLSS selection or cache preservation failed.' }
$quality = ConvertTo-SyntheticFramegenSettings -Settings $performance -Enabled $false -DlssQuality Quality
if ($quality -notmatch '(?m)^\tdlss = 5\r?$' -or $quality -notmatch '(?m)^\tupscaling_quality = "quality"\r?$') { throw 'Quality restore failed.' }
foreach ($invalid in @($source, $dlssSource.Replace('dlss_enabled = true','dlss_enabled = false'), ($dlssSource+"`tdlss = 3`r`n"))) {
    $rejected = $false
    try { ConvertTo-SyntheticFramegenSettings -Settings $invalid -Enabled $false -DlssQuality Performance | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid or ambiguous DLSS configuration accepted.' }
}
'synthetic_dlss_quality_settings=pass'
$reflexSource = $source + "`tnv_reflex_low_latency = 1`r`n`tnv_low_latency_mode = true`r`n`tnv_low_latency_boost = false`r`n`treflex_warp_enabled = false`r`n`t`tnv_reflex_low_latency = 1`r`n"
$reflexOff = ConvertTo-SyntheticFramegenSettings -Settings $reflexSource -Enabled $false -Reflex Off
if ($reflexOff -notmatch '(?m)^\tnv_reflex_low_latency = 0\r?$' -or $reflexOff -notmatch 'nv_low_latency_mode = false' -or
    $reflexOff -notmatch '(?m)^\t\tnv_reflex_low_latency = 1\r?$') { throw 'Reflex Off mapping or cache preservation failed.' }
$reflexOn = ConvertTo-SyntheticFramegenSettings -Settings $reflexOff -Enabled $false -Reflex On
if ($reflexOn -notmatch '(?m)^\tnv_reflex_low_latency = 1\r?$' -or $reflexOn -notmatch 'nv_low_latency_mode = true') { throw 'Reflex On failed.' }
foreach ($trial in @(@($reflexSource,$true),@($source,$false),@($reflexSource.Replace('reflex_warp_enabled = false','reflex_warp_enabled = true'),$false),@(($reflexSource+"`tnv_low_latency_mode = true`r`n"),$false))) {
    $rejected = $false
    try { ConvertTo-SyntheticFramegenSettings -Settings $trial[0] -Enabled $trial[1] -Reflex Off | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw 'Incompatible or ambiguous Reflex trial accepted.' }
}
'synthetic_reflex_settings=pass'
