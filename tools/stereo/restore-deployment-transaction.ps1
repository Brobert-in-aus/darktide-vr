. (Join-Path $PSScriptRoot 'invoke-deployment-transaction.ps1')

function Restore-DarktideDeploymentTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][string] $Manifest,
        [Parameter(Mandatory)][string] $BackupRoot,
        [switch] $AllowChangedFiles
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    $manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
    $backupDirectory = Split-Path -Parent $manifestPath
    $saved = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($saved.schema_version -notin @(1, 2)) { throw 'Unsupported deployment manifest version.' }
    if (-not $rootPath.Equals([string] $saved.root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment manifest belongs to a different installation.'
    }
    if ($saved.status -notin @('staged', 'committed', 'rolled_back', 'rollback_incomplete', 'failed_before_write')) {
        throw 'Deployment manifest has no recoverable staged state.'
    }
    $assertPath = {
        param([string] $Path, [string] $Base)
        $absolute = [IO.Path]::GetFullPath($Path)
        if (-not $absolute.StartsWith($Base + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Recovery path escapes its root: $absolute"
        }
        $cursor = $absolute
        while ($cursor -ne $Base) {
            if (Test-Path -LiteralPath $cursor) {
                $item = Get-Item -LiteralPath $cursor -Force
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Recovery path contains a reparse point: $cursor" }
                if ($cursor -ne $absolute -and -not $item.PSIsContainer) { throw "Recovery parent is a file: $cursor" }
            }
            $cursor = Split-Path -Parent $cursor
        }
        return $absolute
    }
    $entries = @()
    $newFiles = @()
    foreach ($entry in @($saved.entries)) {
        $destination = & $assertPath $entry.Destination $rootPath
        if ($entry.Existed -isnot [bool] -or $entry.Kind -notin @('Source', 'Content', 'Bytes', 'Remove')) {
            throw 'Invalid deployment entry.'
        }
        if (Test-Path -LiteralPath $destination -PathType Container) { throw "Recovery destination is a directory: $destination" }
        $knownHashes = @()
        if ($entry.Existed) {
            if ($entry.OriginalHash -notmatch '^[0-9a-fA-F]{64}$') { throw 'Missing original deployment hash.' }
            $original = & $assertPath $entry.Backup $backupDirectory
            if (-not (Test-Path -LiteralPath $original -PathType Leaf) -or
                    (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ne $entry.OriginalHash) {
                throw "Deployment backup is missing or damaged: $original"
            }
            $entries += @{ Destination = $destination; Source = $original; ExpectedSourceHash = $entry.OriginalHash }
            $knownHashes += $entry.OriginalHash
        } else {
            $entries += @{ Destination = $destination; Remove = $true }
            $newFiles += $destination
        }
        if ($entry.Kind -ne 'Remove') {
            if ($entry.ExpectedHash -notmatch '^[0-9a-fA-F]{64}$') { throw 'Missing staged deployment hash.' }
            $knownHashes += $entry.ExpectedHash
        }
        $currentHash = if (Test-Path -LiteralPath $destination -PathType Leaf) {
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        } else { $null }
        if (-not $AllowChangedFiles -and $null -ne $currentHash) {
            if ($currentHash -notin $knownHashes) {
                throw "Installed file changed after this deployment: $destination. Review it before using -AllowChangedFiles."
            }
        }
        # Bind the exact validated state (including absence) through staging.
        # AllowChangedFiles permits the observed edit, not a later concurrent
        # replacement; the transaction still backs up that observed edit.
        $entries[-1].ExpectedDestinationHash = $currentHash
    }
    if (-not $entries.Count) { throw 'Deployment manifest has no entries.' }
    $directories = @()
    if ($saved.schema_version -eq 2) {
        foreach ($path in @($saved.created_directories)) {
            $directory = & $assertPath $path $rootPath
            if (-not @($newFiles | Where-Object { $_.StartsWith($directory + '\', [StringComparison]::OrdinalIgnoreCase) }).Count) {
                throw 'Recorded new directory does not contain a newly deployed file.'
            }
            if (Test-Path -LiteralPath $directory -PathType Leaf) { throw "Recorded deployment directory became a file: $directory" }
            $directories += $directory
        }
    }
    # Back up the current state before restoration too. A failed recovery write
    # rolls back to that state, and explicit changed-file recovery retains bytes.
    $result = Invoke-DarktideDeploymentTransaction -Root $rootPath -Entries $entries `
        -BackupRoot $BackupRoot -CreateDirectories
    $retained = @()
    foreach ($directory in @($directories | Sort-Object Length -Descending | Select-Object -Unique)) {
        try {
            $null = & $assertPath $directory $rootPath
            if (Test-Path -LiteralPath $directory -PathType Container) { [IO.Directory]::Delete($directory, $false) }
        } catch { $retained += [pscustomobject]@{ Path = $directory; Reason = $_.Exception.Message } }
    }
    $recovery = [ordered]@{
        source_manifest = $manifestPath; recovery_manifest = $result.Manifest
        status = if ($retained.Count) { 'files_restored_directories_retained' } else { 'restored' }
        retained_directories = $retained; changed_files_allowed = [bool] $AllowChangedFiles
    }
    $recovery | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $result.BackupDirectory 'recovery.json') -Encoding UTF8
    [pscustomobject] $recovery
}
