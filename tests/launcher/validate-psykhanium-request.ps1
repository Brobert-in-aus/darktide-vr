$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/stereo/psykhanium-launch-request.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('dtvr-range-request-' + [guid]::NewGuid())
$directory = Join-Path $fixture 'mods/darktidevr'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$path = Join-Path $directory 'darktidevr_enter_psykhanium.flag'
try {
    Set-Content -LiteralPath $path -Value 'enter' # Stale older launch.
    $hub = Set-PsykhaniumLaunchRequest -GameRoot $fixture -Action disabled
    if ((Get-Content -LiteralPath $path -Raw).Contains('enter')) { throw 'Hub inherited range entry.' }
    $range = Set-PsykhaniumLaunchRequest -GameRoot $fixture -Action enter
    Clear-PsykhaniumLaunchRequest $hub # Late cleanup must preserve the newer request.
    if ((Get-Content -LiteralPath $path -Raw).Trim() -ne $range.Content) { throw 'Older cleanup deleted newer range request.' }
    $hub2 = Set-PsykhaniumLaunchRequest -GameRoot $fixture -Action disabled
    Clear-PsykhaniumLaunchRequest $range
    if ((Get-Content -LiteralPath $path -Raw).Trim() -ne $hub2.Content) { throw 'Older range cleanup altered hub request.' }
    Clear-PsykhaniumLaunchRequest $hub2
    if (Test-Path -LiteralPath $path) { throw 'Hub cleanup restored stale command.' }
    $range2 = Set-PsykhaniumLaunchRequest -GameRoot $fixture -Action enter
    Set-Content -LiteralPath $path -Value consumed
    Clear-PsykhaniumLaunchRequest $range2
    if (Test-Path -LiteralPath $path) { throw 'Consumed request was resurrected.' }
    Write-Output 'psykhanium_request=pass stale hub range ownership cleanup'
} finally {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    Remove-Item -LiteralPath $directory
    Remove-Item -LiteralPath (Join-Path $fixture 'mods')
    Remove-Item -LiteralPath $fixture
}
