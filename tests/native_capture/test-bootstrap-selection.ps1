param(
    [Parameter(Mandatory)][string] $Executable,
    [Parameter(Mandatory)][string] $CaptureLibrary,
    [Parameter(Mandatory)][string] $BootstrapLibrary
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$evidenceRoot = Join-Path $repoRoot ('artifacts/unattended/bootstrap-selection-' + [guid]::NewGuid().ToString('N'))
$script:caseCount = 0
function Invoke-StartupCase([int] $Mask, [string] $Text = 'enabled', [bool] $Enabled = $true) {
    $caseRoot = Join-Path $evidenceRoot ('case-' + $script:caseCount++)
    $binaries = Join-Path $caseRoot 'binaries'
    $modRoot = Join-Path $caseRoot 'mods/darktidevr_stereo_probe'
    $modBin = Join-Path $modRoot 'bin'
    [IO.Directory]::CreateDirectory($binaries) | Out-Null
    [IO.Directory]::CreateDirectory($modBin) | Out-Null
    Copy-Item -LiteralPath $Executable -Destination (Join-Path $binaries 'bootstrap-selection.exe')
    Copy-Item -LiteralPath $BootstrapLibrary -Destination (Join-Path $binaries 'd3d12.dll')
    Copy-Item -LiteralPath $CaptureLibrary -Destination (Join-Path $modBin 'darktidevr_native_capture.dll')
    $presence = @('darktidevr_diagnostic_render_hooks.flag', 'darktidevr_vertex_shader_dump.flag', 'darktidevr_billboard_shader_substitution.flag')
    for ($i = 0; $i -lt 3; $i++) {
        if ($Mask -band (1 -shl $i)) { [IO.File]::WriteAllText((Join-Path $modBin $presence[$i]), '') }
    }
    if ($Mask -band 8) { [IO.File]::WriteAllText((Join-Path $modRoot 'darktidevr_billboard_pixel_shader_probe.flag'), $Text) }
    if ($Mask -band 16) { [IO.File]::WriteAllText((Join-Path $modRoot 'darktidevr_performance_pass_trace.flag'), $Text) }
    $diagnostic = [int]([bool]($Mask -band 3) -or ([bool]($Mask -band 16) -and $Enabled))
    $dump = [int][bool]($Mask -band 2)
    $substitution = [int][bool]($Mask -band 4)
    $pixel = [int]([bool]($Mask -band 8) -and $Enabled)
    & (Join-Path $binaries 'bootstrap-selection.exe') $caseRoot $diagnostic $dump $substitution $pixel | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Bootstrap selection failed: mask=$Mask case=$caseRoot" }
}
for ($mask = 0; $mask -lt 32; $mask++) { Invoke-StartupCase $mask }
Invoke-StartupCase 24 'disabled' $false
Invoke-StartupCase 24 " `tENABLED`r`n" $true
Invoke-StartupCase 24 ('enabled' + (' ' * 24)) $true
Invoke-StartupCase 24 ('enabled' + (' ' * 25)) $false
Invoke-StartupCase 24 'enabled extra' $false
Write-Output "bootstrap_selection=pass cases=$script:caseCount real_proxy=true game_started=false"
