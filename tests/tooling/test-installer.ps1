param([string] $ModRoot)
# The self-locating installer (darktidevr-install.ps1) and the batch file's
# three routes: inside a game folder the mode switch, anywhere else the
# installer, and opened from inside the zip the recovery that finds the zip,
# extracts it and installs from it. Steam libraries and Xbox app games folders
# are fixtures under a temporary folder, so no real installation is touched.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if (-not $ModRoot) { $ModRoot = Join-Path $repoRoot 'mods\darktidevr' }
function Fail([string] $message) { [Console]::Error.WriteLine($message); exit 1 }

$root = Join-Path ([IO.Path]::GetTempPath()) ("darktidevr-installer-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
# An empty argument is dropped when a native process is called, so "search
# nothing" is a folder that does not exist.
$nowhere = Join-Path $root 'no-such-folder'

# A mod folder as the archive carries it: the installer, the resolver, the
# batch file, and a mode switch double that records how it was called.
function New-ModFolder([string] $Path) {
    New-Item -ItemType Directory -Path (Join-Path $Path 'tools'), (Join-Path $Path 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ModRoot 'darktidevr-install.ps1') -Destination $Path
    Copy-Item -LiteralPath (Join-Path $ModRoot 'Darktide VR Mode.bat') -Destination $Path
    Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\stereo\resolve-darktide-game-root.ps1') -Destination (Join-Path $Path 'tools')
    Set-Content -LiteralPath (Join-Path $Path 'darktidevr-mode.ps1') -Encoding ascii -Value @'
param($Mode, $GameRoot)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'mode-called.txt') -Value "mode=$Mode game=$GameRoot" -Encoding ascii
Write-Output "mode switch ran mode=$Mode"
'@
    Set-Content -LiteralPath (Join-Path $Path 'scripts\marker.lua') -Value 'return 1' -Encoding ascii
}
function New-Game([string] $Path, [switch] $Store, [switch] $NoLoader) {
    New-Item -ItemType Directory -Path (Join-Path $Path 'binaries'), (Join-Path $Path 'mods') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Path 'binaries\Darktide.exe') -Value 'exe' -Encoding ascii
    if ($Store) { Set-Content -LiteralPath (Join-Path $Path 'MicrosoftGame.config') -Value '<Game/>' -Encoding ascii }
    if (-not $NoLoader) {
        New-Item -ItemType Directory -Path (Join-Path $Path 'mods\dmf') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Path 'mods\mod_load_order.txt') -Value 'dmf' -Encoding ascii
    }
}
function Invoke-Installer([string] $Source, [string[]] $Steam, [string[]] $Drives, [string[]] $Answers) {
    $ErrorActionPreference = 'Continue'
    try {
        $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Source 'darktidevr-install.ps1'),
            '-SkipAppx', '-SteamRoots') + @($(if ($Steam) { $Steam -join ';' } else { $nowhere })) + @('-DriveRoots') +
            @($(if ($Drives) { $Drives -join ';' } else { $nowhere }))
        if ($Answers) { $arguments += @('-Answers', ($Answers -join ';')) }
        $lines = @(& powershell.exe @arguments 2>&1 | ForEach-Object { "$_" })
        return @{ exit = $LASTEXITCODE; lines = $lines }
    } finally { $ErrorActionPreference = 'Stop' }
}

