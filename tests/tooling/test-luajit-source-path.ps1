$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$gate = Join-Path $repo 'tools/lua/test-lua-syntax.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('darktidevr-lua-path-' + [guid]::NewGuid().ToString('N'))
while ($fixture.Length -lt 280) { $fixture = Join-Path $fixture ('nested-' + ('x' * 48)) }
# Retain this process-owned fixture as evidence; no recursive cleanup.
[IO.Directory]::CreateDirectory('\\?\' + $fixture) | Out-Null
$valid = Join-Path $fixture 'valid chunk.lua'
$invalid = Join-Path $fixture 'invalid chunk.lua'
[IO.File]::WriteAllText('\\?\' + $valid, 'error("The compilation gate must not execute this chunk")')
[IO.File]::WriteAllText('\\?\' + $invalid, 'local = broken')
& $gate -SourcePaths @($valid)
if ($LASTEXITCODE -ne 0) { throw 'Valid long-path source failed compilation' }
& $gate -SourcePaths @('\\?\' + $valid)
if ($LASTEXITCODE -ne 0) { throw 'Already extended source path failed compilation' }
$rejected = $false
try { & $gate -SourcePaths @($valid, $invalid) 2>&1 | Out-Null }
catch { $rejected = $_.Exception.Message -match 'LuaJIT rejected|invalid chunk.lua' }
if (-not $rejected) { throw 'Invalid companion chunk was accepted' }
Write-Output "luajit_source_path=pass path_length=$($valid.Length) compile_only=true rejects_invalid_companion=true"
