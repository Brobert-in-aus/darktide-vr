# Batch original stereo copy transitions

The FG consumer ingests a packed original image into two retained eye textures.
Previously each eye copy transitioned the same packed source from COMMON to
COPY_SOURCE and back. The consumer now transitions that source once, transitions
both destinations together, copies both eye regions, then restores all three
resources together.

Each ingested original pair uses two barrier API calls instead of four, and six
resource transitions instead of eight. Copy regions, destination selection,
pose metadata, ready/consumed fence ownership, and generated-image ordering are
unchanged. The generated-image copy already batches its shared source transition.
No shader, game-side stereo or DLSS history changes are included.

Windows x64 Release `darktidevr-xr-harness` builds successfully. The synthetic
consumer candidate has SHA-256
`262E84EA040DF91CBD0DEB935DC041667C53A6DCBF0D00BCB93EA9F56ACBE00C`;
the preceding `69A58452...` consumer is preserved locally for comparison.
The accepted physical viewer is not replaced. This small command reduction is
not an FPS claim; mission trials measure its practical effect separately.
