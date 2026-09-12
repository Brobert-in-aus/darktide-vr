param(
    [ValidateSet('Enabled', 'Disabled')]
    [string]$Mode = 'Disabled',
    [string]$GameModDirectory = 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\mods\darktidevr'
)

$ErrorActionPreference = 'Stop'
$flagPath = Join-Path $GameModDirectory 'darktidevr_performance_pass_trace.flag'
$value = if ($Mode -eq 'Enabled') { 'enabled' } else { 'disabled' }
Set-Content -LiteralPath $flagPath -Value $value -Encoding ascii

Write-Output "performance_pass_trace=$($Mode.ToLowerInvariant())"
Write-Output 'note=fresh-process diagnostic; implies GPU profiling and focused draw hooks'
Write-Output "flag=$flagPath"
