[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Inspect', 'Apply', 'Restore')]
    [string] $Action,

    # Resolved from the Steam installation when neither is given; -GameRoot
    # selects among several copies the same way the launcher does.
    [string] $GameExe,

    [string] $GameRoot,

    # Outside the game folder and outside any repository: a package user needs
    # a writable, discoverable place for the pristine executable.
    [string] $Backup = (Join-Path $env:LOCALAPPDATA 'DarktideVR\Darktide.exe.pre-skinner-assert-patch')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $GameExe) {
    . (Join-Path $PSScriptRoot 'resolve-darktide-game-root.ps1')
    $GameExe = Join-Path (Resolve-DarktideGameRoot -GameRoot $GameRoot) 'binaries\Darktide.exe'
}
New-Item -ItemType Directory -Path (Split-Path -Parent $Backup) -Force | Out-Null

# One entry per supported game build: the pristine executable's hash and the
# raw file offsets of the two `jne skip_assert` branches in
# stingray::deferred_skinning_kernel ("Bad Skinner!", d3d12_dispatcher lines
# 376 and 396). Each becomes `jmp skip_assert`; these are the only changed
# bytes. A build is recognised by reversing those bytes and hashing, so a
# patched executable is identified as exactly as a pristine one.
$builds = @(
    @{ Name = '1.12.5'
       Sha256 = 'e0f581d2c63b692c7d9f328e3edeb39c0f484956905569d38ba27bbb3fcc0aae'
       Offsets = @(0x7a7586, 0x7a7682) },
    @{ Name = '1.13.1'
       Sha256 = '28b843bc2905faaa0f27329d68e5de989df908f2552d80bf2b3c79b86e259775'
       Offsets = @(0x7c89c6, 0x7c8ac2) },
    @{ Name = '1.13.2'
       Sha256 = 'a7131fecade52ad4758eb7c7fa26986aa2c32edd545cb50cc61585ebfb4f9deb'
       Offsets = @(0x7c8ee6, 0x7c8fe2) }
)
$originalByte = [byte] 0x75
$patchedByte = [byte] 0xeb

