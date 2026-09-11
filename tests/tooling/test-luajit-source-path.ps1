$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$gate = Join-Path $repo 'tools/lua/test-lua-syntax.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('darktidevr-lua-path-' + [guid]::NewGuid().ToString('N'))
$fixture = $fixtureRoot
while ($fixture.Length -lt 280) { $fixture = Join-Path $fixture ('nested-' + ('x' * 48)) }
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

# The package gate must inspect the selected mod's descriptor, including when
# its source comes from an installed copy or a focused worktree.
$packageGate = Join-Path $repo 'tools/stereo/test-darktide-lua-source.ps1'
$packageRoot = Join-Path ([IO.Path]::GetTempPath()) ('darktidevr-lua-package-' + [guid]::NewGuid().ToString('N'))
$packageLua = Join-Path $packageRoot 'scripts/mods/darktidevr_stereo_probe'
[void][IO.Directory]::CreateDirectory($packageLua)
$entry = Join-Path $packageLua 'darktidevr_stereo_probe.lua'
$companion = Join-Path $packageLua 'companion.lua'
$descriptor = Join-Path $packageRoot 'darktidevr_stereo_probe.mod'
[IO.File]::WriteAllText($entry, 'error("Package validation must not execute Lua")')
[IO.File]::WriteAllText($companion, 'return {}')
[IO.File]::WriteAllText($descriptor, 'local = broken_descriptor')
$rejected = $false
try { & $packageGate -SourcePath $entry 2>&1 | Out-Null }
catch { $rejected = $_.Exception.Message -match 'LuaJIT rejected|darktidevr_stereo_probe\.mod' }
if (-not $rejected) { throw 'Selected package descriptor was not compiled.' }
[IO.File]::WriteAllText($descriptor, 'error("Package validation must not execute its descriptor")')
$result = & $packageGate -SourcePath $entry
if ($result -notmatch 'chunks=3 ') { throw 'Package gate did not compile the entry, companion and descriptor.' }
[IO.File]::WriteAllText($companion, 'local = broken_companion')
$rejected = $false
try { & $packageGate -SourcePath $entry 2>&1 | Out-Null }
catch { $rejected = $_.Exception.Message -match 'LuaJIT rejected|companion\.lua' }
if (-not $rejected) { throw 'Selected package companion was not compiled.' }
[IO.File]::WriteAllText($companion, 'return {}')
[IO.File]::Delete($descriptor)
$rejected = $false
try { & $packageGate -SourcePath $entry 2>&1 | Out-Null }
catch { $rejected = $true }
if (-not $rejected) { throw 'Missing package descriptor fell back to checkout state.' }
Write-Output 'luajit_package_source=pass selected_descriptor=true missing_descriptor_rejected=true compile_only=true'
# Long-path fixtures are awkward to delete by hand; remove them on success.
try { [IO.Directory]::Delete('\\?\' + $fixtureRoot, $true) } catch { }
try { [IO.Directory]::Delete($packageRoot, $true) } catch { }
