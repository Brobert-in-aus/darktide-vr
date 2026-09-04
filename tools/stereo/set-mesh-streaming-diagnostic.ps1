[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'Disable', 'Restore')]
    [string] $Action = 'Inspect',
    [string] $SettingsPath = (Join-Path $env:APPDATA 'Fatshark\Darktide\user_settings.config'),
    [string] $StatePath = (Join-Path $PSScriptRoot '..\..\artifacts\unattended\mesh-streaming-diagnostic.json')
)

# Fatshark confirms this user override at:
# https://forums.fatsharkgames.com/t/mesh-streaming-not-working-correctly/83361
# Keep this opt-in: disabling streaming may increase VRAM use and stalls.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$settingsFullPath = [IO.Path]::GetFullPath($SettingsPath)
$stateFullPath = [IO.Path]::GetFullPath($StatePath)
$settingsText = [IO.File]::ReadAllText($settingsFullPath)
$sections = [regex]::Matches($settingsText,
    '(?m)^mesh_streamer_settings[ \t]*=[ \t]*\{(?<body>[^{}]*)\}')
if ($sections.Count -ne 1) {
    throw 'Expected one flat mesh_streamer_settings section; no settings changed.'
}
$section = $sections[0]
$body = $section.Groups['body'].Value
$assignments = [regex]::Matches($body,
    '(?m)^[ \t]*disable[ \t]*=[ \t]*(?<value>true|false)[ \t]*\r?$')
if ($assignments.Count -gt 1 -or
        ([regex]::IsMatch($body, '\bdisable\s*=') -and $assignments.Count -ne 1)) {
    throw 'Ambiguous mesh-streaming override; no settings changed.'
}
$hasOverride = $assignments.Count -eq 1
$value = if ($hasOverride) { $assignments[0].Groups['value'].Value } else { $null }
if ($Action -eq 'Inspect') {
    Write-Output ('mesh_streaming.user_disable=' + $(if ($hasOverride) { $value } else { 'inherited' }))
    return
}
if (Get-Process -Name Darktide -ErrorAction SilentlyContinue) {
    throw 'Darktide is running. Apply this restart-only diagnostic after it closes.'
}
$saved = if (Test-Path -LiteralPath $stateFullPath) {
    Get-Content -LiteralPath $stateFullPath -Raw | ConvertFrom-Json
} else { $null }
if ($saved -and $saved.active -and $saved.settings_path -ne $settingsFullPath) {
    throw 'An active diagnostic belongs to another settings file.'
}
if ($Action -eq 'Disable') {
    if ($saved -and $saved.active) {
        if ($value -ne 'true') { throw 'The active override changed externally; refusing to replace it.' }
        Write-Output 'mesh_streaming.diagnostic=already_disabled'
        return
    }
    $saved = [pscustomobject]@{
        settings_path = $settingsFullPath
        had_override = $hasOverride
        original_value = $value
        active = $true
    }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($stateFullPath)) | Out-Null
    $saved | ConvertTo-Json | Set-Content -LiteralPath $stateFullPath -Encoding UTF8
    if ($hasOverride) {
        $assignment = $assignments[0].Groups['value']
        $newBody = $body.Remove($assignment.Index, $assignment.Length).Insert($assignment.Index, 'true')
    } else {
        $newline = if ($settingsText.Contains("`r`n")) { "`r`n" } else { "`n" }
        $newBody = $body.TrimEnd() + $newline + "`tdisable = true" + $newline
    }
} else {
    if (-not $saved -or -not $saved.active) { throw 'No active diagnostic state to restore.' }
    if ($value -ne 'true') { throw 'The diagnostic override changed externally; refusing to replace it.' }
    if ($saved.had_override) {
        $assignment = $assignments[0].Groups['value']
        $newBody = $body.Remove($assignment.Index, $assignment.Length).Insert(
            $assignment.Index, [string]$saved.original_value)
    } else {
        $newBody = [regex]::Replace($body, '(?m)^[ \t]*disable[ \t]*=[ \t]*true[ \t]*(?:\r?\n|$)', '')
    }
}
# Restore only the override, preserving other settings and calibration edits.
$bodyStart = $section.Groups['body'].Index
$updated = $settingsText.Remove($bodyStart, $body.Length).Insert($bodyStart, $newBody)
[IO.File]::WriteAllText($settingsFullPath, $updated, [Text.UTF8Encoding]::new($false))
if ($Action -eq 'Restore') {
    $saved.active = $false
    $saved | ConvertTo-Json | Set-Content -LiteralPath $stateFullPath -Encoding UTF8
}
Write-Output ('mesh_streaming.diagnostic=' + $Action.ToLowerInvariant())
