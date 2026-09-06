Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$helper = Join-Path $PSScriptRoot '../../tools/stereo/advance-darktide-to-hub.ps1'
$errors = $null; $tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $helper).Path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$names = @('Assert-DarktideStartupOwner', 'Get-DarktideStartupState',
    'Wait-DarktideLogMatch', 'Send-DarktideKey')
foreach ($definition in $ast.FindAll({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $false)) {
    if ($definition.Name -in $names) { . ([scriptblock]::Create($definition.Extent.Text)) }
}
# No game or desktop input: process discovery uses this test's own process.
$testProcess = [System.Diagnostics.Process]::GetCurrentProcess()
function Get-Process {
    [CmdletBinding()] param([string] $Name, [int] $Id)
    if ($Name -eq 'Darktide' -or $Id -eq $testProcess.Id) { $testProcess }
}
$resolvedGameExe = $testProcess.Path
$GameProcessId = $testProcess.Id
$script:ownedProcess = $null
$script:ownedProcessStart = $null
$script:ownedLogPath = $null
$ConsoleLogRoot = Join-Path $env:TEMP ('dtvr-startup-test-' + [guid]::NewGuid().ToString('N'))
$path = Join-Path $ConsoleLogRoot 'console.log'
New-Item -ItemType Directory -Path $ConsoleLogRoot | Out-Null
try {
    Set-Content -LiteralPath $path -Value @(
        'Entering Game State StateTitle',
        'Entering Game State StateMainMenu',
        'DARKTIDEVR_PRESENTATION open view=main_menu_view active=true',
        'DARKTIDEVR_MENU_READINESS view=main_menu elapsed=0.6 list_input=true start_ready=true reason=ready'
    )
    $found = Wait-DarktideLogMatch -Patterns @(
        'DARKTIDEVR_MENU_READINESS view=main_menu .*start_ready=true reason=ready'
    ) -Deadline (Get-Date).AddSeconds(2)
    if ($found.Id -ne $testProcess.Id -or (Get-DarktideStartupState) -ne 'StateMainMenu') {
        throw 'Readiness did not bind to the expected process and state.'
    }
    Add-Content -LiteralPath $path -Value 'Entering Game State StateLoading'
    if ((Get-DarktideStartupState) -ne 'StateLoading') { throw 'Stale menu state was accepted.' }
    # This must return before even looking up the native foreground helper,
    # which is deliberately not loaded in this offline test.
    Send-DarktideKey -Process $testProcess -Keys '{ENTER}' -ExpectedState 'StateMainMenu'
    Send-DarktideKey -Process $testProcess -Keys ' ' -ExpectedState 'StateTitle'
    $script:ownedProcessStart = $testProcess.StartTime.AddSeconds(-1)
    $rejected = $false
    try { Assert-DarktideStartupOwner } catch { $rejected = $true }
    if (-not $rejected) { throw 'Process replacement did not stop startup automation.' }
    'startup_advance=pass'
} finally {
    Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ConsoleLogRoot -ErrorAction SilentlyContinue
}
