[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Apply', 'Inspect', 'Restore')]
    [string] $Action,

    [string] $SettingsPath = (Join-Path $env:APPDATA 'Fatshark\Darktide\user_settings.config'),

    [string] $BackupPath = (Join-Path $PSScriptRoot '..\..\artifacts\phase1\render-settings\user_settings.pre-vr.config')
)

$ErrorActionPreference = 'Stop'
$resolvedSettingsPath = [System.IO.Path]::GetFullPath($SettingsPath)
$resolvedBackupPath = [System.IO.Path]::GetFullPath($BackupPath)

$vrSettings = [ordered]@{
    # "low" still expands to enabled AO/GTAO and baked DDGI at startup.
    ambient_occlusion_quality           = '"off"'
    gi_quality                          = '"off"'
    light_quality                       = '"low"'
    ssr_quality                         = '"off"'
    texture_quality                     = '"low"'
    volumetric_fog_quality              = '"low"'
    dof_quality                         = '"off"'
    lens_flare_quality                  = '"off"'
    bloom_enabled                       = 'false'
    display_noise_enabled               = 'false'
    dof_enabled                         = 'false'
    dof_high_quality                    = 'false'
    lens_flares_enabled                 = 'false'
    lens_quality_color_fringe_enabled   = 'false'
    lens_quality_distortion_enabled     = 'false'
    lens_quality_enabled                = 'false'
    light_shafts_enabled                = 'false'
    motion_blur_enabled                 = 'false'
    sharpen_enabled                     = 'false'
    sun_flare_enabled                   = 'false'
    ui_bloom_enabled                    = 'false'
    ao_enabled                          = 'false'
    baked_ddgi                          = 'false'
    decals_enabled                      = 'false'
    gtao_enabled                        = 'false'
    gtao_quality                        = '0'
    local_lights_max_dynamic_shadow_distance = '0'
    local_lights_max_non_shadow_casting_distance = '0'
    local_lights_max_static_shadow_distance = '0'
    local_lights_shadow_map_filter_quality = '"low"'
    local_lights_shadows_enabled        = 'false'
    lod_object_multiplier               = '0.5'
    lod_scatter_density                 = '0.25'
    particles_capacity_multiplier       = '0.5'
    particles_simulation_lod            = '1'
    rough_transparency_enabled          = 'false'
    rt_light_quality                    = '"low"'
    skin_material_enabled               = 'false'
    ssr_enabled                         = 'false'
    ssr_high_quality                    = 'false'
    static_sun_shadows                  = 'false'
    sun_shadow_map_filter_quality       = '"low"'
    sun_shadows                         = 'false'
    terrain_displacement_max_distance   = '0'
    terrain_displacement_min_distance   = '0'
    terrain_tesselation_max_distance    = '0'
    terrain_tesselation_min_distance    = '0'
    # Preserve the lowest-cost DLSS mode for the initial dual-render profile.
    # Its temporal shimmer is tracked separately from the performance gate.
    upscaling_quality                   = '"ultra_performance"'
    volumetric_extrapolation_high_quality = 'false'
    volumetric_lighting_local_lights    = 'false'
    volumetric_volumes_enabled          = 'false'
    max_blood_decals                    = '0'
    max_footstep_decals                 = '0'
    max_impact_decals                   = '0'
    max_ragdolls                        = '0'
}

# Darktide stores this selector in both launcher and in-game master sections.
$vrMultiSettings = [ordered]@{
    graphics_quality = '"custom"'
}

