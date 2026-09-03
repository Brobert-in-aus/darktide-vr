[CmdletBinding()]
param([Parameter(Mandatory)] [string] $Helper)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. $Helper

$requiredTypes = @(
    'depth',
    'hudless_color',
    'motion_vectors',
    'scaling_input_color',
    'scaling_output_color'
)
$distinctTags = @()
foreach ($eye in 0..1) {
    foreach ($typeName in $requiredTypes) {
        $distinctTags += [pscustomobject]@{
            armed_eye = "$eye"
            type_name = $typeName
            native = "eye${eye}_${typeName}"
        }
    }
}

$ready = Get-StreamlineStereoInputReadiness -ResourceTags $distinctTags
if (-not $ready.Ready -or $ready.Blockers.Count -ne 0 -or
        $ready.AliasedTypes.Count -ne 0) {
    throw 'Distinct complete per-eye inputs must pass readiness.'
}

$aliasedTags = @($distinctTags | ForEach-Object {
        $native = if ($_.type_name -eq 'hudless_color') {
            $_.native
        }
        else {
            "shared_$($_.type_name)"
        }
        [pscustomobject]@{
            armed_eye = $_.armed_eye
            type_name = $_.type_name
            native = $native
        }
    })
$aliased = Get-StreamlineStereoInputReadiness -ResourceTags $aliasedTags
$expectedAliases = @(
    'depth',
    'motion_vectors',
    'scaling_input_color',
    'scaling_output_color'
)
if ($aliased.Ready -or
        ($aliased.Blockers -join ',') -ne 'cross_eye_aliasing' -or
        ($aliased.AliasedTypes -join ',') -ne ($expectedAliases -join ',')) {
    throw 'Cross-eye temporal-resource aliasing must fail readiness.'
}

$missingTags = @($distinctTags | Where-Object {
        -not ($_.armed_eye -eq '1' -and $_.type_name -eq 'motion_vectors')
    })
$missing = Get-StreamlineStereoInputReadiness -ResourceTags $missingTags
if ($missing.Ready -or
        ($missing.Blockers -join ',') -ne 'missing_eye1' -or
        ($missing.MissingEye1Types -join ',') -ne 'motion_vectors') {
    throw 'A missing required eye input must fail readiness.'
}

Write-Output 'streamline_input_readiness=pass'
