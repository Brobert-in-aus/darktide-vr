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

The 120-second cm_archives/difficulty-3 trial at simulator 120 Hz, FG On,
cap 120, DLSS Quality, Reflex On and normal streaming delivered 119.37 distinct
pairs/s (59.69 originals plus 59.69 generated), with 0.63 cached repeats/s.
Board telemetry averaged 75.31% GPU busy and 286.47 W. This does not establish
an FPS gain over the earlier 119.41–119.51 FPS controls. Shutdown was clean,
pose mismatches were zero and exact installation restoration passed.
Local evidence: `synthetic-solo-xr-barriers-120-20260910` and
`solo-xr-barriers-120-gpu-20260910.csv` under ignored artifacts.

The corresponding 144 Hz/Unlimited stretch trial delivered 142.27 distinct
pairs/s with 1.63 cached repeats/s, 94.79% GPU busy and 334.25 W board power.
The earlier consumer measured 141.85 FPS/331.67 W; these single-run differences
do not establish an improvement. Clean shutdown, zero pose mismatches and
exact restoration passed. Evidence: `synthetic-solo-xr-barriers-144-20260910`
and `solo-xr-barriers-144-gpu-20260910.csv`. Physical 144 Hz remains unavailable
in the Ready recheck recorded in 144HZ-STRETCH.md.
