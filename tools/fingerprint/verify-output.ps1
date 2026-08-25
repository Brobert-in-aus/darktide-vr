param(
    [Parameter(Mandatory = $true)]
    [string] $Tool
)

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'darktidevr-fingerprint-' + [guid]::NewGuid().ToString('N'))
$settingsDirectory = Join-Path $testRoot 'bundle\application_settings'
$reportPath = Join-Path $testRoot 'report.json'

try {
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    @'
content_revision = "24680"
game_revision = "13579"
game_version = "test-build"
'@ | Set-Content -LiteralPath (Join-Path $settingsDirectory 'settings_common.ini')

    & $Tool --exe $Tool --game-root $testRoot --output $reportPath
    if ($LASTEXITCODE -ne 0) {
        throw "Fingerprint tool returned exit code $LASTEXITCODE"
    }

    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    if ($report.schema_version -ne 1) {
        throw 'Unexpected fingerprint schema version'
    }
    if ($report.sha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'SHA-256 is not a 64-character lowercase hexadecimal value'
    }
    if ($report.game_version -ne 'test-build' -or
        $report.game_revision -ne '13579' -or
        $report.content_revision -ne '24680') {
        throw 'Game settings metadata did not round-trip'
    }
    if ($report.safe_mode_required -ne $true) {
        throw 'Unknown test build must fail closed into safe mode'
    }
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
