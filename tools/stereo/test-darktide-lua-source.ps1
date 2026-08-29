[CmdletBinding()]
param(
    [string] $SourcePath,

    [ValidateRange(1, 200)]
    [int] $MaximumFileScopeLocals = 198
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $SourcePath) {
    $SourcePath = Join-Path $repoRoot `
        'mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua'
}
$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$lines = @(Get-Content -LiteralPath $resolvedSource)

# The Darktide mod is one LuaJIT chunk. File-scope locals remain live for the
# rest of that chunk, and Lua rejects the chunk once its 200-local compiler
# ceiling is crossed. Count declarations at column zero; nested declarations
# are indented by the repository formatter and do not consume the chunk scope.
$fileScopeLocals = 0
foreach ($line in $lines) {
    if ($line -match '^local\s+function\s+[A-Za-z_][A-Za-z0-9_]*') {
        $fileScopeLocals++
        continue
    }
    if ($line -match '^local\s+(.+)$') {
        $declaration = ($Matches[1] -split '=', 2)[0]
        $names = @($declaration -split ',' | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*$' })
        $fileScopeLocals += $names.Count
    }
}
if ($fileScopeLocals -gt $MaximumFileScopeLocals) {
    throw "Lua file-scope local budget exceeded: $fileScopeLocals > $MaximumFileScopeLocals. Store new state on an existing table or split the chunk into modules."
}

# State-table members must not be initialized before the local table exists.
# This catches the exact class of load-time failure that otherwise degrades XR
# to its flat fallback while making the stereo mod appear to have launched.
$trackedTables = @('controller_observation', 'presentation')
foreach ($tableName in $trackedTables) {
    $declarationLine = $null
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^local\s+$tableName\s*=\s*{") {
            $declarationLine = $index
            break
        }
    }
    if ($null -eq $declarationLine) {
        throw "Required state table '$tableName' has no file-scope declaration."
    }
    for ($index = 0; $index -lt $declarationLine; $index++) {
        if ($lines[$index] -match "(^|[^A-Za-z0-9_])$tableName\s*\.") {
            throw "State table '$tableName' is referenced before declaration at line $($index + 1)."
        }
    }
}

$luaCompiler = Get-Command luac -ErrorAction SilentlyContinue
if ($luaCompiler) {
    & $luaCompiler.Source -p $resolvedSource
    if ($LASTEXITCODE -ne 0) {
        throw "luac rejected the stereo mod source with exit code $LASTEXITCODE"
    }
    $syntaxMode = 'luac'
}
else {
    $pnpm = Get-Command pnpm -ErrorAction SilentlyContinue
    if (-not $pnpm) {
        throw 'Neither luac nor pnpm is available for fail-closed Lua syntax validation.'
    }
    $parseOutput = @(& $pnpm.Source dlx luaparse --quiet --file `
        $resolvedSource 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $details = ($parseOutput | ForEach-Object { [string] $_ }) -join "`n"
        throw "luaparse rejected the stereo mod source:`n$details"
    }
    $syntaxMode = 'luaparse'
}

Write-Output "lua_source_check=pass file_scope_locals=$fileScopeLocals limit=$MaximumFileScopeLocals syntax=$syntaxMode source=$resolvedSource"