try {
    # Steam: a registered library with the app manifest, as Steam writes them.
    $steamRoot = Join-Path $root 'Steam'
    $library = Join-Path $root 'SteamLibrary'
    New-Item -ItemType Directory -Path (Join-Path $steamRoot 'steamapps'), (Join-Path $library 'steamapps\common') -Force | Out-Null
    $escaped = $library.Replace('\', '\\')
    Set-Content -LiteralPath (Join-Path $steamRoot 'steamapps\libraryfolders.vdf') -Encoding ascii -Value @"
"libraryfolders"
{
	"0"
	{
		"path"		"$escaped"
	}
}
"@
    Set-Content -LiteralPath (Join-Path $library 'steamapps\appmanifest_1361210.acf') -Encoding ascii -Value @'
"AppState"
{
	"appid"		"1361210"
	"installdir"		"Warhammer 40,000 DARKTIDE"
}
'@
    $steamGame = Join-Path $library 'steamapps\common\Warhammer 40,000 DARKTIDE'
    New-Game $steamGame

    # Microsoft Store / Game Pass: one drive with the default XboxGames folder,
    # one with a custom folder named only by its .GamingRoot.
    $driveA = Join-Path $root 'driveA'
    $storeGame = Join-Path $driveA 'XboxGames\Warhammer 40,000- DARKTIDE\Content'
    New-Game $storeGame -Store
    $driveB = Join-Path $root 'driveB'
    $customGame = Join-Path $driveB 'Games\Xbox\Warhammer 40,000- DARKTIDE\Content'
    New-Game $customGame -Store
    $gamingRoot = [byte[]](0x52, 0x47, 0x42, 0x58, 1, 0, 0, 0) + [Text.Encoding]::Unicode.GetBytes("Games\Xbox`0")
    [IO.File]::WriteAllBytes((Join-Path $driveB '.GamingRoot'), $gamingRoot)
    # A game folder without the Store's config is not a Store install.
    New-Game (Join-Path $driveA 'XboxGames\Something Else\Content')

    $source = Join-Path $root 'Downloads\darktidevr-extracted\mods\darktidevr'
    New-ModFolder $source

    # Steam alone: found, confirmed, copied, switched to VR with its root.
    $one = Invoke-Installer $source @($steamRoot) @() @('y')
    if ($one.exit -ne 0 -or -not ($one.lines -match 'Found Darktide \(Steam\)')) { Fail "Steam install not found: $($one.lines -join ' | ')" }
    if (-not (Test-Path -LiteralPath (Join-Path $steamGame 'mods\darktidevr\scripts\marker.lua'))) { Fail 'The mod was not copied into the Steam game' }
    $called = Get-Content -LiteralPath (Join-Path $steamGame 'mods\darktidevr\mode-called.txt') -Raw
    if ($called.Trim() -ne "mode=vr game=$steamGame") { Fail "The installed mode switch was not run for VR: $called" }

    # Both stores: listed, and the chosen one gets it.
    $many = Invoke-Installer $source @($steamRoot) @($driveA, $driveB) @('3')
    $listed = @($many.lines | Where-Object { $_ -match '^\s+\d\s' })
    if ($listed.Count -ne 3) { Fail "Expected three installations listed: $($many.lines -join ' | ')" }
    if (-not ($many.lines -match 'Microsoft Store / Game Pass: .*driveB')) { Fail 'The .GamingRoot folder was not searched' }
    if ($many.exit -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $customGame 'mods\darktidevr\mode-called.txt'))) {
        Fail "The chosen Store install did not get the mod: $($many.lines -join ' | ')" }

    # A refused confirmation, a choice out of range: nothing installed.
    $storeOnly = Invoke-Installer $source @() @($driveA) @('n')
    if ($storeOnly.exit -eq 0 -or (Test-Path -LiteralPath (Join-Path $storeGame 'mods\darktidevr'))) { Fail 'A refused install still installed' }
    if ((Invoke-Installer $source @($steamRoot) @($driveA) @('7')).exit -eq 0) { Fail 'An out-of-range choice installed' }

    # Nothing found: a typed folder is used; a wrong one is refused.
    $typedGame = Join-Path $root 'Elsewhere\Darktide'
    New-Game $typedGame
    $typed = Invoke-Installer $source @() @() @($typedGame)
    if ($typed.exit -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $typedGame 'mods\darktidevr\mode-called.txt'))) { Fail "A typed game folder was not used: $($typed.lines -join ' | ')" }
    if ((Invoke-Installer $source @() @() @((Join-Path $root 'nowhere'))).exit -eq 0) { Fail 'A folder without Darktide was accepted' }

    # No mod loader: refused before anything is copied.
    $bare = Join-Path $root 'Bare\Darktide'
    New-Game $bare -NoLoader
    $refused = Invoke-Installer $source @() @() @($bare)
    if ($refused.exit -eq 0 -or -not ($refused.lines -match 'Mod Loader') -or (Test-Path -LiteralPath (Join-Path $bare 'mods\darktidevr'))) {
        Fail "An install without the mod loader went ahead: $($refused.lines -join ' | ')" }

    # The batch file's routes. Each run answers its prompts from a file.
    function Invoke-Bat([string] $Bat, [string] $Typed, [hashtable] $Environment = @{}) {
        $in = Join-Path $root 'bat-input.txt'
        [IO.File]::WriteAllText($in, $Typed + "`r`n`r`n`r`n")
        $saved = @{}
        foreach ($key in $Environment.Keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key); [Environment]::SetEnvironmentVariable($key, $Environment[$key]) }
        try {
            $out = Join-Path $root 'bat-output.txt'
            $p = Start-Process cmd.exe -ArgumentList '/c', "`"$Bat`"" -RedirectStandardInput $in -RedirectStandardOutput $out -NoNewWindow -PassThru -Wait
            return @(Get-Content -LiteralPath $out)
        } finally {
            foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
        }
    }
    # Inside a game folder: the menu.
    $inGame = Join-Path $steamGame 'mods\darktidevr\Darktide VR Mode.bat'
    $menu = Invoke-Bat $inGame '3'
    if (-not ($menu -match '3  Status only') -or -not ($menu -match 'mode switch ran mode=status')) { Fail "The in-game batch file did not run the menu: $($menu -join ' | ')" }

    # Opened from inside the zip: only the batch file, in Windows' temporary
    # copy named after the zip; the zip itself in a searched folder. The zip
    # holds a mod folder whose installer is a double that records its run.
    $zipSource = Join-Path $root 'zip-content'
    $zipMod = Join-Path $zipSource 'mods\darktidevr'
    New-ModFolder $zipMod
    Set-Content -LiteralPath (Join-Path $zipMod 'darktidevr-install.ps1') -Encoding ascii -Value @"
Set-Content -LiteralPath '$root\recovered.txt' -Value 'installer ran' -Encoding ascii
Write-Output 'installer double ran'
"@
    $downloads = Join-Path $root 'MyDownloads'
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null
    $zipName = 'darktidevr-9.9.9-test (1).zip'
    Compress-Archive -Path (Join-Path $zipSource 'mods') -DestinationPath (Join-Path $downloads $zipName)
    $tempCopy = Join-Path $root ("92f9ce15-f53e-4d19-81b3-094439ca0c73_$zipName.c73\mods\darktidevr")
    New-Item -ItemType Directory -Path $tempCopy -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ModRoot 'Darktide VR Mode.bat') -Destination $tempCopy
    $recovered = Invoke-Bat (Join-Path $tempCopy 'Darktide VR Mode.bat') '' @{ DTVR_ZIP_SEARCH = $downloads }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'recovered.txt')) -or -not ($recovered -match 'Installing from .*darktidevr-9\.9\.9-test \(1\)\.zip')) {
        Fail "The zip was not found and installed from: $($recovered -join ' | ')" }
    # The same, with the zip nowhere to be found: the extraction message.
    $lost = Invoke-Bat (Join-Path $tempCopy 'Darktide VR Mode.bat') '' @{ DTVR_ZIP_SEARCH = (Join-Path $root 'empty-search') }
    if (-not ($lost -match 'the zip could not be found')) { Fail "No message when the zip is missing: $($lost -join ' | ')" }
    # A batch file alone in an ordinary folder: the same message, no search.
    $alone = Join-Path $root 'alone'
    New-Item -ItemType Directory -Path $alone -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $ModRoot 'Darktide VR Mode.bat') -Destination $alone
    if (-not ((Invoke-Bat (Join-Path $alone 'Darktide VR Mode.bat') '') -match 'Extract the whole archive')) { Fail 'A lone batch file gave no extraction message' }
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'installer=pass steam store gaming_root choose refuse typed no_loader bat_menu bat_zip_recovery bat_alone'
