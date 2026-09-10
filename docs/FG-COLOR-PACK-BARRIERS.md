# Framegen packed-color copy barriers

Continuous framegen preparation packs two owned eye snapshots into the wide
backbuffer. The previous implementation issued six barrier calls: one for the
target and two for each eye, then one to restore the target. The new helper
batches all independent transitions before the copies and restores them after
both copies, reducing this to two calls. It retains the same six transitions,
copy regions, queue waits and final states. If both eyes share one source, that
source is transitioned once in each direction.

The caller still validates extents and formats and supplies a separate target.
This does not combine DLSS histories, remove an eye evaluation or change frame
selection. The existing earlier input-copy batching is a separate change.

Windows x64 Release native builds pass. The extended `stereo_input_copy` test
uses WARP with the DirectX debug layer, checks exact bytes in both packed eyes,
repeats with a shared source and verifies restored states without warnings or
errors. It checks two copies and two barrier calls in both cases.

The focused candidate is based on `37e2cde`, the diagnostic-cleanup baseline,
with only this helper and call-site change. Its DLL SHA-256 is
`830F70BA37AFD2CCEE42611BB1AC7AD8DF7C1277046DF51AB113D2E3D3F42E1B`.
The 120 Hz stationary SoloPlay FG trial delivered 119.57 distinct pairs/s,
split evenly between original and generated frames, with 0.41 cached repeats/s.
Clean exit, zero pose mismatches and exact installation restoration passed.
The matching baseline delivered 119.88 distinct pairs/s and 0.12 cached
repeats/s, also exiting cleanly with zero pose mismatches and exact restoration.
This comparison establishes no FPS improvement; the lower candidate result
does not justify promoting it to the accepted installation. No physical
visual acceptance is claimed. Evidence: ignored
`synthetic-solo-fg-color-pack-120-a-20260910` artifacts.
The baseline evidence is `synthetic-solo-fg-color-pack-control-120-a-20260910`.
That run required focus recovery from the simulator preview during title-screen
startup; measurement began only after mission readiness, with the normal warmup.