function Get-BytesSha256([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        # [Convert]::ToHexString is absent from .NET Framework (Windows PowerShell 5.1).
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

# The build this executable is, and whether its two branches are original or
# patched. $null when it is no build this tool knows: a game update, or a file
# changed by something else.
function Resolve-Build([byte[]] $Bytes, [string] $Sha256) {
    foreach ($build in $builds) {
        if ($Sha256 -eq $build.Sha256) {
            return @{ Build = $build; State = 'original' }
        }
        $patchedCount = 0
        $candidate = $true
        foreach ($offset in $build.Offsets) {
            if ($offset -ge $Bytes.Length) { $candidate = $false; break }
            if ($Bytes[$offset] -eq $patchedByte) { ++$patchedCount }
            elseif ($Bytes[$offset] -ne $originalByte) { $candidate = $false; break }
        }
        if (-not $candidate -or $patchedCount -eq 0) { continue }
        $reversed = [byte[]] $Bytes.Clone()
        foreach ($offset in $build.Offsets) { $reversed[$offset] = $originalByte }
        if ((Get-BytesSha256 $reversed) -ne $build.Sha256) { continue }
        if ($patchedCount -ne $build.Offsets.Count) {
            throw 'Refusing a partially patched Darktide executable'
        }
        return @{ Build = $build; State = 'patched' }
    }
    return Find-Build $Bytes $Sha256
}

# A build this table does not list -- the next weekly hotfix, or the
# Microsoft Store / Game Pass executable, which is a different file from
# Steam's -- is recognised by the patch sites themselves rather than by hash:
# exactly one `cmp [rsi+0xd0], eax; jne +0x31` whose assertion call names
# "Bad Skinner!" with the condition of line 376, and exactly one with that of
# line 396, both original or both patched. The strings are followed through
# the instructions' RIP-relative loads, so a match is the same two branches
# that the listed builds patch, not merely similar bytes. Anything else is
# no build: unsupported, as before.
function Get-PeSections([byte[]] $Bytes) {
    $pe = [BitConverter]::ToInt32($Bytes, 0x3c)
    $count = [BitConverter]::ToUInt16($Bytes, $pe + 6)
    $optional = [BitConverter]::ToUInt16($Bytes, $pe + 20)
    $table = $pe + 24 + $optional
    for ($i = 0; $i -lt $count; ++$i) {
        $o = $table + $i * 40
        [pscustomobject]@{
            VirtualSize = [BitConverter]::ToUInt32($Bytes, $o + 8)
            VirtualAddress = [BitConverter]::ToUInt32($Bytes, $o + 12)
            RawSize = [BitConverter]::ToUInt32($Bytes, $o + 16)
            RawOffset = [BitConverter]::ToUInt32($Bytes, $o + 20)
        }
    }
}

function Convert-RawToRva($Sections, [long] $Raw) {
    foreach ($s in $Sections) {
        if ($Raw -ge $s.RawOffset -and $Raw -lt $s.RawOffset + $s.RawSize) { return $Raw - $s.RawOffset + $s.VirtualAddress }
    }
    return $null
}

function Convert-RvaToRaw($Sections, [long] $Rva) {
    foreach ($s in $Sections) {
        if ($Rva -ge $s.VirtualAddress -and $Rva -lt $s.VirtualAddress + [Math]::Max($s.VirtualSize, $s.RawSize)) { return $Rva - $s.VirtualAddress + $s.RawOffset }
    }
    return $null
}

# The NUL-terminated string a 7-byte `lea reg, [rip+disp32]` at $Raw loads.
function Get-LeaString([byte[]] $Bytes, $Sections, [long] $Raw) {
    $rva = Convert-RawToRva $Sections $Raw
    if ($null -eq $rva) { return $null }
    $target = Convert-RvaToRaw $Sections ($rva + 7 + [BitConverter]::ToInt32($Bytes, $Raw + 3))
    if ($null -eq $target -or $target -lt 0 -or $target -ge $Bytes.Length) { return $null }
    $end = [Array]::IndexOf($Bytes, [byte] 0, [int] $target)
    if ($end -lt 0 -or $end - $target -gt 256) { return $null }
    return [Text.Encoding]::ASCII.GetString($Bytes, $target, $end - $target)
}

function Find-Build([byte[]] $Bytes, [string] $Sha256) {
    $conditions = @{ 376 = 'bones_buffer.last_frame_accessed != frame'
                     396 = 'last_bones_buffer.last_frame_accessed != frame' }
    try { $sections = @(Get-PeSections $Bytes) } catch { return $null }
    # Latin-1 maps every byte to one character, so a regex index is a file offset.
    $text = [Text.Encoding]::GetEncoding(28591).GetString($Bytes)
    $pattern = '\x8b\x85\x00\x09\x00\x00\x39\x86\xd0\x00\x00\x00[\x75\xeb]\x31\x48\x8d\x05[\s\S]{4}\xb9[\s\S]{4}\x4c\x8d\x0d'
    $found = @{}
    foreach ($match in [regex]::Matches($text, $pattern)) {
        $site = $match.Index + 12
        # jne (2) and lea rax (7) precede `mov ecx, <line>`, whose immediate is at +10.
        $line = [BitConverter]::ToInt32($Bytes, $site + 10)
        if (-not $conditions.ContainsKey($line)) { continue }
        if ((Get-LeaString $Bytes $sections ($site + 2)) -ne 'Bad Skinner!') { continue }
        if ((Get-LeaString $Bytes $sections ($site + 14)) -ne $conditions[$line]) { continue }
        if ($found.ContainsKey($line)) { return $null }
        $found[$line] = $site
    }
    if ($found.Count -ne 2) { return $null }
    $offsets = @($found[376], $found[396])
    $values = @($offsets | ForEach-Object { $Bytes[$_] })
    if (@($values | Where-Object { $_ -eq $originalByte }).Count -eq 2) {
        $original = $Sha256
        $state = 'original'
    } elseif (@($values | Where-Object { $_ -eq $patchedByte }).Count -eq 2) {
        $reversed = [byte[]] $Bytes.Clone()
        foreach ($offset in $offsets) { $reversed[$offset] = $originalByte }
        $original = Get-BytesSha256 $reversed
        $state = 'patched'
    } else {
        throw 'Refusing a partially patched Darktide executable'
    }
    return @{ Build = @{ Name = "unlisted-$($original.Substring(0, 12))"; Sha256 = $original
                         Offsets = $offsets; Unlisted = $true }; State = $state }
}

$gamePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $GameExe)
$backupPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $Backup)
if (-not (Test-Path -LiteralPath $gamePath -PathType Leaf)) {
    throw "Darktide executable not found: $gamePath"
}
if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Refusing to modify Darktide.exe while the game is running'
}

