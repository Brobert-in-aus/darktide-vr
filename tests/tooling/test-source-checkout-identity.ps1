Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\tools\unattended\source-checkout-identity.ps1')
$tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $tempBase ('darktidevr-identity-test-' + [Guid]::NewGuid().ToString('N'))
$global:IdentityFixtureGitCalls = 0
$global:IdentityFixtureGitAvailable = $true
$global:IdentityFixtureGitFailure = $false
$global:IdentityFixtureGitDirty = $false
function Get-Command { param($Name, $ErrorAction) if ($global:IdentityFixtureGitAvailable) { [pscustomobject]@{Name='git'} } }
function git {
    $global:IdentityFixtureGitCalls++
    $global:LASTEXITCODE = 0
    if ($global:IdentityFixtureGitFailure) { $global:LASTEXITCODE = 1; return }
    switch ($args[2]) {
        'rev-parse' { if ($args[3] -eq '--show-toplevel') { return $testRoot }; return ('a' * 40) }
        'branch' { return 'fixture-branch' }
        'status' { if ($global:IdentityFixtureGitDirty) { return ' M fixture.lua' } }
        default { throw 'Unexpected fixture Git query.' }
    }
}
try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $result = Get-SourceCheckoutIdentity -Root $testRoot
    if ($result.available -or $result.reason -ne 'not_checkout' -or $null -ne $result.dirty -or $global:IdentityFixtureGitCalls) {
        throw 'An extracted package queried or inherited a parent checkout.'
    }
    # Worktrees have a .git file instead of a directory.
    [IO.File]::WriteAllText((Join-Path $testRoot '.git'), 'fixture marker')
    $global:IdentityFixtureGitAvailable = $false
    $result = Get-SourceCheckoutIdentity -Root $testRoot
    if ($result.available -or $result.reason -ne 'git_unavailable' -or $global:IdentityFixtureGitCalls) { throw 'Missing Git was not recorded.' }
    $global:IdentityFixtureGitAvailable = $true
    $global:IdentityFixtureGitFailure = $true
    $global:LASTEXITCODE = 23
    $result = Get-SourceCheckoutIdentity -Root $testRoot
    if ($result.available -or $result.reason -ne 'git_query_failed' -or $null -ne $result.head) { throw 'Failed Git query was reported as a revision.' }
    if ($global:LASTEXITCODE -ne 23) { throw 'Optional metadata overwrote the caller native exit status.' }
    $global:IdentityFixtureGitFailure = $false
    foreach ($dirty in @($false, $true)) {
        $global:IdentityFixtureGitDirty = $dirty
        $result = Get-SourceCheckoutIdentity -Root $testRoot
        if (-not $result.available -or $result.head -ne ('a' * 40) -or $result.branch -ne 'fixture-branch' -or $result.dirty -ne $dirty) {
            throw 'Checkout identity was not retained.'
        }
    }
    Write-Output 'source_checkout_identity=pass package_no_git missing_git failed_git worktree clean dirty'
} finally {
    foreach ($name in @('IdentityFixtureGitCalls','IdentityFixtureGitAvailable','IdentityFixtureGitFailure','IdentityFixtureGitDirty')) {
        Remove-Variable -Scope Global -Name $name -ErrorAction SilentlyContinue
    }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolved.StartsWith($tempBase + '\', [StringComparison]::OrdinalIgnoreCase) -or
            -not (Split-Path -Leaf $resolved).StartsWith('darktidevr-identity-test-')) { throw 'Refusing cleanup outside the temporary test directory.' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
