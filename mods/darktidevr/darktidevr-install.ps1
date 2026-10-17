[CmdletBinding()]
param(
    # The game folder to install into. Without it the Steam libraries and the
    # Xbox app's games folders are searched, and the player chooses when more
    # than one installation is found.
    [string] $GameRoot,

    # Answers for the prompts, in order, for tests and scripted installs. A
    # prompt with no answer left reads the console.
    [string[]] $Answers,

    # Search roots for tests: Steam installations and drive roots.
    [string[]] $SteamRoots,
    [string[]] $DriveRoots,
    [switch] $SkipAppx
)

# Installs the mod folder this script sits in into a Darktide installation,
# then switches that installation to VR mode. "Darktide VR Mode.bat" runs it
# when the archive was extracted anywhere but the game folder, so a player
# never has to find the game folder (17 October 2026).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Through -File an array arrives as one string: the test roots are ';'-separated.
if ($SteamRoots) { $SteamRoots = @($SteamRoots | ForEach-Object { $_ -split ';' } | Where-Object { $_ }) }
if ($DriveRoots) { $DriveRoots = @($DriveRoots | ForEach-Object { $_ -split ';' } | Where-Object { $_ }) }
if ($Answers) { $Answers = @($Answers | ForEach-Object { $_ -split ';' }) }

$modName = 'darktidevr'
$sourceRoot = $PSScriptRoot
. (Join-Path $sourceRoot 'tools\resolve-darktide-game-root.ps1')

$answerIndex = 0
function Read-Answer([string] $Prompt) {
    Write-Host -NoNewline "$Prompt "
    if ($script:Answers -and $script:answerIndex -lt $script:Answers.Count) {
        $value = $script:Answers[$script:answerIndex]
        $script:answerIndex++
        Write-Host $value
        return $value
    }
    $line = [Console]::ReadLine()
    if ($null -eq $line) { return '' }
    return $line.Trim().Trim('"')
}

function Test-GameFolder([string] $Path) {
    return $Path -and (Test-Path -LiteralPath (Join-Path $Path 'binaries\Darktide.exe') -PathType Leaf)
}

if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Close Darktide before installing.'
}

$found = [Collections.Generic.List[pscustomobject]]::new()
if ($GameRoot) {
    if (-not (Test-GameFolder $GameRoot)) { throw "Not a Darktide game folder (no binaries\Darktide.exe): $GameRoot" }
    $found.Add([pscustomobject]@{ Store = 'chosen'; Root = (Resolve-Path -LiteralPath $GameRoot).Path })
} else {
    # A library that cannot be read is skipped, not fatal: the other store,
    # or a typed folder, may still be the right one.
    $steam = @()
    try {
        $steam = @(if ($PSBoundParameters.ContainsKey('SteamRoots')) {
            Get-DarktideSteamInstallations -SteamRoots $SteamRoots
        } else { Get-DarktideSteamInstallations })
    } catch { Write-Output "Steam libraries could not be read: $($_.Exception.Message)" }
    foreach ($root in $steam) { $found.Add([pscustomobject]@{ Store = 'Steam'; Root = $root }) }
    $store = @()
    try {
        $storeArguments = @{ SkipAppx = $SkipAppx }
        if ($PSBoundParameters.ContainsKey('DriveRoots')) { $storeArguments.DriveRoots = $DriveRoots }
        $store = @(Get-DarktideStoreInstallations @storeArguments)
    } catch { Write-Output "Xbox app games folders could not be read: $($_.Exception.Message)" }
    foreach ($root in $store) {
        if (-not ($found | Where-Object { $_.Root -eq $root })) {
            $found.Add([pscustomobject]@{ Store = 'Microsoft Store / Game Pass'; Root = $root })
        }
    }
}

$target = $null
if ($found.Count -eq 1) {
    Write-Output "Found Darktide ($($found[0].Store)): $($found[0].Root)"
    $answer = Read-Answer 'Install Darktide VR there? [Y/n]'
    if ($answer -and $answer -notmatch '^(y|yes)$') { Write-Output 'Nothing installed.'; exit 1 }
    $target = $found[0].Root
} elseif ($found.Count -gt 1) {
    Write-Output 'Darktide is installed in more than one place:'
    for ($i = 0; $i -lt $found.Count; ++$i) {
        Write-Output ("  {0}  {1}: {2}" -f ($i + 1), $found[$i].Store, $found[$i].Root)
    }
    $answer = Read-Answer "Install into which one? [1-$($found.Count)]"
    $index = 0
    if (-not [int]::TryParse($answer, [ref] $index) -or $index -lt 1 -or $index -gt $found.Count) {
        Write-Output 'Nothing installed.'; exit 1
    }
    $target = $found[$index - 1].Root
} else {
    Write-Output 'Darktide was not found in the Steam libraries or the Xbox app''s games folders.'
    Write-Output 'Type the game folder (the one that contains "binaries", "bundle" and "mods"),'
    Write-Output 'for example C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE'
    Write-Output 'or C:\XboxGames\Warhammer 40,000- DARKTIDE\Content.'
    $answer = Read-Answer 'Game folder:'
    if (-not (Test-GameFolder $answer)) { Write-Output "Not a Darktide game folder: $answer"; exit 1 }
    $target = (Resolve-Path -LiteralPath $answer).Path
}

# The mod loader and framework are the other mods' business, but without them
# the game never loads this one: say so before changing anything.
if (-not (Test-Path -LiteralPath (Join-Path $target 'mods\dmf') -PathType Container) -or
        -not (Test-Path -LiteralPath (Join-Path $target 'mods\mod_load_order.txt') -PathType Leaf)) {
    Write-Output "The Darktide Mod Loader and Darktide Mod Framework are not installed in $target."
    Write-Output 'Install them first (their toggle_darktide_mods.bat must have been run), then run this again.'
    exit 1
}

$destination = Join-Path $target "mods\$modName"
$sourceFull = [IO.Path]::GetFullPath($sourceRoot).TrimEnd('\')
$destinationFull = [IO.Path]::GetFullPath($destination).TrimEnd('\')
if ($sourceFull -ne $destinationFull) {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    # Over an earlier version, as extracting over it would: files are
    # replaced, files only the old version had are left alone.
    $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceFull.Length + 1)
        $out = Join-Path $destination $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $out -Force
    }
    Write-Output "Installed $($files.Count) files into $destination"
}

$modeScript = Join-Path $destination 'darktidevr-mode.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $modeScript -Mode vr -GameRoot $target
exit $LASTEXITCODE
