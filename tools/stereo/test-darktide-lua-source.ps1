[CmdletBinding()]
param([string] $SourcePath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $SourcePath) {
    $SourcePath = Join-Path $repoRoot 'mods/darktidevr/scripts/mods/darktidevr/darktidevr.lua'
}
$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$sourceDirectory = Split-Path -Parent $resolvedSource
# The selected source belongs to <mod>/scripts/mods/darktidevr.
# Validate that same package's descriptor, not whichever checkout runs the gate.
# Missing descriptors must fail rather than borrowing a valid checkout copy.
$descriptor = (Resolve-Path -LiteralPath (Join-Path $sourceDirectory '../../../darktidevr.mod')).Path
$chunks = @($resolvedSource) + @(Get-ChildItem -LiteralPath $sourceDirectory -Filter '*.lua' -File |
    Where-Object FullName -ne $resolvedSource | ForEach-Object FullName)
$chunks += $descriptor
& (Join-Path $repoRoot 'tools/lua/test-lua-syntax.ps1') -SourcePaths $chunks
Write-Output "lua_source_check=pass compiler=LuaJIT chunks=$($chunks.Count) source=$resolvedSource descriptor=$descriptor"
