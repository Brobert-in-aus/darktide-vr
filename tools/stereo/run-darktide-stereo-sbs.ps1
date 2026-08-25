[CmdletBinding()]
param(
    [ValidateRange(5, 3600)]
    [int] $DurationSeconds = 300,

    [string] $GameExe =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe',

    [string] $Harness =
        'build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe'
)

$replacement = Join-Path $PSScriptRoot 'run-darktide-shared-eyes.ps1'
Write-Warning 'This compatibility launcher was renamed to run-darktide-shared-eyes.ps1.'
& $replacement -DurationSeconds $DurationSeconds -GameExe $GameExe -Harness $Harness
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
