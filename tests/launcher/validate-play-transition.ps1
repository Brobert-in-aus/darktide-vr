[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Load only the two functions under test. Never execute launcher discovery,
# native input or the top-level launch script in this regression test.
$source = Join-Path $PSScriptRoot '..\..\tools\stereo\invoke-darktide-launcher-play.ps1'
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $source).Path, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count) {
    throw ($parseErrors | Out-String)
}
foreach ($name in @('Get-StartedDarktideProcess', 'Invoke-ConfirmedLauncherClick')) {
    $functions = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq $name
    }, $true))
    if ($functions.Count -ne 1) {
        throw "Expected exactly one function named $name"
    }
    . ([scriptblock]::Create($functions[0].Extent.Text))
}

if ('DarktideVrLauncherInput' -as [type]) {
    throw 'Run this test in a fresh PowerShell process; native input must not be loaded.'
}
Add-Type -TypeDefinition @'
using System;
public static class DarktideVrLauncherInput {
    public static int Clicks;
    public static bool Fail;
    public static void ClickClient(IntPtr window, int x, int y) {
        Clicks++;
        if (Fail) throw new InvalidOperationException("simulated foreground failure");
    }
}
'@

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

$started = Get-Date
$deadline = $started.AddMinutes(1)
$gamePath = 'X:\fixture\binaries\Darktide.exe'
$newGame = [pscustomobject]@{
    Id = 42; StartTime = $started.AddSeconds(1); Path = $gamePath
}
$oldGame = [pscustomobject]@{
    Id = 43; StartTime = $started.AddSeconds(-1); Path = $gamePath
}
$otherGame = [pscustomobject]@{
    Id = 44; StartTime = $started.AddSeconds(1); Path = 'X:\other\Darktide.exe'
}
$script:queryCount = 0
$script:appearAfter = 0
$script:fakeProcesses = @($oldGame, $otherGame, $newGame)
function Get-Process {
    param([string] $Name, [string] $ErrorAction)
    Assert-True ($Name -eq 'Darktide') 'Only query Darktide processes'
    $script:queryCount++
    if ($script:queryCount -gt $script:appearAfter) {
        $script:fakeProcesses
    }
}

$actual = Get-StartedDarktideProcess
Assert-True ($actual.Id -eq 42) 'Reject older and wrong-path processes'
$script:fakeProcesses = @($oldGame, $otherGame)
Assert-True ($null -eq (Get-StartedDarktideProcess)) 'No authenticated process must return null'

$script:fakeProcesses = @($newGame)
$actual = Invoke-ConfirmedLauncherClick -Window 1 -X 1 -Y 1
Assert-True ($actual.Id -eq 42 -and [DarktideVrLauncherInput]::Clicks -eq 0) `
    'A manual launch before activation must succeed without clicking'

$script:queryCount = 0
$script:appearAfter = 1
[DarktideVrLauncherInput]::Fail = $true
$actual = Invoke-ConfirmedLauncherClick -Window 1 -X 1 -Y 1
Assert-True ($actual.Id -eq 42 -and [DarktideVrLauncherInput]::Clicks -eq 1) `
    'A new authenticated game after activation failure must count as success'

$script:fakeProcesses = @($oldGame, $otherGame)
$script:appearAfter = 0
$deadline = (Get-Date).AddSeconds(-1)
$failed = $false
try {
    Invoke-ConfirmedLauncherClick -Window 1 -X 1 -Y 1 | Out-Null
}
catch {
    $failed = $_.ToString().Contains('simulated foreground failure')
}
Assert-True $failed 'Without a new authenticated game, preserve the activation error'

$script:fakeProcesses = @()
[DarktideVrLauncherInput]::Fail = $false
$before = [DarktideVrLauncherInput]::Clicks
$actual = Invoke-ConfirmedLauncherClick -Window 1 -X 1 -Y 1
Assert-True ($null -eq $actual -and [DarktideVrLauncherInput]::Clicks -eq $before + 1) `
    'A delivered click must not claim a confirmed game'

Write-Output 'launcher_play_transition=pass cases=6 native_input=none'
