param(
    [Parameter(Mandatory = $true)]
    [string] $GameRoot,

    [string] $Output
)

$ErrorActionPreference = 'Stop'
$gameRootPath = (Resolve-Path -LiteralPath $GameRoot).Path
$executable = Join-Path $gameRootPath 'binaries\Darktide.exe'
$interposer = Join-Path $gameRootPath 'binaries\sl.interposer.dll'
$d3d12Core = Join-Path $gameRootPath 'shader_cache\D3D12\D3D12Core.dll'

foreach ($requiredFile in @($executable, $interposer, $d3d12Core)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required renderer artifact not found: $requiredFile"
    }
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} `
    'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw 'Visual Studio vswhere.exe is required for the static renderer probe'
}

$dumpbinCandidates = & $vswhere -latest -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe'
$dumpbin = $dumpbinCandidates | Select-Object -Last 1
if (-not $dumpbin -or -not (Test-Path -LiteralPath $dumpbin -PathType Leaf)) {
    throw 'A Visual Studio x64 dumpbin.exe could not be located'
}

$gameImports = @(& $dumpbin /imports $executable)
$interposerExports = @(& $dumpbin /exports $interposer)
if ($LASTEXITCODE -ne 0) {
    throw "dumpbin failed with exit code $LASTEXITCODE"
}

$importedModules = @(
    $gameImports |
        ForEach-Object {
            if ($_ -match '^\s{4}([^\s]+\.dll)\s*$') { $Matches[1] }
        } |
        Sort-Object -Unique
)
$graphicsImports = @(
    $gameImports |
        ForEach-Object {
            if ($_ -match '\b(CreateDXGIFactory\d*|D3D1[12][A-Za-z0-9_]+)\s*$') {
                $Matches[1]
            }
        } |
        Sort-Object -Unique
)
$graphicsExports = @(
    $interposerExports |
        ForEach-Object {
            if ($_ -match '\b(CreateDXGIFactory\d*|DXGIGetDebugInterface1|D3D1[12][A-Za-z0-9_]+)\s*$') {
                $Matches[1]
            }
        } |
        Sort-Object -Unique
)

function Get-ArtifactRecord([string] $Path) {
    $item = Get-Item -LiteralPath $Path
    [ordered]@{
        relative_path = [IO.Path]::GetRelativePath($gameRootPath, $Path)
        size = $item.Length
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
        file_version = $item.VersionInfo.FileVersion
        product_version = $item.VersionInfo.ProductVersion
    }
}

$report = [ordered]@{
    schema_version = 1
    probe = 'read-only-pe-import-export-census'
    game_was_started = $false
    artifacts = @(
        Get-ArtifactRecord $executable
        Get-ArtifactRecord $interposer
        Get-ArtifactRecord $d3d12Core
    )
    executable_imported_modules = $importedModules
    executable_graphics_imports = $graphicsImports
    streamline_graphics_exports = $graphicsExports
    observations = @(
        'Darktide imports its D3D/DXGI creation entry points through sl.interposer.dll.'
        'IDXGISwapChain::Present is a COM method and is not expected in the PE import table.'
        'Static imports do not prove runtime call order, object ownership, hook safety, or EAC compatibility.'
    )
}

$json = $report | ConvertTo-Json -Depth 6
if ($Output) {
    $parent = Split-Path -Parent $Output
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $Output -Value $json -Encoding utf8NoBOM
} else {
    $json
}
