[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $SourceTree,
    [Parameter(Mandatory = $true)] [string] $HistoryDatabase,
    [Parameter(Mandatory = $true)] [string] $ThreadId,
    [Parameter(Mandatory = $true)] [int] $FirstExcludedOrdinal,
    [Parameter(Mandatory = $true)] [int] $LastExcludedOrdinal,
    [string] $IncludePathRegex = '.*',
    [switch] $SkipUnappliedUpdates,
    [switch] $Forward
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$temporaryRoot = [IO.Path]::GetTempPath()
$nonce = [guid]::NewGuid().ToString('N')
$temporaryIndex = Join-Path $temporaryRoot "darktidevr-replay-$nonce.index"
$temporaryPatch = Join-Path $temporaryRoot "darktidevr-replay-$nonce.patch"
$temporaryContent = Join-Path $temporaryRoot "darktidevr-replay-$nonce.content"
$previousIndex = $env:GIT_INDEX_FILE

try {
    $env:GIT_INDEX_FILE = $temporaryIndex
    & git -C $workspaceRoot read-tree $SourceTree
    if ($LASTEXITCODE -ne 0) { throw 'Unable to seed temporary index.' }

    $order = if ($Forward) { 'ASC' } else { 'DESC' }
    $query = @"
SELECT rollout_ordinal, item_json
FROM thread_items
WHERE thread_id='$ThreadId'
  AND item_type='fileChange'
  AND rollout_ordinal>$FirstExcludedOrdinal
  AND rollout_ordinal<$LastExcludedOrdinal
ORDER BY rollout_ordinal $order;
"@
    $rowsJson = (& sqlite3 -json $HistoryDatabase $query) -join "`n"
    $rows = $rowsJson | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read change history.' }

    $reversed = 0
    $skipped = 0
    foreach ($row in $rows) {
        $ordinal = [int] $row.rollout_ordinal
        $item = $row.item_json | ConvertFrom-Json
        foreach ($change in $item.changes) {
            $absolutePath = [string] $change.path
            if ($absolutePath -notmatch $IncludePathRegex) {
                continue
            }
            $prefix = $workspaceRoot + '\'
            if (-not $absolutePath.StartsWith(
                    $prefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Recorded path is outside workspace: $absolutePath"
            }
            $relativePath = $absolutePath.Substring($prefix.Length).Replace('\', '/')
            $kind = [string] $change.kind.type
            $diffText = [string] $change.diff

            if ($kind -eq 'add') {
                $output = & git -C $workspaceRoot rm --cached `
                    --ignore-unmatch -- $relativePath 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not reverse addition of $relativePath`n$output"
                }
            } elseif ($kind -eq 'delete') {
                [IO.File]::WriteAllText(
                    $temporaryContent, $diffText, [Text.UTF8Encoding]::new($false))
                $blob = (& git -C $workspaceRoot hash-object -w $temporaryContent).Trim()
                if ($LASTEXITCODE -ne 0 -or $blob -notmatch '^[0-9a-f]{40}$') {
                    throw "Could not restore deleted content for $relativePath"
                }
                $cacheInfo = "100644,$blob,$relativePath"
                & git -C $workspaceRoot update-index --add --cacheinfo $cacheInfo
                if ($LASTEXITCODE -ne 0) {
                    throw "Could not index restored deletion for $relativePath"
                }
            } elseif ($kind -eq 'update') {
                $patchText = @"
diff --git a/$relativePath b/$relativePath
--- a/$relativePath
+++ b/$relativePath
$diffText
"@
                [IO.File]::WriteAllText(
                    $temporaryPatch, $patchText, [Text.UTF8Encoding]::new($false))
                if ($Forward) {
                    $output = & git -C $workspaceRoot apply --cached `
                        --ignore-space-change --whitespace=nowarn `
                        $temporaryPatch 2>&1
                } else {
                    $output = & git -C $workspaceRoot apply -R --cached `
                        --ignore-space-change --whitespace=nowarn `
                        $temporaryPatch 2>&1
                }
                if ($LASTEXITCODE -ne 0) {
                    if ($SkipUnappliedUpdates) {
                        "skipped_update=$ordinal path=$relativePath"
                        $skipped++
                        continue
                    }
                    throw "Could not reverse update $ordinal of $relativePath`n$output"
                }
            } else {
                throw "Unsupported change kind '$kind': $relativePath"
            }
            $reversed++
        }
    }

    $tree = (& git -C $workspaceRoot write-tree).Trim()
    if ($LASTEXITCODE -ne 0 -or $tree -notmatch '^[0-9a-f]{40}$') {
        throw 'Unable to write reconstructed tree.'
    }
    "reversed_changes=$reversed"
    "skipped_changes=$skipped"
    "reconstructed_tree=$tree"
} finally {
    if ($null -eq $previousIndex) {
        Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
    } else {
        $env:GIT_INDEX_FILE = $previousIndex
    }
    foreach ($path in @($temporaryIndex, $temporaryPatch, $temporaryContent)) {
        $resolved = [IO.Path]::GetFullPath($path)
        if ($resolved.StartsWith(
                $temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
            (Test-Path -LiteralPath $resolved)) {
            Remove-Item -LiteralPath $resolved -Force
        }
    }
}
