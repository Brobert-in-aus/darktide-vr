Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Utility/Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
. (Join-Path $PSScriptRoot '..\..\tools\stereo\restore-deployment-transaction.ps1')
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ('darktidevr-recovery-test-' + [Guid]::NewGuid().ToString('N'))
$game = Join-Path $testRoot 'game'
$backups = Join-Path $testRoot 'backups'
$lock = $null
function Assert-Text([string] $Path, [string] $Expected) {
    if ([IO.File]::ReadAllText($Path) -cne $Expected) { throw "Unexpected bytes: $Path" }
}
function Assert-Rejected([string] $Manifest, [string] $Message) {
    $failed = $false
    try { Restore-DarktideDeploymentTransaction -Root $game -Manifest $Manifest -BackupRoot $backups | Out-Null }
    catch { $failed = $_.Exception.Message.Contains($Message) }
    if (-not $failed) { throw "Expected recovery rejection: $Message" }
}
try {
    [IO.Directory]::CreateDirectory($game) | Out-Null
    $a = Join-Path $game 'a.dll'; $b = Join-Path $game 'b.lua'; $stale = Join-Path $game 'old.flag'
    $left = Join-Path $game 'left\new.flag'; $right = Join-Path $game 'rght\new.flag'
    $plan = @(@{ Content = 'new-a'; Destination = $a }, @{ Content = 'new-b'; Destination = $b },
        @{ Remove = $true; Destination = $stale }, @{ Content = 'new-left'; Destination = $left },
        @{ Content = 'new-right'; Destination = $right })
    foreach ($path in @($a, $b, $stale)) { [IO.File]::WriteAllText($path, 'original') }
    $deployed = Invoke-DarktideDeploymentTransaction -Root $game -Entries $plan -BackupRoot $backups -CreateDirectories
    # A failed recovery must roll its earlier restoration back to the deployed state.
    $lock = [IO.File]::Open($b, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    Assert-Rejected $deployed.Manifest 'Status=rolled_back'
    $lock.Dispose(); $lock = $null
    Assert-Text $a 'new-a'; Assert-Text $b 'new-b'
    if (Test-Path -LiteralPath $stale) { throw 'Rejected recovery partially restored a removed file.' }
    $recovered = Restore-DarktideDeploymentTransaction -Root $game -Manifest $deployed.Manifest -BackupRoot $backups
    if ($recovered.status -ne 'restored') { throw 'Recovery did not complete.' }
    foreach ($path in @($a, $b, $stale)) { Assert-Text $path 'original' }
    foreach ($directory in @('left', 'rght')) {
        if (Test-Path -LiteralPath (Join-Path $game $directory)) { throw 'New empty directory survived recovery.' }
    }
    Restore-DarktideDeploymentTransaction -Root $game -Manifest $deployed.Manifest -BackupRoot $backups | Out-Null
    # Model abrupt termination: saved staged state, mixed old/new and missing bytes.
    $deployed = Invoke-DarktideDeploymentTransaction -Root $game -Entries $plan -BackupRoot $backups -CreateDirectories
    $interrupted = Get-Content -LiteralPath $deployed.Manifest -Raw | ConvertFrom-Json
    $interrupted.status = 'staged'
    $interrupted | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $deployed.Manifest -Encoding UTF8
    [IO.File]::WriteAllText($a, 'original')
    Remove-Item -LiteralPath $b
    Restore-DarktideDeploymentTransaction -Root $game -Manifest $deployed.Manifest -BackupRoot $backups | Out-Null
    foreach ($path in @($a, $b, $stale)) { Assert-Text $path 'original' }
    # Foreign changes are protected unless explicitly selected, then backed up.
    $deployed = Invoke-DarktideDeploymentTransaction -Root $game -Entries $plan -BackupRoot $backups -CreateDirectories
    [IO.File]::WriteAllText($a, 'later-user-edit')
    Assert-Rejected $deployed.Manifest 'Installed file changed after this deployment'
    Assert-Text $a 'later-user-edit'; Assert-Text $b 'new-b'
    $extra = Join-Path $game 'left\user.txt'
    [IO.File]::WriteAllText($extra, 'keep-user-file')
    $recovered = Restore-DarktideDeploymentTransaction -Root $game -Manifest $deployed.Manifest -BackupRoot $backups -AllowChangedFiles
    if ($recovered.status -ne 'files_restored_directories_retained' -or $recovered.retained_directories.Count -ne 1) {
        throw 'Nonempty directory retention was not reported.'
    }
    Assert-Text $extra 'keep-user-file'; Assert-Text $a 'original'
    $receipt = Get-Content -LiteralPath $recovered.recovery_manifest -Raw | ConvertFrom-Json
    Assert-Text $receipt.entries[0].Backup 'later-user-edit'
    # Change an input after recovery's initial validation but before the real
    # transaction stages it. The whole recovery must reject, preserving new edits.
    $raceDeployed=Invoke-DarktideDeploymentTransaction -Root $game -Entries $plan -BackupRoot $backups -CreateDirectories
    $raceSaved=Get-Content -LiteralPath $raceDeployed.Manifest -Raw|ConvertFrom-Json
    $transaction=${function:Invoke-DarktideDeploymentTransaction}
    try {
        function Invoke-DarktideDeploymentTransaction {
            param($Root,$Entries,$BackupRoot,[switch]$CreateDirectories)
            & $beforeStaging
            & $transaction @PSBoundParameters
        }
        foreach($mutation in @('changed','removed','appeared','backup')) {
            $beforeStaging={
                switch($mutation) {
                    changed { [IO.File]::WriteAllText($b,'concurrent-edit') }
                    removed { Remove-Item -LiteralPath $b }
                    appeared { [IO.File]::WriteAllText($stale,'concurrent-new-file') }
                    backup { [IO.File]::WriteAllText($raceSaved.entries[1].Backup,'concurrent-backup-damage') }
                }
            }
            $message=if($mutation -eq 'backup'){'Source hash precondition'}else{'Destination hash precondition'}
            Assert-Rejected $raceDeployed.Manifest $message
            Assert-Text $a 'new-a'
            if($mutation -eq 'changed'){Assert-Text $b 'concurrent-edit'}
            elseif($mutation -eq 'removed'){if(Test-Path -LiteralPath $b){throw 'Recovery recreated a concurrently removed file.'}}
            else{Assert-Text $b 'new-b'}
            if($mutation -eq 'appeared'){Assert-Text $stale 'concurrent-new-file';Remove-Item -LiteralPath $stale}
            [IO.File]::WriteAllText($b,'new-b')
            [IO.File]::WriteAllText($raceSaved.entries[1].Backup,'original')
        }
        [IO.File]::WriteAllText($b,'reviewed-user-edit')
        $beforeStaging={ [IO.File]::WriteAllText($b,'later-concurrent-edit') }
        $rejected=$false
        try { Restore-DarktideDeploymentTransaction -Root $game -Manifest $raceDeployed.Manifest -BackupRoot $backups -AllowChangedFiles|Out-Null }
        catch { $rejected=$_.Exception.Message.Contains('Destination hash precondition') }
        if(-not $rejected){throw 'Explicit recovery accepted a later unreviewed replacement.'}
        Assert-Text $a 'new-a';Assert-Text $b 'later-concurrent-edit'
        [IO.File]::WriteAllText($b,'new-b')
    } finally { Set-Item -Path Function:Invoke-DarktideDeploymentTransaction -Value $transaction }
    Restore-DarktideDeploymentTransaction -Root $game -Manifest $raceDeployed.Manifest -BackupRoot $backups|Out-Null
    # A damaged original must reject before any destination changes.
    $saved = Get-Content -LiteralPath $deployed.Manifest -Raw | ConvertFrom-Json
    [IO.File]::WriteAllText($saved.entries[1].Backup, 'damaged')
    Assert-Rejected $deployed.Manifest 'Deployment backup is missing or damaged'
    Assert-Text $a 'original'; Assert-Text $b 'original'
    $altered = Join-Path (Split-Path -Parent $deployed.Manifest) 'altered.json'
    $saved.root = Join-Path $testRoot 'wrong-game'
    $saved | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $altered -Encoding UTF8
    Assert-Rejected $altered 'different installation'
    $saved.root = $game
    $saved.entries[0].Destination = Join-Path $testRoot 'outside'
    $saved | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $altered -Encoding UTF8
    Assert-Rejected $altered 'escapes its root'
    Write-Output 'deployment_recovery=pass restore repeat failed_restore_rollback changed_file_guard retained_user_files backup_hash scope'
} finally {
    if ($lock) { $lock.Dispose() }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolved).StartsWith('darktidevr-recovery-test-')) { throw 'Refusing cleanup outside the temporary test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
