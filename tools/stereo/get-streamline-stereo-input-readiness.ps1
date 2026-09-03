function Get-StreamlineStereoInputReadiness {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [object[]] $ResourceTags = @()
    )

    $requiredTypes = @(
        'depth',
        'hudless_color',
        'motion_vectors',
        'scaling_input_color',
        'scaling_output_color'
    )
    $eye0Tags = @($ResourceTags | Where-Object armed_eye -eq '0')
    $eye1Tags = @($ResourceTags | Where-Object armed_eye -eq '1')
    $missingEye0Types = @()
    $missingEye1Types = @()
    $aliasedTypes = @()

    foreach ($typeName in $requiredTypes) {
        $eye0Native = @($eye0Tags |
            Where-Object type_name -eq $typeName |
            Select-Object -ExpandProperty native -Unique)
        $eye1Native = @($eye1Tags |
            Where-Object type_name -eq $typeName |
            Select-Object -ExpandProperty native -Unique)
        if ($eye0Native.Count -eq 0) {
            $missingEye0Types += $typeName
        }
        if ($eye1Native.Count -eq 0) {
            $missingEye1Types += $typeName
        }
        if (@($eye0Native | Where-Object { $eye1Native -contains $_ }).Count -gt 0) {
            $aliasedTypes += $typeName
        }
    }

    $blockers = @()
    if ($missingEye0Types.Count -gt 0) {
        $blockers += 'missing_eye0'
    }
    if ($missingEye1Types.Count -gt 0) {
        $blockers += 'missing_eye1'
    }
    if ($aliasedTypes.Count -gt 0) {
        $blockers += 'cross_eye_aliasing'
    }

    [pscustomobject]@{
        RequiredTypes = $requiredTypes
        MissingEye0Types = $missingEye0Types
        MissingEye1Types = $missingEye1Types
        AliasedTypes = $aliasedTypes
        Blockers = $blockers
        Ready = $blockers.Count -eq 0
    }
}
