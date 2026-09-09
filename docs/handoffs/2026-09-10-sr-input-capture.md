# DLSS SR input capture — 10 September

Development continues under the user's stereo/DLSS/engine performance priorities.
This was a short input-observation trial, not gameplay revalidation or an FPS
comparison. The accepted installation is restored and no game/viewer remains.

## Trial and restoration

Ready preflight passed with 600 submitted frames, zero non-rendered frames and
VirtualDesktopXR at 2496×2688 per eye. Proximity override was disabled/status
checked before the live session, then restored with Enable/Status afterwards.

Focused source `8c01989`, PR #244, was built from accepted native `23345e5` with
only optional SR observation changes. DLL SHA-256:
`61B6B09A3785AC1FEC69DD64CEE619311AEF49F2D0B5757086E964E478AA5957`.
Both native locations and the existing NGX flag were updated through an exact-
hash deployment transaction. The flag retained all previous settings and added
only `observe_sr_inputs=1`. Lua, viewer and shaders were not deployed.

Launch used `-SkipDeploymentSync -EnterPsykhanium -DurationSeconds 300` while
the game was closed. The launcher compiled the actual installed 50 Lua chunks
and the checkout's 69 chunks. Fresh synchronized-sequential initialization and
nonzero `shared_ready` were observed; the launch reported 2,345 fresh shared
pairs and 15,444 XR submissions before closing. Those totals establish delivery,
not image quality. This launch used standard pair waiting because the historical
precise-wait environment override was not set; it must not be compared to the
accepted precise-wait performance runs. Set `DTVR_XR_PRECISE_PAIR_WAIT=1` in the
launch process for subsequent performance sessions, restoring its old value
afterwards.

After the bounded capture, the owned game was asked to close. It exited with
code 0 and the runner finished. The transaction restored both DLLs and the flag
without permitting changed-file overrides. Both DLLs again hash to
`FCCDD0DE699F9D50D2BD316792829D4EE5700843D925D194BE4DF1F3EEB02369`;
the flag hashes to `DA9D4CF438C387D198C02D38AD480074DE81F101200D7E52F3D544D0A8094531`.
All nine existing trial-plan files found on disk, including older alternatives,
pass their payload/baseline hash checks. No staged plan was changed.

## Observed inputs

The strict schema-2 reader accepts 64/64 complete, successful SR evaluations
(calls 252–377), with all 512 scalar values valid. Two distinct feature handles
have stable lifetimes 5 and 6, with 32 observations each. In call order they
alternate in 32 pairs; each pair uses identical jitter, and each lifetime has
32 distinct jitter samples. This is call-order pairing, not independent eye or
pose attribution. All observed reset values are zero and pre-exposure is one.

| Input | Observed extent / value |
| --- | --- |
| Colour | 1664×1792, format 26 |
| Output | 2496×2688, format 26 |
| Depth | 1664×1792, format 19 |
| Motion vectors | 1664×1792, format 33 |
| Render subrect | 1664×1792 |
| Motion-vector scale | −1664, −1792 |
| Transparency, exposure, bias-current-colour masks | Successful null queries |

Each non-null resource role uses one stable pointer across both feature
lifetimes. Sequential rendering may legitimately reuse transient textures;
pointer aliasing does not prove overlapping GPU use or shared temporal history.
Two handles also do not prove correct per-eye history. No pixels or complete
motion/projection conventions were captured, and no HUD-blur fix is established.
The data rules out an always-reset SR path **within these 64 calls**; it does
not describe startup before admission or later transitions.

## Receipts and next work

Local capture: `artifacts/diagnostics/sr-inputs-20260910/` with original SR log,
strict JSON, summary, associated NGX/Streamline records and initialization lines.
SR source SHA-256:
`f3e0e386897344a87d6d776c6109f76b0668954d5d90be83fbcaf4292ef0115a`.

Local operational receipts under `artifacts/unattended`:
`sr-inputs-ready-20260910`, `sr-inputs-live-launch-20260910.log`,
`sr-inputs-live-deployment-20260910.json`, `sr-inputs-live-restored-20260910.json`,
and `sr-inputs-post-trial-status-20260910.json`.

Continue engine preparation/culling dependency analysis and identify a bounded
measurement seam that distinguishes world-update reuse from per-eye render work.
For DLSS, establish eye/pose ownership and motion conventions before changing
jitter, masks or reset. Worn observation remains required for visual acceptance.
