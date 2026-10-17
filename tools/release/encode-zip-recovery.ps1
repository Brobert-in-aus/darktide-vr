# Writes zip-recovery.ps1 into "Darktide VR Mode.bat" as an -EncodedCommand
# (UTF-16LE, base64): the batch file has no script beside it in that case, and
# an encoded command needs no quoting. Run after editing zip-recovery.ps1;
# tests/tooling/test-mode-switch-installer.ps1 fails when the two disagree.
param([switch] $Check)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'zip-recovery.ps1'))
# Comments and blank lines are not needed in the command, and cmd.exe limits
# a line to 8191 characters.
$code = (($source -split "`r?`n") | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }) -join "`n"
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
if ($encoded.Length -gt 7000) { throw "Encoded recovery is $($encoded.Length) characters; cmd.exe allows 8191 per line." }
$bat = Join-Path $repoRoot 'mods\darktidevr\Darktide VR Mode.bat'
$text = [IO.File]::ReadAllText($bat)
$pattern = '(?m)^(\s*powershell\.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand )\S+'
if ($text -notmatch $pattern) { throw 'The batch file has no encoded recovery line.' }
$updated = [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $encoded })
if ($Check) {
    if ($updated -ne $text) { throw 'Darktide VR Mode.bat does not carry the current zip-recovery.ps1; run tools\release\encode-zip-recovery.ps1.' }
    Write-Output "zip_recovery_encoding=current characters=$($encoded.Length)"
    exit 0
}
[IO.File]::WriteAllText($bat, $updated)
Write-Output "zip_recovery_encoding=written characters=$($encoded.Length)"
