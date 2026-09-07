Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\stereo\get-vr-mod-load-order.ps1')
$name = 'darktidevr_stereo_probe'
foreach ($newline in @("`n", "`r`n")) {
    foreach ($tail in @('', $newline)) {
        $original = '-- User ' + [char]0x00e9 + ' comments' + $newline + '-- ' + $name + $newline + 'custom_hud' + $tail
        $bytes = [Text.Encoding]::UTF8.GetBytes($original)
        $result = Get-DarktideVrModLoadOrder -Bytes $bytes
        if (-not $result.Changed -or [Text.Encoding]::UTF8.GetString($result.Bytes) -cne
                ($original + $(if ($tail) { '' } else { $newline }) + $name + $newline)) { throw 'Append changed existing content or newline style.' }
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -ne $result.Bytes[$index]) { throw 'Original byte changed.' }
        }
        $again = Get-DarktideVrModLoadOrder -Bytes $result.Bytes
        if ($again.Changed -or ($again.Bytes -join ',') -ne ($result.Bytes -join ',')) { throw 'Repeat install changed the mod list.' }
    }
}
$empty = Get-DarktideVrModLoadOrder -Bytes ([byte[]] @())
if ([Text.Encoding]::UTF8.GetString($empty.Bytes) -ne ($name + [Environment]::NewLine)) { throw 'Empty list did not receive the VR mod.' }
$spaced = [Text.Encoding]::ASCII.GetBytes("`t$name `r`n")
if ((Get-DarktideVrModLoadOrder -Bytes $spaced).Changed) { throw 'Loader-compatible whitespace was not recognized.' }
foreach ($bad in @(
        [Text.Encoding]::ASCII.GetBytes("$name`n$name`n"),
        [Text.Encoding]::ASCII.GetBytes($name.ToUpperInvariant()),
        [byte[]] @(255, 254, 100, 0),
        [byte[]] (239, 187, 191))) {
    $failed = $false
    try { Get-DarktideVrModLoadOrder -Bytes $bad | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw 'Unsupported or ambiguous list was accepted.' }
}
Write-Output 'vr_mod_load_order=pass append_preserves_bytes newline comments duplicate case encoding repeat'