function Get-SettingValue {
    param(
        [Parameter(Mandatory = $true)] [string] $Text,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    $matches = [regex]::Matches($Text, "(?m)^\s*$([regex]::Escape($Name))\s*=\s*(?<value>[^\r\n]+)\s*$")
    if ($matches.Count -ne 1) {
        throw "Expected exactly one '$Name' assignment, found $($matches.Count)."
    }

    return $matches[0].Groups['value'].Value.Trim()
}

function Show-Settings {
    param([Parameter(Mandatory = $true)] [string] $Text)

    foreach ($entry in $vrSettings.GetEnumerator()) {
        $actual = Get-SettingValue -Text $Text -Name $entry.Key
        [pscustomobject]@{
            Setting = $entry.Key
            Current = $actual
            VrValue = $entry.Value
            Matches = ($actual -ceq $entry.Value)
        }
    }


    foreach ($entry in $vrMultiSettings.GetEnumerator()) {
        $matches = [regex]::Matches($Text, "(?m)^\s*$([regex]::Escape($entry.Key))\s*=\s*(?<value>[^\r\n]+)\s*$")
        if ($matches.Count -lt 1) {
            throw "Expected at least one '$($entry.Key)' assignment."
        }

        $actualValues = @($matches | ForEach-Object { $_.Groups['value'].Value.Trim() })
        [pscustomobject]@{
            Setting = $entry.Key
            Current = $actualValues -join ', '
            VrValue = $entry.Value
            Matches = (($actualValues | Where-Object { $_ -cne $entry.Value }).Count -eq 0)
        }
    }
}

if ($Action -eq 'Restore') {
    if (-not (Test-Path -LiteralPath $resolvedBackupPath -PathType Leaf)) {
        throw "No saved render-settings backup exists at '$resolvedBackupPath'."
    }

    $runningGame = Get-Process -Name 'Darktide' -ErrorAction SilentlyContinue
    if ($runningGame) {
        throw 'Darktide is running. Close it before restoring user settings.'
    }

    Copy-Item -LiteralPath $resolvedBackupPath -Destination $resolvedSettingsPath -Force
    Write-Host "Restored the exact pre-VR settings from '$resolvedBackupPath'."
    exit 0
}

if (-not (Test-Path -LiteralPath $resolvedSettingsPath -PathType Leaf)) {
    throw "Darktide user settings were not found at '$resolvedSettingsPath'."
}

$settingsText = [System.IO.File]::ReadAllText($resolvedSettingsPath)

if ($Action -eq 'Inspect') {
    Show-Settings -Text $settingsText | Format-Table -AutoSize
    exit 0
}

$runningGame = Get-Process -Name 'Darktide' -ErrorAction SilentlyContinue
if ($runningGame) {
    throw 'Darktide is running. Close it before applying the VR render profile.'
}

if (-not (Test-Path -LiteralPath $resolvedBackupPath -PathType Leaf)) {
    $backupDirectory = Split-Path -Parent $resolvedBackupPath
    New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    Copy-Item -LiteralPath $resolvedSettingsPath -Destination $resolvedBackupPath
    Write-Host "Saved the exact pre-VR settings to '$resolvedBackupPath'."
}

foreach ($entry in $vrSettings.GetEnumerator()) {
    [void] (Get-SettingValue -Text $settingsText -Name $entry.Key)
    $pattern = "(?m)^(?<indent>\s*)$([regex]::Escape($entry.Key))\s*=\s*[^\r\n]+$"
    $replacement = '${indent}' + $entry.Key + ' = ' + $entry.Value
    $settingsText = [regex]::Replace($settingsText, $pattern, $replacement)
}


foreach ($entry in $vrMultiSettings.GetEnumerator()) {
    $pattern = "(?m)^(?<indent>\s*)$([regex]::Escape($entry.Key))\s*=\s*[^\r\n]+$"
    if (-not [regex]::IsMatch($settingsText, $pattern)) {
        throw "Expected at least one '$($entry.Key)' assignment."
    }

    $replacement = '${indent}' + $entry.Key + ' = ' + $entry.Value
    $settingsText = [regex]::Replace($settingsText, $pattern, $replacement)
}

$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($resolvedSettingsPath, $settingsText, $utf8WithoutBom)

$result = Show-Settings -Text ([System.IO.File]::ReadAllText($resolvedSettingsPath))
if ($result.Matches -contains $false) {
    throw 'The VR render profile did not verify after writing.'
}

$result | Format-Table -AutoSize
Write-Host 'Applied the reversible VR render profile.'
Write-Host "Restore later with: $PSCommandPath -Action Restore"
