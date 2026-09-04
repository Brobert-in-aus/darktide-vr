[CmdletBinding()]
param([string] $SourcePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $SourcePath) {
    $SourcePath = Join-Path $repoRoot 'mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua'
}
$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$chunks = @($resolvedSource) + @(Get-ChildItem (Split-Path $resolvedSource) -Filter '*.lua' |
    Where-Object FullName -ne $resolvedSource | ForEach-Object FullName)
$chunks += Join-Path $repoRoot 'mods/darktidevr_stereo_probe/darktidevr_stereo_probe.mod'
& (Join-Path $repoRoot 'tools/lua/test-lua-syntax.ps1') -SourcePaths $chunks
Write-Output "lua_source_check=pass compiler=LuaJIT chunks=$($chunks.Count) source=$resolvedSource"
