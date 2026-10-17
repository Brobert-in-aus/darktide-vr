# Source of the -EncodedCommand in "Darktide VR Mode.bat" (regenerate it with
# tools\release\encode-zip-recovery.ps1 after editing). It runs when the batch
# file was opened from inside the zip: Windows copied only the batch file to
# <TEMP>\<id>_<zip name>.zip.<x>\mods\darktidevr\. The zip is found by that
# name, extracted, and the installer in it runs. Exit 2: not that layout;
# 3: the zip was not found.
$ProgressPreference = 'SilentlyContinue'
$here = $env:DTVR_HERE
if ($here -notmatch '\\[0-9a-fA-F-]{36}_([^\\]+\.zip)\.[^\\]+\\mods\\darktidevr\\?$') { exit 2 }
$name = $Matches[1]
$roots = @()
if ($env:DTVR_ZIP_SEARCH) { $roots = @($env:DTVR_ZIP_SEARCH -split ';') } else {
    try { $roots += (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
    $roots += @((Join-Path $env:USERPROFILE 'Downloads'), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'))
}
$zip = $roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -Filter $name -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
} | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $zip) { exit 3 }
Write-Output "Installing from $($zip.FullName)"
$out = Join-Path $env:TEMP ('darktidevr-install-' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $out
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $out 'mods\darktidevr\darktidevr-install.ps1')
$code = $LASTEXITCODE
Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
exit $code
