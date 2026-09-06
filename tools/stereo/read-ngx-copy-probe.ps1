[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $OutputPath,
    [Parameter(Mandatory)][string] $StatePath,
    [Parameter(Mandatory)][string] $QueuePath,
    [Parameter(Mandatory)][string] $CopyPath,
    [Parameter(Mandatory)][string] $BitmapPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$pairReport = & (Join-Path $PSScriptRoot 'read-ngx-pair-state-probe.ps1') `
    -OutputPath $OutputPath -StatePath $StatePath -QueuePath $QueuePath
$records = @(Get-Content -LiteralPath $CopyPath | ForEach-Object {
    $parts = $_ -split ' '
    if ($parts[0] -ne 'NGX_COPY') { throw 'Unknown copy record.' }
    $fields = @{}
    foreach ($part in $parts[1..($parts.Count-1)]) {
        $field = $part -split '=',2
        if ($field.Count -ne 2 -or $fields.ContainsKey($field[0])) { throw 'Malformed copy record.' }
        $fields[$field[0]] = $field[1]
    }
    $fields
})
if ($records.Count -ne 2 -or $records[0].phase -ne 'staged' -or $records[1].phase -ne 'exported') {
    throw 'Copy was not staged and exported exactly once.'
}
$record = $records[1]
foreach ($field in @('left_call','right_call','source','owned','readback','width','height','row_pitch','bytes')) {
    if ($records[0][$field] -cne $record[$field]) { throw "Copy identity changed: $field" }
}
foreach ($entry in $records) {
    if ($entry.result -ne '0x00000000' -or $entry.publication -ne '0') { throw 'Copy reported failure or publication.' }
}
foreach ($field in @('left_call','right_call','width','height','row_pitch','bytes','left_nonblack','right_nonblack','left_hash','right_hash')) {
    if ($record[$field] -notmatch '^\d+$') { throw 'Invalid copy numeric field.' }
    $record[$field] = [uint64]::Parse($record[$field])
}
$resources = @($record.source,$record.owned,$record.readback)
foreach ($resource in $resources) {
    if ($resource -notmatch '^[0-9A-F]{16}$' -or [Convert]::ToUInt64($resource,16) -eq 0) { throw 'Invalid owned copy resource.' }
}
if (@($resources | Select-Object -Unique).Count -ne 3) { throw 'Private resource aliases its source.' }
$pair = @($pairReport.Pairs | Where-Object { $_.LeftCall -eq $record.left_call -and $_.RightCall -eq $record.right_call })
if ($pair.Count -ne 1 -or $pair[0].Output -cne $record.source -or $pair[0].EndState -ne 8 -or
    $pair[0].Width -ne $record.width -or $pair[0].Height -ne $record.height -or
    $record.row_pitch -lt $record.width*4 -or $record.row_pitch%256 -ne 0 -or
    $record.bytes -lt ($record.height-1)*$record.row_pitch+$record.width*4) {
    throw 'Copy lacks its exact known-state GPU-complete source pair.'
}
$bitmap = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $BitmapPath).Path)
if ($bitmap.Length -ne 54+$record.width*$record.height*4 -or
    [BitConverter]::ToUInt16($bitmap,0) -ne 0x4d42 -or [BitConverter]::ToUInt32($bitmap,10) -ne 54 -or
    [BitConverter]::ToUInt32($bitmap,14) -ne 40 -or [BitConverter]::ToInt32($bitmap,18) -ne $record.width -or
    [BitConverter]::ToInt32($bitmap,22) -ne -[int64]$record.height -or
    [BitConverter]::ToUInt16($bitmap,28) -ne 32 -or [BitConverter]::ToUInt32($bitmap,30) -ne 0) {
    throw 'Exported bitmap is incomplete or has the wrong dimensions/format.'
}
$eyePixels = $record.width/2*$record.height
if ($record.left_nonblack -eq 0 -or $record.right_nonblack -eq 0 -or
    $record.left_nonblack -gt $eyePixels -or $record.right_nonblack -gt $eyePixels) {
    throw 'Generated readback has an empty or invalid eye pixel count.'
}
[pscustomobject]@{
    PrivateOutputCopyVerified=$true; GpuReadbackCompleted=$true
    LeftCall=$record.left_call; RightCall=$record.right_call
    Width=$record.width; Height=$record.height
    LeftNonblackPixels=$record.left_nonblack; RightNonblackPixels=$record.right_nonblack
    EyeHashesDiffer=$record.left_hash -ne $record.right_hash
    BitmapPath=(Resolve-Path -LiteralPath $BitmapPath).Path
    GeneratedXrPublicationVerified=$false; VisualAcceptance='unverified'
}
