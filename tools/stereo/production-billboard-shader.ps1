Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

function Assert-ProductionBillboardShader {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $ShaderPath, [Parameter(Mandatory)][string] $SourcePath)
    $ErrorActionPreference = 'Stop'
    $manifestPath = Join-Path (Split-Path -Parent $ShaderPath) 'production-shader.json'
    foreach ($path in @($ShaderPath, $SourcePath, $manifestPath)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Prebuilt production shader input is missing: $path" }
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.schema_version -ne 1 -or $manifest.profile -cne 'production' -or
            $manifest.scale -ne 1 -or $manifest.zero_spin -ne 1 -or $manifest.cylindrical -ne 1) {
        throw 'Prebuilt particle shader is not the production profile.'
    }
    if ($manifest.source_sha256 -ne (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash -or
            $manifest.shader_sha256 -ne (Get-FileHash -LiteralPath $ShaderPath -Algorithm SHA256).Hash) {
        throw 'Prebuilt production shader identity mismatch; rebuild it from the current source.'
    }
}
