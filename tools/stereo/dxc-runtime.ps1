function Get-VerifiedDxcRuntimeFiles {
    [CmdletBinding()]
    param([string] $RuntimeRoot = (Join-Path $PSScriptRoot '../../build/dependencies/dxc-runtime'))
    $spec = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../dependencies/dxc-runtime.psd1')
    $verified = @()
    foreach ($entry in $spec.Files) {
        $source = Join-Path $RuntimeRoot $entry.Name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
                (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -ne $entry.SHA256) {
            throw "Pinned DXC runtime file is missing or changed: $($entry.Name). Prepare it with tools/dependencies/get-dxc-runtime.ps1 before building or syncing."
        }
        $verified += [pscustomobject]@{ Source=$source; InstalledName=$entry.InstalledName }
    }
    return $verified
}
