$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $repo 'tools/stereo/resolve-darktide-game-root.ps1')
$fixtureParent = [IO.Path]::GetFullPath((Join-Path $repo 'artifacts/tests'))
$fixture = Join-Path $fixtureParent ('game-root-' + [guid]::NewGuid())
function Expect-Failure([scriptblock] $Action, [string] $Pattern) {
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        return
    }
    throw "Expected rejection matching $Pattern"
}
function Write-Manifest([string] $Library, [string] $Folder, [string] $AppId = '1361210') {
    $apps = Join-Path $Library 'steamapps'
    New-Item -ItemType Directory -Path $apps -Force | Out-Null
    $escaped = $Folder.Replace('\', '\\')
    [IO.File]::WriteAllText((Join-Path $apps 'appmanifest_1361210.acf'),
        '"AppState" { "appid" "' + $AppId + '" "installdir" "' + $escaped + '" }')
}
function Add-Game([string] $Library, [string] $Folder) {
    Write-Manifest $Library $Folder
    $game = Join-Path (Join-Path $Library 'steamapps/common') $Folder
    $binaries = Join-Path $game 'binaries'
    New-Item -ItemType Directory -Path $binaries -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $binaries 'Darktide.exe'), '')
    return $game
}
try {
    $steam = Join-Path $fixture 'Steam primary'
    $library = Join-Path $fixture "Other disk's games"
    $game = Add-Game $library 'Custom Darktide folder'
    Write-Manifest $steam 'Partially installed'
    $libraryFile = Join-Path $steam 'steamapps/libraryfolders.vdf'
    $escaped = $library.Replace('\', '\\')
    [IO.File]::WriteAllText($libraryFile, '// comment' + "`n" +
        '"libraryfolders" { "0" { "path" "' + $escaped + '" "apps" { "1361210" "1" } } ' +
        '"1" { "path" "' + $escaped.ToUpperInvariant() + '" } }')
    if ((Resolve-DarktideGameRoot -SteamRoots @($steam, $steam)) -ne $game) { throw 'Modern secondary library discovery failed.' }
    [IO.File]::WriteAllText($libraryFile, '"LibraryFolders" { "1" "' + $escaped + '" }')
    if ((Resolve-DarktideGameRoot -SteamRoots @($steam)) -ne $game) { throw 'Legacy library discovery failed.' }
    Expect-Failure { Resolve-DarktideGameRoot -SteamRoots @() } 'not found'
    Expect-Failure { Resolve-DarktideGameRoot -GameRoot $steam -SteamRoots @($steam) } 'does not contain'
    # Explicit selection bypasses Steam metadata and does not silently fall back.
    [IO.File]::WriteAllText($libraryFile, 'invalid metadata')
    if ((Resolve-DarktideGameRoot -GameRoot $game -SteamRoots @($steam)) -ne $game) { throw 'Explicit root was overridden.' }
    Expect-Failure { Resolve-DarktideGameRoot -SteamRoots @($steam) } 'Unsupported Steam manifest token'
    [IO.File]::WriteAllText($libraryFile, '"libraryfolders" { "0" { "path" "' + $escaped + '" } }')
    Write-Manifest $library '..\outside'
    Expect-Failure { Resolve-DarktideGameRoot -SteamRoots @($steam) } 'invalid installation folder'
    Write-Manifest $library 'Custom Darktide folder' '42'
    Expect-Failure { Resolve-DarktideGameRoot -SteamRoots @($steam) } 'invalid app identity'
    Write-Manifest $library 'Custom Darktide folder'
    $other = Add-Game $steam 'Another Darktide'
    Expect-Failure { Resolve-DarktideGameRoot -SteamRoots @($steam) } 'Multiple Darktide installations'
    if ((Resolve-DarktideGameRoot -GameRoot $game) -ne $game) { throw 'Explicit ambiguous selection failed.' }
    Remove-Item -LiteralPath (Join-Path $game 'binaries/Darktide.exe')
    if ((Resolve-DarktideGameRoot -SteamRoots @($steam)) -ne $other) { throw 'Stale manifest concealed valid installation.' }
    Remove-Item -LiteralPath (Join-Path $other 'binaries/Darktide.exe')
    Expect-Failure { Resolve-DarktideGameRoot -SteamRoots @($steam) } 'not found'
    foreach ($text in @('"x" {', '"x"', '}', '"x" "a" "x" "b"', '"x" { "y" }', '"unterminated')) {
        Expect-Failure { ConvertFrom-SteamKeyValues $text } 'Steam manifest'
    }
    $parsed = ConvertFrom-SteamKeyValues '"x" "say \"hi\""'
    if ($parsed.x -ne 'say "hi"') { throw 'Quoted string decoding failed.' }
    Write-Output 'game_root_discovery=pass modern_legacy explicit ambiguity stale_manifest malformed_metadata'
}
finally {
    # Only this newly created fixture subtree can be removed recursively.
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (-not $resolvedFixture.StartsWith($fixtureParent + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped its test directory.' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
