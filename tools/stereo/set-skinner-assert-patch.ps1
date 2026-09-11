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

$originalSha256 =
    'e0f581d2c63b692c7d9f328e3edeb39c0f484956905569d38ba27bbb3fcc0aae'
$patches = @(
    # jne skip_assert -> jmp skip_assert. These are the only changed bytes.
    @{ Offset = 0x7a7586; Original = [byte] 0x75; Patched = [byte] 0xeb },
    @{ Offset = 0x7a7682; Original = [byte] 0x75; Patched = [byte] 0xeb }
)

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

function Get-PatchState([byte[]] $Bytes) {
    $originalCount = 0
    $patchedCount = 0
    foreach ($patch in $patches) {
        $value = $Bytes[$patch.Offset]
        if ($value -eq $patch.Original) {
            ++$originalCount
        }
        elseif ($value -eq $patch.Patched) {
            ++$patchedCount
        }
        else {
            throw ('Unexpected byte 0x{0:x2} at file offset 0x{1:x}' -f
                $value, $patch.Offset)
        }
    }
    if ($originalCount -eq $patches.Count) {
        return 'original'
    }
    if ($patchedCount -eq $patches.Count) {
        return 'patched'
    }
    throw 'Refusing a partially patched Darktide executable'
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
$state = Get-PatchState $bytes
$sha256 = Get-BytesSha256 $bytes

if ($Action -eq 'Inspect') {
    # Plain lines: object output can be dropped when the host exits right
    # after emitting it, and installers parse these values.
    Write-Output "path=$gamePath"
    Write-Output "state=$state"
    Write-Output "sha256=$sha256"
    Write-Output ("patched.offsets=" + (($patches.Offset | ForEach-Object { '0x{0:x}' -f $_ }) -join ','))
    Write-Output "backup=$backupPath backup.present=$(Test-Path -LiteralPath $backupPath -PathType Leaf)"
    exit 0
}

if ($Action -eq 'Apply') {
    $eac = Get-Service EasyAntiCheat_EOS -ErrorAction SilentlyContinue
    if ($eac -and $eac.Status -ne 'Stopped') {
        throw "Refusing to patch Darktide while EAC is $($eac.Status)"
    }
    if ($state -eq 'patched') {
        throw 'Darktide.exe is already patched'
    }
    if ($sha256 -ne $originalSha256) {
        throw "Unknown Darktide executable hash: $sha256"
    }

    $backupDirectory = Split-Path -Parent $backupPath
    if (-not (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $backupPath) {
        $backupSha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).
            Hash.ToLowerInvariant()
        if ($backupSha256 -ne $originalSha256) {
            throw "Existing backup has unexpected hash: $backupSha256"
        }
    }
    else {
        Copy-Item -LiteralPath $gamePath -Destination $backupPath
    }

    foreach ($patch in $patches) {
        $bytes[$patch.Offset] = $patch.Patched
    }
    [IO.File]::WriteAllBytes($gamePath, $bytes)
    $patchedSha256 = (Get-FileHash -LiteralPath $gamePath -Algorithm SHA256).
        Hash.ToLowerInvariant()
    Write-Output "Applied exact two-byte skinner assertion patch"
    Write-Output "patched.sha256=$patchedSha256"
    Write-Output "restore.command=tools\stereo\set-skinner-assert-patch.ps1 -Action Restore"
    exit 0
}

if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
    throw "Pristine backup not found: $backupPath"
}
$backupSha256 = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).
    Hash.ToLowerInvariant()
if ($backupSha256 -ne $originalSha256) {
    throw "Pristine backup has unexpected hash: $backupSha256"
}
if ($state -ne 'patched') {
    throw 'Darktide.exe is not in the expected patched state'
}

$reversed = [byte[]] $bytes.Clone()
foreach ($patch in $patches) {
    $reversed[$patch.Offset] = $patch.Original
}
if ((Get-BytesSha256 $reversed) -ne $originalSha256) {
    throw 'Patched executable differs from the known build beyond the two patch bytes'
}
Copy-Item -LiteralPath $backupPath -Destination $gamePath -Force
Write-Output 'Restored pristine Darktide.exe from verified backup'
