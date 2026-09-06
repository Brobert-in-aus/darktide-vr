[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Extract only key dispatch. Stub native focus and COM input so this test
# cannot activate windows or inject input into the developer's desktop.
$source = Join-Path $PSScriptRoot '..\..\tools\stereo\advance-darktide-to-hub.ps1'
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $source).Path, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$functionAst = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Send-DarktideKey'
}, $true))
if ($functionAst.Count -ne 1) { throw 'Missing startup key dispatcher' }
. ([scriptblock]::Create($functionAst[0].Extent.Text))
Add-Type -TypeDefinition @'
using System;
public static class DarktideStartupFocus {
    public static uint ForegroundProcess;
    public static IntPtr GetForegroundWindow() { return IntPtr.Zero; }
    public static uint GetWindowThreadProcessId(IntPtr window, out uint processId) {
        processId = ForegroundProcess;
        return 1;
    }
}
'@
$script:sent = @()
$script:startupKeyAttempts = @{ StateTitle = 0 }
$script:observedState = 'StateTitle'
function Assert-DarktideStartupOwner { }
function Get-DarktideStartupState { return $script:observedState }
function New-Object {
    param([string] $ComObject)
    if ($ComObject -ne 'WScript.Shell') { throw 'Unexpected COM request' }
    $fakeShell = [pscustomobject]@{}
    $fakeShell | Add-Member ScriptMethod AppActivate { throw 'Focus stealing forbidden' }
    $fakeShell | Add-Member ScriptMethod SendKeys { param($keys) $script:sent += $keys }
    return $fakeShell
}
$process = Get-Process -Id $PID
[DarktideStartupFocus]::ForegroundProcess = 0
Send-DarktideKey -Process $process -Keys '{ENTER}' -ExpectedState 'StateTitle'
if ($script:sent.Count) { throw 'Background startup injected input' }
[DarktideStartupFocus]::ForegroundProcess = $PID
Send-DarktideKey -Process $process -Keys ' ' -ExpectedState 'StateTitle'
if ($script:sent.Count -ne 1 -or $script:sent[0] -ne ' ') {
    throw 'Foreground startup did not deliver its key'
}
[DarktideStartupFocus]::ForegroundProcess = 0
Send-DarktideKey -Process $process -Keys '{ENTER}' -ExpectedState 'StateTitle'
if ($script:sent.Count -ne 1) { throw 'Alt-Tab did not suspend input' }
[DarktideStartupFocus]::ForegroundProcess = $PID
$script:observedState = 'StateGameplay'
Send-DarktideKey -Process $process -Keys ' ' -ExpectedState 'StateTitle'
if ($script:sent.Count -ne 1) { throw 'Stale title readiness injected gameplay input' }
if ($script:startupKeyAttempts.StateTitle -ne 1) { throw 'Skipped keys counted as attempts' }
Write-Output 'startup_focus=pass'
