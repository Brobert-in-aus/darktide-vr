Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot '../../tools/stereo/start-darktide-vr.ps1'
$errors = $null; $tokens = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $source).Path, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$definitions = @($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Test-DarktideOfflineWorkloadReady'
}, $false))
if ($definitions.Count -ne 1) { throw 'Expected one production workload predicate.' }
. ([scriptblock]::Create($definitions[0].Extent.Text))
# Execute only the pure production predicate, never the launcher or a game.
$stereo = 'DARKTIDEVR_STEREO active mode=synchronized_sequential half_ipd=0.032'
$hub = '<<value>>StateGameplay:on_enter(): hub_ship<</value>>'
$mission = 'DARKTIDEVR_SOLO_BENCHMARK ready mission=cm_archives difficulty=3 host=singleplay'
$cases = @(
    @{name='hub'; text="$hub`n$stereo"; mission=''; expected=$true},
    @{name='hub_without_stereo'; text=$hub; mission=''; expected=$false},
    @{name='stereo_without_hub'; text=$stereo; mission=''; expected=$false},
    @{name='empty'; text=''; mission=''; expected=$false},
    @{name='solo'; text="$mission`n$stereo"; mission='cm_archives'; expected=$true},
    @{name='solo_without_stereo'; text=$mission; mission='cm_archives'; expected=$false},
    @{name='hub_not_requested_mission'; text="$hub`n$stereo"; mission='cm_archives'; expected=$false},
    @{name='mission_not_hub'; text="$mission`n$stereo"; mission=''; expected=$false},
    @{name='wrong_mission'; text="$mission`n$stereo"; mission='other'; expected=$false},
    @{name='wrong_host'; text=("$mission`n$stereo".Replace('singleplay','multiplayer')); mission='cm_archives'; expected=$false},
    @{name='invalid_difficulty'; text=("$mission`n$stereo".Replace('difficulty=3','difficulty=0')); mission='cm_archives'; expected=$false},
    @{name='mission_regex_literal'; text="$mission`n$stereo"; mission='cm_.*'; expected=$false}
)
foreach ($case in $cases) {
    $actual = Test-DarktideOfflineWorkloadReady -ConsoleText $case.text -SoloMission $case.mission
    if ($actual -isnot [bool] -or $actual -ne $case.expected) {
        throw "Unexpected readiness for $($case.name): $actual"
    }
}
Write-Output "offline_workload_readiness=pass cases=$($cases.Count) game_started=false"
