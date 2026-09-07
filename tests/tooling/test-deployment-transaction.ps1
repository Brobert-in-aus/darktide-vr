Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
. (Join-Path $PSScriptRoot '..\..\tools\stereo\invoke-deployment-transaction.ps1')
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ('darktidevr-deploy-test-' + [Guid]::NewGuid().ToString('N'))
$game = Join-Path $testRoot 'game'
$backup = Join-Path $testRoot 'backups'
$sources = Join-Path $testRoot 'sources'
$link = Join-Path $game 'linked'
$lock = $null
function Assert-Text([string] $Path, [string] $Expected) {
    if ([IO.File]::ReadAllText($Path) -cne $Expected) { throw "Unexpected bytes in $Path" }
}
function Assert-Rejected([hashtable[]] $Plan, [string] $Message) {
    $rejected = $false
    try { Invoke-DarktideDeploymentTransaction -Root $game -Entries $Plan -BackupRoot $backup | Out-Null }
    catch { $rejected = $_.Exception.Message.Contains($Message) }
    if (-not $rejected) { throw "Expected rejection: $Message" }
}
try {
    [IO.Directory]::CreateDirectory($game) | Out-Null
    [IO.Directory]::CreateDirectory($sources) | Out-Null
    $a = Join-Path $game 'a.dll'; $b = Join-Path $game 'b.lua'
    $flag = Join-Path $game 'new.flag'; $stale = Join-Path $game 'old.flag'
    $sourceA = Join-Path $sources 'a.dll'; $sourceB = Join-Path $sources 'b.lua'
    [IO.File]::WriteAllText($sourceA, 'new-native')
    [IO.File]::WriteAllText($sourceB, 'new-lua')
    $entries = @(
        @{ Source = $sourceA; Destination = $a },
        @{ Content = "enabled`r`n"; Destination = $flag },
        @{ Remove = $true; Destination = $stale },
        @{ Source = $sourceB; Destination = $b }
    )
    foreach ($phase in @('success', 'locked-last-file')) {
        [IO.File]::WriteAllText($a, 'original-native')
        [IO.File]::WriteAllText($b, 'original-lua')
        [IO.File]::WriteAllText($stale, 'original-diagnostic')
        if (Test-Path -LiteralPath $flag) { Remove-Item -LiteralPath $flag }
        if ($phase -eq 'locked-last-file') {
            $lock = [IO.File]::Open($b, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            Assert-Rejected $entries 'Status=rolled_back'
            $lock.Dispose(); $lock = $null
            Assert-Text $a 'original-native'
            Assert-Text $b 'original-lua'
            Assert-Text $stale 'original-diagnostic'
            if (Test-Path -LiteralPath $flag) { throw 'New file survived rollback.' }
            $manifests = @(Get-ChildItem -LiteralPath $backup -Directory | ForEach-Object {
                Get-Content -LiteralPath (Join-Path $_.FullName 'manifest.json') -Raw | ConvertFrom-Json
            } | Where-Object status -eq 'rolled_back')
            if ($manifests.Count -ne 1 -or $manifests[0].rollback_failures.Count -ne 0) {
                throw 'Rollback was not recorded as verified.'
            }
        } else {
            $receipt = Invoke-DarktideDeploymentTransaction -Root $game -Entries $entries -BackupRoot $backup
            if ($receipt.Status -ne 'committed' -or $receipt.FileCount -ne 4) { throw 'Missing commit receipt.' }
            Assert-Text $a 'new-native'; Assert-Text $b 'new-lua'; Assert-Text $flag "enabled`r`n"
            if (Test-Path -LiteralPath $stale) { throw 'Requested diagnostic removal did not occur.' }
            $manifest = Get-Content -LiteralPath $receipt.Manifest -Raw | ConvertFrom-Json
            Assert-Text $manifest.entries[0].Backup 'original-native'
            Assert-Text $manifest.entries[2].Backup 'original-diagnostic'
            if ($manifest.status -ne 'committed') { throw 'Commit manifest disagrees.' }
        }
    }
    Assert-Rejected @($entries[0], @{ Content = 'duplicate'; Destination = $a.ToUpperInvariant() }) 'Duplicate deployment destination'
    Assert-Rejected @(@{ Content = 'outside'; Destination = (Join-Path $testRoot 'outside.txt') }) 'escapes installation root'
    Assert-Rejected @(@{ Content = 'directory'; Destination = $sources }) 'escapes installation root'
    $directory = Join-Path $game 'directory'
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    Assert-Rejected @(@{ Content = 'directory'; Destination = $directory }) 'destination is a directory'
    Assert-Rejected @(@{ Content = 'missing'; Destination = (Join-Path $game 'missing\file') }) 'directory is missing'
    Assert-Rejected @(@{ Source = (Join-Path $sources 'absent'); Destination = $a }) 'Missing deployment source'
    Assert-Text $a 'original-native'
    $outside = Join-Path $testRoot 'junction-target'
    [IO.Directory]::CreateDirectory($outside) | Out-Null
    $victim = Join-Path $outside 'file'
    [IO.File]::WriteAllText($victim, 'outside-original')
    New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    Assert-Rejected @(@{ Content = 'escaped'; Destination = (Join-Path $link 'file') }) 'reparse point'
    Assert-Text $victim 'outside-original'
    Write-Output 'deployment_transaction=pass staging backup success locked_write rollback new_file removal scope duplicate junction'
} finally {
    if ($lock) { $lock.Dispose() }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolved).StartsWith('darktidevr-deploy-test-')) {
        throw 'Refusing cleanup outside the test-owned temporary directory.'
    }
    if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
