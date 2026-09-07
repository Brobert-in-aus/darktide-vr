function Get-DarktideVrModLoadOrder {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]] $Bytes)
    # The loader uses a line-oriented byte text file. Keep all existing bytes,
    # including comments and newline style; append only the missing entry.
    if ($Bytes -contains 0) { throw 'Mod load order contains NUL bytes; use a byte-text mod list.' }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 239 -and $Bytes[1] -eq 187 -and $Bytes[2] -eq 191) {
        throw 'Mod load order has a UTF-8 BOM that the loader treats as part of its first entry.'
    }
    $text = [Text.Encoding]::UTF8.GetString($Bytes)
    $name = 'darktidevr_stereo_probe'
    # Match the loader's f:lines and ASCII Lua %s trim, not Unicode whitespace.
    $pattern = '^[ \t\v\f\r]*' + $name + '[ \t\v\f\r]*$'
    $active = @($text -split '\n' | Where-Object { $_ -cmatch $pattern })
    if (@($text -split '\n' | Where-Object { $_ -match $pattern -and $_ -cnotmatch $pattern }).Count) {
        throw 'Mod load order has a VR entry with different capitalization; use darktidevr_stereo_probe.'
    }
    if ($active.Count -gt 1) { throw 'Mod load order has duplicate active VR entries; resolve them before installation.' }
    if ($active.Count -eq 1) { return [pscustomobject]@{ Changed = $false; Bytes = $Bytes } }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } elseif ($text.Contains("`n")) { "`n" } else { [Environment]::NewLine }
    $separator = if ($text.Length -and -not $text.EndsWith("`n") -and -not $text.EndsWith("`r")) { $newline } else { '' }
    $suffix = [Text.Encoding]::ASCII.GetBytes($separator + $name + $newline)
    $updated = [byte[]]::new($Bytes.Length + $suffix.Length)
    [Array]::Copy($Bytes, 0, $updated, 0, $Bytes.Length)
    [Array]::Copy($suffix, 0, $updated, $Bytes.Length, $suffix.Length)
    return [pscustomobject]@{ Changed = $true; Bytes = $updated }
}
