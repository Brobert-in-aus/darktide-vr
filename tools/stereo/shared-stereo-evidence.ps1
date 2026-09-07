function Add-SharedStereoEvidence {
    param([hashtable] $Evidence, [string] $Line)
    if ($Line -match '^openxr\.(fresh_shared_pairs|submitted_frames|presentation)=(.*)$') {
        $key = $Matches[1]
        # A second summary is ambiguous; never combine separate runs.
        if ($Evidence.ContainsKey($key)) { $Evidence[$key] = 'duplicate' }
        else { $Evidence[$key] = $Matches[2] }
    }
}

function Assert-SharedStereoEvidence {
    param([hashtable] $Evidence)
    [uint64] $pairs = 0
    [uint64] $frames = 0
    if ($Evidence['presentation'] -ne 'shared-eye-projection' -or
            -not [uint64]::TryParse([string]$Evidence['fresh_shared_pairs'], [ref]$pairs) -or
            -not [uint64]::TryParse([string]$Evidence['submitted_frames'], [ref]$frames) -or
            $pairs -eq 0 -or $frames -eq 0) {
        throw 'Automatic gameplay run did not verify shared stereo delivery. Flat fallback or an incomplete viewer summary is insufficient; inspect the current game log for stereo initialization.'
    }
    Write-Output "stereo.delivery=verified fresh_shared_pairs=$pairs submitted_frames=$frames visual_acceptance=pending"
}
