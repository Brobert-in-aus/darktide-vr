Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop

function Invoke-DarktideDeploymentTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][hashtable[]] $Entries,
        [Parameter(Mandatory)][string] $BackupRoot
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    if ($rootPath -eq [IO.Path]::GetPathRoot($rootPath).TrimEnd('\', '/')) {
        throw 'A deployment root must be a specific installation directory.'
    }
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    $assertDestination = {
        param([string] $Path)
        $absolute = [IO.Path]::GetFullPath($Path)
        if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Deployment path escapes installation root: $absolute"
        }
        $cursor = $absolute
        while ($cursor -ne $rootPath) {
            if (Test-Path -LiteralPath $cursor) {
                $item = Get-Item -LiteralPath $cursor -Force
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "Deployment path contains a reparse point: $cursor"
                }
            }
            $cursor = Split-Path -Parent $cursor
        }
        if (Test-Path -LiteralPath $absolute -PathType Container) {
            throw "Deployment destination is a directory: $absolute"
        }
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $absolute) -PathType Container)) {
            throw "Deployment destination directory is missing: $absolute"
        }
        return $absolute
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $plan = @()
    foreach ($entry in $Entries) {
        $destination = & $assertDestination $entry.Destination
        if (-not $seen.Add($destination)) { throw "Duplicate deployment destination: $destination" }
        $kinds = @('Source', 'Content', 'Remove' | Where-Object { $entry.ContainsKey($_) })
        if ($kinds.Count -ne 1) { throw 'Each deployment entry requires exactly one Source, Content or Remove.' }
        $kind = $kinds[0]
        $source = $null
        if ($kind -eq 'Source') {
            if (-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)) { throw "Missing deployment source: $($entry.Source)" }
            $source = (Resolve-Path -LiteralPath $entry.Source).Path
        }
        if ($kind -eq 'Remove' -and $entry.Remove -ne $true) { throw 'Remove entries must explicitly select true.' }
        $plan += [pscustomobject]@{
            Destination = $destination; Kind = $kind; Source = $source
            Content = if ($kind -eq 'Content') { [string] $entry.Content } else { $null }
            Existed = $false; OriginalHash = $null; ExpectedHash = $null
            Backup = $null; Staged = $null
        }
    }
    $backupBase = [IO.Path]::GetFullPath($BackupRoot)
    if ($backupBase.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
            $backupBase.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Deployment backups must be outside the installation directory.'
    }
    $backupDirectory = Join-Path $backupBase ('deployment-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
    $manifestPath = Join-Path $backupDirectory 'manifest.json'
    $receipt = [ordered]@{ schema_version = 1; root = $rootPath; status = 'preparing'; entries = $plan }
    $saveManifest = { $receipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8 }
    $touched = [Collections.Generic.List[object]]::new()
    try {
        # Read and verify every source and original before changing installed bytes.
        for ($index = 0; $index -lt $plan.Count; $index++) {
            $entry = $plan[$index]
            $entry.Existed = Test-Path -LiteralPath $entry.Destination -PathType Leaf
            if ($entry.Existed) {
                $entry.OriginalHash = (Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash
                $entry.Backup = Join-Path $backupDirectory ("original-$index.bin")
                Copy-Item -LiteralPath $entry.Destination -Destination $entry.Backup
                if ((Get-FileHash -LiteralPath $entry.Backup -Algorithm SHA256).Hash -ne $entry.OriginalHash) {
                    throw "Original changed while backing up: $($entry.Destination)"
                }
            }
            if ($entry.Kind -ne 'Remove') {
                $entry.Staged = Join-Path $backupDirectory ("staged-$index.bin")
                if ($entry.Kind -eq 'Source') {
                    $entry.ExpectedHash = (Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256).Hash
                    Copy-Item -LiteralPath $entry.Source -Destination $entry.Staged
                    if ((Get-FileHash -LiteralPath $entry.Staged -Algorithm SHA256).Hash -ne $entry.ExpectedHash) {
                        throw "Source changed while staging: $($entry.Source)"
                    }
                } else {
                    [IO.File]::WriteAllBytes($entry.Staged, [Text.Encoding]::ASCII.GetBytes($entry.Content))
                    $entry.ExpectedHash = (Get-FileHash -LiteralPath $entry.Staged -Algorithm SHA256).Hash
                }
            }
        }
        $receipt.status = 'staged'
        & $saveManifest
        foreach ($entry in $plan) {
            $null = & $assertDestination $entry.Destination
            $existsNow = Test-Path -LiteralPath $entry.Destination -PathType Leaf
            if ($existsNow -ne $entry.Existed -or ($existsNow -and
                    (Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash -ne $entry.OriginalHash)) {
                throw "Destination changed after staging: $($entry.Destination)"
            }
            $touched.Add($entry)
            if ($entry.Kind -eq 'Remove') {
                if ($entry.Existed) { Remove-Item -LiteralPath $entry.Destination -Force }
                if (Test-Path -LiteralPath $entry.Destination) { throw "Removal did not complete: $($entry.Destination)" }
            } else {
                Copy-Item -LiteralPath $entry.Staged -Destination $entry.Destination -Force
                if ((Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash -ne $entry.ExpectedHash) {
                    throw "Deployment hash mismatch: $($entry.Destination)"
                }
            }
        }
        $receipt.status = 'committed'
        & $saveManifest
    } catch {
        $failure = $_.Exception.Message
        $rollbackFailures = [Collections.Generic.List[string]]::new()
        for ($index = $touched.Count - 1; $index -ge 0; $index--) {
            $entry = $touched[$index]
            try {
                $null = & $assertDestination $entry.Destination
                if ($entry.Existed) {
                    $currentHash = if (Test-Path -LiteralPath $entry.Destination -PathType Leaf) {
                        (Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash
                    } else { $null }
                    # A locked file can fail its write without changing bytes.
                    if ($currentHash -ne $entry.OriginalHash) {
                        Copy-Item -LiteralPath $entry.Backup -Destination $entry.Destination -Force
                    }
                    if ((Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash -ne $entry.OriginalHash) {
                        throw 'Restored bytes do not match the original.'
                    }
                } elseif (Test-Path -LiteralPath $entry.Destination -PathType Leaf) {
                    Remove-Item -LiteralPath $entry.Destination -Force
                    if (Test-Path -LiteralPath $entry.Destination) { throw 'New file remains after rollback.' }
                }
            } catch { $rollbackFailures.Add("$($entry.Destination): $($_.Exception.Message)") }
        }
        $receipt.status = if ($rollbackFailures.Count) { 'rollback_incomplete' } elseif ($touched.Count) { 'rolled_back' } else { 'failed_before_write' }
        $receipt['failure'] = $failure
        $receipt['rollback_failures'] = @($rollbackFailures.ToArray())
        try { & $saveManifest } catch { $rollbackFailures.Add("Manifest: $($_.Exception.Message)") }
        throw "Deployment failed: $failure Status=$($receipt.status). Backup=$backupDirectory. $($rollbackFailures -join '; ')"
    }
    [pscustomobject]@{ Status = $receipt.status; BackupDirectory = $backupDirectory; Manifest = $manifestPath; FileCount = $plan.Count }
}
