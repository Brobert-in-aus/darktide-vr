param([string] $ToolPath)
# The skinner patch on an executable the tool does not list (a weekly game
# hotfix, or the Microsoft Store / Game Pass build): the two branches are
# found by their instructions and the strings those instructions load, then
# patched, inspected and restored; a near miss is refused. The executable is a
# synthetic one-section PE carrying exactly what the search reads, so the test
# needs no game files.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if (-not $ToolPath) { $ToolPath = Join-Path $repoRoot 'tools\stereo\set-skinner-assert-patch.ps1' }
function Fail([string] $message) { Write-Error $message; exit 1 }

$root = Join-Path ([IO.Path]::GetTempPath()) ("darktidevr-skinner-discovery-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null

function New-Executable([string] $Condition396 = 'last_bones_buffer.last_frame_accessed != frame', [switch] $Duplicate) {
    $b = New-Object byte[] 0x3000
    [BitConverter]::GetBytes([int] 0x80).CopyTo($b, 0x3c)
    [Text.Encoding]::ASCII.GetBytes("PE`0`0").CopyTo($b, 0x80)
    [BitConverter]::GetBytes([uint16] 1).CopyTo($b, 0x86)        # sections
    [BitConverter]::GetBytes([uint16] 0xf0).CopyTo($b, 0x94)     # optional header size
    $section = 0x80 + 24 + 0xf0
    [Text.Encoding]::ASCII.GetBytes('.text').CopyTo($b, $section)
    foreach ($pair in @(@(8, 0x2000), @(12, 0x1000), @(16, 0x2000), @(20, 0x1000))) {
        [BitConverter]::GetBytes([uint32] $pair[1]).CopyTo($b, $section + $pair[0])
    }
    # Raw offset equals RVA in this section, which keeps the displacements plain.
    $strings = @{}
    $at = 0x2800
    foreach ($text in @('Bad Skinner!', 'bones_buffer.last_frame_accessed != frame', $Condition396)) {
        if (-not $strings.ContainsKey($text)) {
            $strings[$text] = $at
            [Text.Encoding]::ASCII.GetBytes($text + "`0").CopyTo($b, $at)
            $at += $text.Length + 8
        }
    }
    $sites = @(@(0x1100, 376, 'bones_buffer.last_frame_accessed != frame'), @(0x1200, 396, $Condition396))
    if ($Duplicate) { $sites += ,@(0x1300, 396, $Condition396) }
    foreach ($site in $sites) {
        $start = $site[0] - 12
        ([byte[]](0x8b, 0x85, 0x00, 0x09, 0x00, 0x00, 0x39, 0x86, 0xd0, 0x00, 0x00, 0x00, 0x75, 0x31, 0x48, 0x8d, 0x05)).CopyTo($b, $start)
        [BitConverter]::GetBytes([int] ($strings['Bad Skinner!'] - ($site[0] + 2 + 7))).CopyTo($b, $site[0] + 5)
        $b[$site[0] + 9] = 0xb9
        [BitConverter]::GetBytes([int] $site[1]).CopyTo($b, $site[0] + 10)
        ([byte[]](0x4c, 0x8d, 0x0d)).CopyTo($b, $site[0] + 14)
        [BitConverter]::GetBytes([int] ($strings[$site[2]] - ($site[0] + 14 + 7))).CopyTo($b, $site[0] + 17)
    }
    return ,$b
}

function Invoke-Tool([string] $Action, [string] $Exe, [string] $Backup) {
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ToolPath -Action $Action -GameExe $Exe -Backup $Backup 2>&1 | ForEach-Object { "$_" })
        return @{ exit = $LASTEXITCODE; lines = $lines }
    } finally { $ErrorActionPreference = 'Stop' }
}
function Value($result, [string] $key) { return (($result.lines | Where-Object { $_ -like "$key=*" } | Select-Object -First 1) -replace "^$key=", '') }

try {
    $exe = Join-Path $root 'Darktide.exe'
    $backup = Join-Path $root 'pristine.bin'
    $pristine = New-Executable
    [IO.File]::WriteAllBytes($exe, $pristine)

    $inspect = Invoke-Tool 'Inspect' $exe $backup
    if ((Value $inspect 'state') -ne 'original' -or (Value $inspect 'build') -notlike 'unlisted-*' -or
            (Value $inspect 'patched.offsets') -ne '0x1100,0x1200') { Fail "Unlisted build not found: $($inspect.lines -join ' | ')" }

    $apply = Invoke-Tool 'Apply' $exe $backup
    if ($apply.exit -ne 0) { Fail "Apply failed: $($apply.lines -join ' | ')" }
    $patched = [IO.File]::ReadAllBytes($exe)
    $changed = @(0..($patched.Length - 1) | Where-Object { $patched[$_] -ne $pristine[$_] })
    if ($changed.Count -ne 2 -or $changed[0] -ne 0x1100 -or $changed[1] -ne 0x1200 -or $patched[0x1100] -ne 0xeb) { Fail "Apply changed bytes $($changed -join ',')" }
    if ((Value (Invoke-Tool 'Inspect' $exe $backup) 'state') -ne 'patched') { Fail 'A patched unlisted build was not recognised' }

    # Without the pristine copy there is nothing to prove the restore against.
    $refused = Invoke-Tool 'Restore' $exe (Join-Path $root 'missing.bin')
    if ($refused.exit -eq 0 -or -not ($refused.lines -match 'Verify integrity')) { Fail "Restore without the copy was not refused: $($refused.lines -join ' | ')" }
    $restore = Invoke-Tool 'Restore' $exe $backup
    if ($restore.exit -ne 0) { Fail "Restore failed: $($restore.lines -join ' | ')" }
    $restored = [IO.File]::ReadAllBytes($exe)
    if (@(0..($restored.Length - 1) | Where-Object { $restored[$_] -ne $pristine[$_] }).Count -ne 0) { Fail 'Restore did not reproduce the pristine executable' }

    # Near misses: a different assertion at the second site, or a third site.
    foreach ($case in @(@{ name = 'wrong condition'; bytes = (New-Executable -Condition396 'bones_buffer.last_frame_accessed == frame') },
                        @{ name = 'duplicate site'; bytes = (New-Executable -Duplicate) })) {
        [IO.File]::WriteAllBytes($exe, $case.bytes)
        $result = Invoke-Tool 'Inspect' $exe $backup
        if ((Value $result 'state') -ne 'unsupported') { Fail "$($case.name) was accepted: $($result.lines -join ' | ')" }
        if ((Invoke-Tool 'Apply' $exe $backup).exit -eq 0) { Fail "$($case.name) was patched" }
    }
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'skinner_patch_discovery=pass unlisted_found apply_two_bytes restore_needs_copy near_misses_refused'
