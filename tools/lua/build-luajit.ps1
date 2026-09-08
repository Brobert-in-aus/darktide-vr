[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
. (Join-Path $PSScriptRoot 'validator-hash.ps1')
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$revision = '24c20c94e7db195b640854619577441f9b4bc6be'
$checkout = Join-Path $repo 'build/dependencies/luajit'
if (-not (Test-Path $checkout)) {
    & git clone --no-checkout https://github.com/LuaJIT/LuaJIT.git $checkout
    if ($LASTEXITCODE) { throw 'LuaJIT clone failed' }
    & git -C $checkout checkout --detach $revision
    if ($LASTEXITCODE) { throw 'LuaJIT checkout failed' }
}
if ((& git -C $checkout rev-parse HEAD).Trim() -ne $revision) {
    throw 'Unexpected LuaJIT revision; restore the pinned dependency checkout.'
}
& git -C $checkout diff --quiet HEAD --
if ($LASTEXITCODE) { throw 'LuaJIT sources differ from the pinned revision.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'Visual Studio C++ tools are required' }
$vcvars = Join-Path $vs 'VC/Auxiliary/Build/vcvars64.bat'
$batch = Join-Path $checkout 'build-validator.cmd'
@"
@echo off
call "$vcvars"
if errorlevel 1 exit /b 1
cd /d "$checkout\src"
call msvcbuild.bat static
"@ | Set-Content -LiteralPath $batch -Encoding ascii
& $env:ComSpec /d /c $batch
if ($LASTEXITCODE) { throw 'LuaJIT build failed' }
$exe = Join-Path $checkout 'src/luajit.exe'
[ordered]@{ revision = $revision; sha256 = (Get-LuaValidatorHash $exe) } |
    ConvertTo-Json | Set-Content (Join-Path $checkout 'validator.json')
Write-Output "LuaJIT validator built at revision $revision"
