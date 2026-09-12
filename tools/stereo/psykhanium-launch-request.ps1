# A launch owns one request. Never restore an older automation command, and
# never let delayed cleanup delete a newer launch's still-armed request.
function Set-PsykhaniumLaunchRequest {
    param(
        [Parameter(Mandatory)][string] $GameRoot,
        [Parameter(Mandatory)][ValidateSet('enter','disabled')][string] $Action
    )
    $path = Join-Path $GameRoot 'mods\darktidevr\darktidevr_enter_psykhanium.flag'
    $content = "$Action`nlaunch_id=$([guid]::NewGuid().ToString('N'))"
    Set-Content -LiteralPath $path -Value $content -Encoding ascii
    [pscustomobject]@{ Path = $path; Content = $content }
}

function Clear-PsykhaniumLaunchRequest {
    param([Parameter(Mandatory)] $Request)
    if (-not (Test-Path -LiteralPath $Request.Path -PathType Leaf)) { return }
    $current = (Get-Content -LiteralPath $Request.Path -Raw).Trim()
    if ($current -eq $Request.Content -or $current -eq 'consumed') {
        Remove-Item -LiteralPath $Request.Path -Force
    }
}
