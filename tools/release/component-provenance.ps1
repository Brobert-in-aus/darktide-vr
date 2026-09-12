# Receipts are build records, not signatures or proof of reproducible output.
function Assert-ComponentProvenance {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Receipt,
          [Parameter(Mandatory)][object[]] $Files,
          # Package-relative paths of project-built payloads; every one must be
          # covered. The default matches the project binaries by file name.
          [string[]] $ProjectBinaries)
    if ($Receipt.schema_version -ne 1 -or $Receipt.kind -cne 'component_build_records') {
        throw 'Unsupported component provenance receipt.'
    }
    $payload = @{}
    foreach ($file in $Files) { $payload[[string]$file.path] = $file }
    $covered = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (@($Receipt.components).Count -eq 0) { throw 'Component provenance is empty.' }
    foreach ($component in $Receipt.components) {
        if ([string]$component.name -notmatch '^[a-z][a-z0-9_-]{0,63}$' -or
                [string]$component.source_revision -notmatch '^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$' -or
                $component.source_dirty -isnot [bool] -or $component.source_dirty) {
            throw 'Component provenance requires a named, clean source revision.'
        }
        foreach ($field in @('build_command', 'toolchain', 'build_options', 'dependencies')) {
            if ([string]::IsNullOrWhiteSpace([string]$component.$field)) {
                throw "Component provenance is missing $field."
            }
        }
        if (@($component.files).Count -eq 0) { throw 'Component has no payload files.' }
        foreach ($entry in $component.files) {
            $relative = [string]$entry.path
            if (-not $payload.ContainsKey($relative) -or -not $covered.Add($relative) -or
                    [string]$entry.sha256 -notmatch '^[0-9a-fA-F]{64}$' -or
                    $entry.sha256 -ine $payload[$relative].sha256) {
                throw "Component provenance has an unknown, duplicate or mismatched payload: $relative"
            }
        }
    }
    # These are project-built payloads. Third-party binaries have their own
    # pinned dependency checks; they must not inherit the packaging revision.
    foreach ($file in $Files) {
        $isProjectBinary = if ($ProjectBinaries) { $ProjectBinaries -icontains [string]$file.path }
            else { $file.path -match '(^|[\\/])(darktidevr_native_capture\.dll|d3d12\.dll|darktidevr-xr-harness\.exe)$' }
        if ($isProjectBinary -and -not $covered.Contains([string]$file.path)) {
            throw "Project binary lacks a component build record: $($file.path)"
        }
    }
}
