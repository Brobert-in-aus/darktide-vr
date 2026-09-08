[CmdletBinding()]
param([Parameter(Mandatory)][string[]] $SourcePaths)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
. (Join-Path $PSScriptRoot 'validator-hash.ps1')
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dependency = Join-Path $repo 'build/dependencies/luajit'
$exe = Join-Path $dependency 'src/luajit.exe'
$stamp = Join-Path $dependency 'validator.json'
if (-not (Test-Path $exe) -or -not (Test-Path $stamp)) {
    throw 'Build the pinned compiler first: tools/lua/build-luajit.ps1'
}
$identity = Get-Content $stamp -Raw | ConvertFrom-Json
if ($identity.revision -ne '24c20c94e7db195b640854619577441f9b4bc6be' -or
    $identity.sha256 -ne (Get-LuaValidatorHash $exe)) {
    throw 'LuaJIT compiler identity mismatch; rebuild the pinned validator.'
}
& $exe (Join-Path $PSScriptRoot 'compile.lua') @SourcePaths
if ($LASTEXITCODE -ne 0) { throw 'LuaJIT rejected a source chunk' }
