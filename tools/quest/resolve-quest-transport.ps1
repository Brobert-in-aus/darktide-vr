# Read-only selection. Multiple authorized transports are accepted only when
# every one proves the same physical Quest; names alone never establish identity.
function Resolve-QuestTransport {
    param([string] $Adb, [string[]] $AuthorizedTransports)
    $result = [ordered]@{ Status='missing'; Device=$null; Model=$null;
        PhysicalQuestCount=$null; DuplicateTransports=$false }
    if (-not $AuthorizedTransports -or $AuthorizedTransports.Count -eq 0) {
        $result.PhysicalQuestCount=0
        return [pscustomobject]$result
    }
    $candidates = @()
    foreach ($transport in $AuthorizedTransports) {
        $model = (@(& $Adb -s $transport shell getprop ro.product.model) -join '').Trim()
        if ($LASTEXITCODE -ne 0) { $result.Status='model_query_failed'; return [pscustomobject]$result }
        if ($model -notmatch '^Quest(?:\s|$)') {
            $result.Status='not_quest'
            return [pscustomobject]$result
        }
        if ($AuthorizedTransports.Count -eq 1) {
            $result.Status='selected'; $result.Device=$transport; $result.Model=$model
            $result.PhysicalQuestCount=1
            return [pscustomobject]$result
        }
        $identity = (@(& $Adb -s $transport shell getprop ro.serialno) -join '').Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($identity) -or
                $identity -match '^(unknown|null|none|0+)$') {
            $result.Status='identity_query_failed'
            return [pscustomobject]$result
        }
        $candidates += [pscustomobject]@{Device=$transport; Model=$model; Identity=$identity}
    }
    $identities = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($candidate in $candidates) { [void]$identities.Add($candidate.Identity) }
    $result.PhysicalQuestCount=$identities.Count
    if ($identities.Count -ne 1) { $result.Status='ambiguous'; return [pscustomobject]$result }
    foreach ($candidate in $candidates) {
        if ($candidate.Model -cne $candidates[0].Model) {
            $result.Status='identity_conflict'
            return [pscustomobject]$result
        }
    }
    # Prefer the directly addressed serial transport when available. Otherwise
    # choose a stable alias only after every alias has proven the same device.
    $selected = @($candidates | Where-Object { $_.Device -ceq $_.Identity })
    if ($selected.Count -eq 0) {
        $names = [string[]]@($candidates.Device)
        [Array]::Sort($names, [StringComparer]::Ordinal)
        $selected = @($candidates | Where-Object { $_.Device -ceq $names[0] })
    }
    $result.Status='selected'; $result.Device=$selected[0].Device; $result.Model=$selected[0].Model
    $result.DuplicateTransports=$true
    return [pscustomobject]$result
}