$bytes = [IO.File]::ReadAllBytes($gamePath)
$sha256 = Get-BytesSha256 $bytes
$resolved = Resolve-Build $bytes $sha256

if ($Action -eq 'Inspect') {
    # Plain lines: object output can be dropped when the host exits right
    # after emitting it, and installers parse these values. An unknown build
    # is an answer, not an error: the mode switch must still be able to turn
    # VR off after a game update.
    Write-Output "path=$gamePath"
    if ($resolved) {
        Write-Output "state=$($resolved.State)"
        Write-Output "build=$($resolved.Build.Name)"
    } else {
        Write-Output 'state=unsupported'
        Write-Output 'build=unknown'
    }
    Write-Output "sha256=$sha256"
    if ($resolved) {
        Write-Output ("patched.offsets=" + (($resolved.Build.Offsets | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))
    }
    Write-Output "backup=$backupPath backup.present=$(Test-Path -LiteralPath $backupPath -PathType Leaf)"
    exit 0
}

if (-not $resolved) {
    throw "Unknown Darktide executable hash: $sha256"
}
$build = $resolved.Build

if ($Action -eq 'Apply') {
    $eac = Get-Service EasyAntiCheat_EOS -ErrorAction SilentlyContinue
    if ($eac -and $eac.Status -ne 'Stopped') {
        throw "Refusing to patch Darktide while EAC is $($eac.Status)"
    }
    if ($resolved.State -eq 'patched') {
        throw 'Darktide.exe is already patched'
    }

    $backupDirectory = Split-Path -Parent $backupPath
    if (-not (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    }
    $backupSha256 = $null
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        $backupSha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).
            Hash.ToLowerInvariant()
    }
    if ($backupSha256 -ne $build.Sha256) {
        # No copy yet, or the copy of an earlier game build that a game update
        # has since replaced: this build's pristine executable takes its place.
        Copy-Item -LiteralPath $gamePath -Destination $backupPath -Force
    }

    foreach ($offset in $build.Offsets) {
        $bytes[$offset] = $patchedByte
    }
    [IO.File]::WriteAllBytes($gamePath, $bytes)
    $patchedSha256 = (Get-FileHash -LiteralPath $gamePath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    Write-Output "Applied exact two-byte skinner assertion patch (build $($build.Name))"
    Write-Output "patched.sha256=$patchedSha256"
    Write-Output "restore.command=tools\stereo\set-skinner-assert-patch.ps1 -Action Restore"
    exit 0
}

if ($resolved.State -ne 'patched') {
    throw 'Darktide.exe is not in the expected patched state'
}
# Resolve-Build has already shown that reversing the two bytes reproduces the
# pristine hash, so the restore does not depend on the copy: a copy that is
# missing, or is an earlier build's, must not leave the game unrestorable.
$backupMatches = (Test-Path -LiteralPath $backupPath -PathType Leaf) -and
    ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $build.Sha256)
# An unlisted build has no known hash to prove the reversal against; the copy
# Apply kept is that proof. Without it the restore is refused, and the store's
# own file check (Steam: Verify integrity; Xbox app: Repair) puts it back.
if ($build.Unlisted -and -not $backupMatches) {
    throw 'This executable was patched as a build the tool does not list, and the pristine copy that would prove the restore is missing or belongs to another build. Use Verify integrity of game files (Steam) or Repair (Xbox app) to restore Darktide.exe.'
}
if ($backupMatches) {
    Copy-Item -LiteralPath $backupPath -Destination $gamePath -Force
    Write-Output 'Restored pristine Darktide.exe from verified backup'
} else {
    foreach ($offset in $build.Offsets) {
        $bytes[$offset] = $originalByte
    }
    [IO.File]::WriteAllBytes($gamePath, $bytes)
    Write-Output 'Restored pristine Darktide.exe by reversing the two patched bytes'
}
$restoredSha256 = (Get-FileHash -LiteralPath $gamePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($restoredSha256 -ne $build.Sha256) {
    throw "Restored executable has unexpected hash: $restoredSha256"
}
