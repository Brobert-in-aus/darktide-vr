Set-StrictMode -Version Latest

function ConvertFrom-SteamKeyValues {
    param([Parameter(Mandatory)][string] $Text)
    $root = @{}
    $stack = [Collections.Generic.Stack[hashtable]]::new()
    $stack.Push($root)
    $pending = $null
    # Retain only the text KeyValues grammar used by Steam's local manifests.
    # Unknown tokens and duplicate keys fail instead of choosing a guessed path.
    foreach ($match in [regex]::Matches($Text, '"(?:\\.|[^"\\])*"|[{}]|//[^\r\n]*|\s+|.', 'Singleline')) {
        $token = $match.Value
        if ($token -match '^\s+$' -or $token.StartsWith('//')) { continue }
        $current = $stack.Peek()
        if ($token -eq '{') {
            if ($null -eq $pending -or $current.ContainsKey($pending)) { throw 'Invalid Steam manifest object.' }
            $child = @{}
            $current.Add($pending, $child)
            $stack.Push($child)
            $pending = $null
        }
        elseif ($token -eq '}') {
            if ($null -ne $pending -or $stack.Count -le 1) { throw 'Unbalanced Steam manifest.' }
            [void] $stack.Pop()
        }
        elseif ($token.StartsWith('"') -and $token.EndsWith('"') -and $token.Length -ge 2) {
            $value = [regex]::Replace($token.Substring(1, $token.Length - 2), '\\([\\"])', '$1')
            if ($null -eq $pending) { $pending = $value }
            else {
                if ($current.ContainsKey($pending)) { throw 'Duplicate Steam manifest key.' }
                $current.Add($pending, $value)
                $pending = $null
            }
        }
        else { throw 'Unsupported Steam manifest token.' }
    }
    if ($null -ne $pending -or $stack.Count -ne 1) { throw 'Incomplete Steam manifest.' }
    return $root
}

function Resolve-DarktideGameRoot {
    [CmdletBinding()]
    param([string] $GameRoot, [string[]] $SteamRoots)
    if ($GameRoot) {
        $resolved = (Resolve-Path -LiteralPath $GameRoot -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath (Join-Path $resolved 'binaries/Darktide.exe') -PathType Leaf)) {
            throw 'The selected game folder does not contain binaries\Darktide.exe.'
        }
        return $resolved
    }
    if (-not $PSBoundParameters.ContainsKey('SteamRoots')) {
        $SteamRoots = @(
            foreach ($entry in @(
                @{Path='HKCU:\Software\Valve\Steam'; Name='SteamPath'},
                @{Path='HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name='InstallPath'},
                @{Path='HKLM:\SOFTWARE\Valve\Steam'; Name='InstallPath'})) {
                $value = Get-ItemProperty -LiteralPath $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
                if ($value) { $value.($entry.Name) }
            }
            if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Steam' }
        )
    }
    $libraries = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($steam in $SteamRoots) {
        if (-not $steam -or -not (Test-Path -LiteralPath $steam -PathType Container)) { continue }
        $steam = (Resolve-Path -LiteralPath $steam).Path
        [void] $libraries.Add($steam)
        $libraryFile = Join-Path $steam 'steamapps/libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }
        $data = ConvertFrom-SteamKeyValues ([IO.File]::ReadAllText($libraryFile))
        $folders = $data['libraryfolders']
        if ($folders -isnot [hashtable]) { throw 'Steam library list is invalid; pass -GameRoot explicitly.' }
        foreach ($key in $folders.Keys) {
            if ($key -notmatch '^\d+$') { continue }
            $entry = $folders[$key]
            $path = if ($entry -is [hashtable]) { $entry['path'] } else { $entry }
            if ($path -is [string] -and $path -match '^(?:[a-zA-Z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$))' -and
                    (Test-Path -LiteralPath $path -PathType Container)) {
                [void] $libraries.Add((Resolve-Path -LiteralPath $path).Path)
            }
        }
    }
    $games = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($library in $libraries) {
        $manifest = Join-Path $library 'steamapps/appmanifest_1361210.acf'
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
        $data = ConvertFrom-SteamKeyValues ([IO.File]::ReadAllText($manifest))
        $app = $data['AppState']
        if ($app -isnot [hashtable] -or $app['appid'] -ne '1361210') {
            throw 'Darktide Steam manifest has an invalid app identity; pass -GameRoot explicitly.'
        }
        $folder = $app['installdir']
        if ($folder -isnot [string] -or -not $folder -or $folder -in @('.', '..') -or
                $folder.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw 'Darktide Steam manifest has an invalid installation folder; pass -GameRoot explicitly.'
        }
        $candidate = Join-Path (Join-Path $library 'steamapps/common') $folder
        if (Test-Path -LiteralPath (Join-Path $candidate 'binaries/Darktide.exe') -PathType Leaf) {
            [void] $games.Add((Resolve-Path -LiteralPath $candidate).Path)
        }
    }
    if ($games.Count -eq 1) { return @($games)[0] }
    if ($games.Count -gt 1) { throw ('Multiple Darktide installations found; pass -GameRoot explicitly: ' + (@($games) -join '; ')) }
    throw 'Darktide was not found in the registered Steam libraries. Pass -GameRoot with its installed game folder.'
}
