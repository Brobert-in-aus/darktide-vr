[CmdletBinding()]
param(
    [string] $GameRoot =
        'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE',

    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',

    [switch] $ParticleHorizonLock,

    [switch] $ParticleDiagnosticMagenta,

    [switch] $DiagnosticRenderHooks,

    [bool] $BillboardShaderSubstitution = $true,

    [switch] $VertexShaderDump
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Darktide must be fully closed before synchronizing development files.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$gameRootPath = (Resolve-Path -LiteralPath $GameRoot).Path
$modRoot = Join-Path $gameRootPath 'mods\darktidevr_stereo_probe'
$sourceLua = Join-Path $repoRoot `
    'mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
$sourceLuaRoot = Split-Path -Parent $sourceLua
$sourceNative = Join-Path $repoRoot `
    "build\windows-vs2022\src\producer\$Configuration\darktidevr_native_capture.dll"
$luaSourceCheck = Join-Path $PSScriptRoot 'test-darktide-lua-source.ps1'
if (-not (Test-Path -LiteralPath $luaSourceCheck -PathType Leaf)) {
    throw "Lua source check not found: $luaSourceCheck"
}
& $luaSourceCheck -SourcePath $sourceLua
$destinations = @(
    [pscustomobject]@{
        Source = $sourceLua
        Destination = Join-Path $modRoot `
            'scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
    },
    [pscustomobject]@{
        Source = $sourceNative
        Destination = Join-Path $modRoot 'bin\darktidevr_native_capture.dll'
    },
    [pscustomobject]@{
        Source = $sourceNative
        Destination = Join-Path $gameRootPath `
            'binaries\darktidevr_native_capture.dll'
    }
)

# Required Lua modules are separate LuaJIT chunks, which keeps the production
# probe below its hard local-variable ceiling. Deploy and syntax-check every
# module alongside the entry chunk so a clean game install cannot retain stale
# calibration code.
$luaParser = Get-Command pnpm -ErrorAction SilentlyContinue
if (-not $luaParser) {
    throw 'pnpm is required to validate Darktide VR Lua modules.'
}
$moduleFiles = Get-ChildItem -LiteralPath $sourceLuaRoot -Filter '*.lua' |
    Where-Object FullName -ne $sourceLua
foreach ($moduleFile in $moduleFiles) {
    & $luaParser.Source dlx luaparse --quiet --file $moduleFile.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "luaparse rejected Darktide VR module: $($moduleFile.FullName)"
    }
    $destinations += [pscustomobject]@{
        Source = $moduleFile.FullName
        Destination = Join-Path (Split-Path -Parent $destinations[0].Destination) `
            $moduleFile.Name
    }
}

$billboardShaderDestination = Join-Path $modRoot 'bin\billboard_shaders'
$billboardVertexSource = Join-Path $repoRoot `
    'build\generated\billboard_shaders\vs-42e436fb1ef1b392.dxil'
$billboardPixelDiagnosticDestination = Join-Path $billboardShaderDestination `
    'ps-6020f2548f29fd47.dxil'
if ($BillboardShaderSubstitution -and -not $ParticleHorizonLock) {
    # An ordinary production sync must be self-contained.  Previously the
    # bootstrap flag was enabled while the replacement shader was copied only
    # by an explicit diagnostic switch, allowing a clean install to run stock
    # spherical particles or retain a prior 10x diagnostic vertex shader.
    $buildHorizonLock = Join-Path $PSScriptRoot `
        'build-particle-horizon-lock.ps1'
    if (-not (Test-Path -LiteralPath $buildHorizonLock -PathType Leaf)) {
        throw "Particle horizon-lock build script not found: $buildHorizonLock"
    }
    & $buildHorizonLock
}
if ($BillboardShaderSubstitution) {
    $destinations += [pscustomobject]@{
        Source = $billboardVertexSource
        Destination = Join-Path $billboardShaderDestination `
            'vs-42e436fb1ef1b392.dxil'
    }
}
if ($ParticleDiagnosticMagenta) {
    $destinations += [pscustomobject]@{
        Source = Join-Path $repoRoot `
            'build\generated\billboard_shaders\ps-6020f2548f29fd47.dxil'
        Destination = Join-Path $billboardShaderDestination `
            'ps-6020f2548f29fd47.dxil'
    }
}

foreach ($entry in $destinations) {
    if (-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)) {
        throw "Development source file not found: $($entry.Source)"
    }
    $destinationParent = Split-Path -Parent $entry.Destination
    if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
        throw "Installed Darktide VR directory not found: $destinationParent"
    }
}

foreach ($entry in $destinations) {
    Copy-Item -LiteralPath $entry.Source -Destination $entry.Destination -Force
    $sourceHash = (Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $entry.Destination `
        -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "Development deployment hash mismatch: $($entry.Destination)"
    }
    Write-Output "Synchronized $($entry.Destination) sha256=$sourceHash"
}

# Magenta is an ownership diagnostic, never a production default.  Remove its
# exact deployed shader when the current sync did not request it so a prior
# colour-search run cannot leak into later launches.
if (-not $ParticleDiagnosticMagenta -and
        (Test-Path -LiteralPath $billboardPixelDiagnosticDestination `
            -PathType Leaf)) {
    Remove-Item -LiteralPath $billboardPixelDiagnosticDestination -Force
    Write-Output "Removed stale particle diagnostic: $billboardPixelDiagnosticDestination"
}

# d3d12.dll loads the native capture DLL before Lua can configure it. Keep the
# bootstrap flags authoritative on every deployment so a retired diagnostic
# session cannot silently force the expensive hook set (or make Lua's
# fail-closed configuration reject the launch).
$bootstrapFlags = @(
    [pscustomobject]@{
        Path = Join-Path $modRoot 'bin\darktidevr_diagnostic_render_hooks.flag'
        Enabled = [bool] $DiagnosticRenderHooks
    },
    [pscustomobject]@{
        Path = Join-Path $modRoot 'bin\darktidevr_billboard_shader_substitution.flag'
        Enabled = $BillboardShaderSubstitution
    },
    [pscustomobject]@{
        Path = Join-Path $modRoot 'bin\darktidevr_vertex_shader_dump.flag'
        Enabled = [bool] $VertexShaderDump
    }
)
foreach ($flag in $bootstrapFlags) {
    if ($flag.Enabled) {
        if (-not (Test-Path -LiteralPath $flag.Path -PathType Leaf)) {
            New-Item -ItemType File -Path $flag.Path | Out-Null
        }
        Write-Output "Bootstrap flag enabled: $($flag.Path)"
    } elseif (Test-Path -LiteralPath $flag.Path -PathType Leaf) {
        Remove-Item -LiteralPath $flag.Path -Force
        Write-Output "Bootstrap flag removed: $($flag.Path)"
    }
}
