[CmdletBinding()]
param(
    [ValidateSet('Inspect', 'Apply')]
    [string] $Action = 'Inspect',
    [string] $SettingsPath = (Join-Path $env:APPDATA 'Fatshark\Darktide\user_settings.config')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# NumberOfLogicalProcessors includes SMT/hyperthreads and is deliberately unused.
$processors = @(Get-CimInstance -ClassName Win32_Processor)
$physicalCores = 0
foreach ($processor in $processors) {
    if ($null -eq $processor.NumberOfCores -or $processor.NumberOfCores -lt 1) {
        throw 'Physical core count unavailable; worker configuration was not changed.'
    }
    $physicalCores += [int]$processor.NumberOfCores
}
if ($physicalCores -lt 1) { throw 'No physical processors detected.' }
$workers = [Math]::Max(1, $physicalCores - 1)
Write-Output "worker_threads.physical_cores=$physicalCores recommended=$workers"
if ($Action -eq 'Inspect') { return }
if (Get-Process Darktide -ErrorAction SilentlyContinue) {
    throw 'Darktide must be closed before changing worker threads.'
}
$fullPath = [IO.Path]::GetFullPath($SettingsPath)
if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    throw "Darktide settings file not found: $fullPath"
}
$content = [IO.File]::ReadAllText($fullPath)
# Only the active top-level setting; leave detected_user_settings cache untouched.
$pattern = '(?m)^(max_worker_threads[ \t]*=[ \t]*)(?<value>\d+)[ \t]*\r?$'
$matchesFound = [regex]::Matches($content, $pattern)
if ($matchesFound.Count -ne 1) {
    throw 'Expected one active worker setting; configuration was not changed.'
}
$value = $matchesFound[0].Groups['value']
if ([int]$value.Value -ne $workers) {
    $content = $content.Remove($value.Index, $value.Length).Insert($value.Index, [string]$workers)
    [IO.File]::WriteAllText($fullPath, $content, [Text.UTF8Encoding]::new($false))
}
Write-Output "worker_threads.active=$workers"
