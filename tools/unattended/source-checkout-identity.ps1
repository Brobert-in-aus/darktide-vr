function Get-SourceCheckoutIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Root)
    $Root = (Resolve-Path -LiteralPath $Root).Path
    $identity = [ordered]@{ available = $false; reason = 'not_checkout'; head = $null; branch = $null; dirty = $null; status = @() }
    # An extracted package may sit inside another repository. Never identify
    # that parent checkout as the source of the package's binaries and Lua.
    if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) { return [pscustomobject] $identity }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        $identity.reason = 'git_unavailable'
        return [pscustomobject] $identity
    }
    $previousExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $previousExitValue = if ($previousExitCode) { $previousExitCode.Value } else { $null }
    try {
        $top = @(& git -C $Root rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or $top.Count -ne 1 -or
                -not [IO.Path]::GetFullPath([string] $top[0]).TrimEnd('\', '/').Equals(
                    [IO.Path]::GetFullPath($Root).TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Checkout root differs from the selected source root.'
        }
        $head = @(& git -C $Root rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or $head[0] -notmatch '^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$') { throw 'Checkout revision unavailable.' }
        $branch = @(& git -C $Root branch --show-current 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Checkout branch unavailable.' }
        $status = @(& git -C $Root status --short 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Checkout status unavailable.' }
        $identity.available = $true; $identity.reason = 'checkout'
        $identity.head = [string] $head[0]; $identity.branch = $branch -join ''
        $identity.dirty = $status.Count -gt 0; $identity.status = $status
    } catch { $identity.reason = 'git_query_failed' }
    finally {
        # Optional metadata must not overwrite the caller's native exit status.
        if ($previousExitCode) { $global:LASTEXITCODE = $previousExitValue }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }
    return [pscustomobject] $identity
}
