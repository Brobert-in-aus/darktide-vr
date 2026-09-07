[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sourcePath = Join-Path $repo 'tools/stereo/start-darktide-vr.ps1'
$tokens = $parseErrors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw $parseErrors[0] }
$launchTry = @($tree.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.TryStatementAst] })[-1]
$cleanupText = $launchTry.Finally.Extent.Text
$cleanup = [ScriptBlock]::Create($cleanupText.Substring(1, $cleanupText.Length - 2))
# Initialize the launch's optional owners without invoking its setup, headset,
# filesystem writes or process start/stop. The cleanup body itself is real.
foreach ($variable in $launchTry.Finally.FindAll({ param($node)
    $node -is [Management.Automation.Language.VariableExpressionAst]
}, $true)) {
    $name = $variable.VariablePath.UserPath
    if ($name -notin @('null','true','false','_','ErrorActionPreference') -and
            -not (Get-Variable -Name $name -ErrorAction SilentlyContinue)) {
        Set-Variable -Name $name -Value $null
    }
}
$script:events = [Collections.Generic.List[string]]::new()
$script:failCleanup=$true
$script:failStop=$false
function Test-Path { param($LiteralPath,$PathType) return $LiteralPath -eq 'locked-start-request' }
function Remove-Item { param($LiteralPath,[switch]$Force)
    if ($script:failCleanup) { throw 'start request is locked' }
    $script:events.Add('remove-start')
}
function Set-Content { param($LiteralPath,$Value,$Encoding) $script:events.Add("restore:$LiteralPath=$Value") }
function Get-Process { param($Name,$ErrorAction)
    return @([pscustomobject]@{Id=90;Path='C:\fixture\Darktide.exe'},
        [pscustomobject]@{Id=91;Path='C:\fixture\Darktide.exe'},
        [pscustomobject]@{Id=92;Path='C:\other\Darktide.exe'})
}
function Stop-Process { [CmdletBinding()]param([Parameter(ValueFromPipeline)]$InputObject,[switch]$Force)
    process {
        $script:events.Add("stop:$($InputObject.Id)")
        if ($script:failStop) { throw 'fixture process stop denied' }
    }
}
function Clear-PsykhaniumLaunchRequest { param($Request) $script:events.Add('retire-request') }
$characterStartFlag='locked-start-request'
$gameplayInputFlagPath='gameplay-flag'; $gameplayInputFlagOriginal='enabled'
$xrLaunchOwnsGame=$true; $xrRunnerStarted=$true; $offlineNoHeadset=$false
$preLaunchGameProcessIds=[Collections.Generic.HashSet[int]]::new(); [void]$preLaunchGameProcessIds.Add(90)
$expectedGamePath='C:\fixture\Darktide.exe'
$psykhaniumRequest=@{owner='fixture'}
$launchFailure=$null
$caught=$null
try { & $cleanup } catch { $caught=$_ }
if (-not $caught -or $caught.ToString() -notmatch 'start request is locked') { throw 'Cleanup failure was hidden.' }
foreach ($expected in @('restore:gameplay-flag=enabled','stop:91','retire-request')) {
    if (-not $script:events.Contains($expected)) { throw "Early cleanup failure skipped $expected" }
}
if ($script:events.Contains('stop:90') -or $script:events.Contains('stop:92')) { throw 'Cleanup selected an unrelated process.' }
# Use the launch's actual catch/finally clauses around a supplied failing body.
$script:events.Clear()
$catchText = ($launchTry.CatchClauses | ForEach-Object { $_.Extent.Text }) -join "`n"
$failingLaunch = [ScriptBlock]::Create("try { throw 'original launch failure' }`n" + $catchText + "`nfinally " + $cleanupText)
$caught=$null; $launchFailure=$null
try { & $failingLaunch } catch { $caught=$_ }
if (-not $caught -or $caught.ToString() -ne 'original launch failure') { throw 'Cleanup replaced the original launch failure.' }
if (-not $script:events.Contains('retire-request')) { throw 'Failure-path cleanup did not finish.' }
$script:events.Clear(); $launchFailure=$null; $script:failStop=$true
$caught=$null
try { & $cleanup } catch { $caught=$_ }
if (-not $caught -or $caught.ToString() -notmatch 'start request is locked' -or
        $caught.ToString() -notmatch 'fixture process stop denied' -or
        -not $script:events.Contains('retire-request')) { throw 'Multiple failures did not aggregate and finish cleanup.' }
$script:events.Clear(); $script:failStop=$false; $script:failCleanup=$false
& $cleanup
foreach ($expected in @('remove-start','restore:gameplay-flag=enabled','stop:91','retire-request')) {
    if (-not $script:events.Contains($expected)) { throw "Healthy cleanup skipped $expected" }
}
Write-Output 'launcher_cleanup_continuation=pass'
