# Synthetic stereo frame-generation benchmark

Frame generation is an explicit On/Off variable in
`tools/stereo/run-synthetic-framegen-benchmark.ps1`. It runs the production
dual-view hub-spin workload through the existing XR consumer and a local
OpenXR simulator. The consumer releases both original and generated rings,
so the producer can sustain generation beyond its three output buffers.

The user prefers stereo DLSS frame generation over Virtual Desktop SSW, but
allows dropping it if its overhead outweighs its benefit. Compare rendered
source-pair rate and distinct submitted frames, not merely the simulator's
90 Hz submission count. Cached repeats do not count as generated-frame gains.
SSW is unavailable in this simulator and is not an on/off variable here.

## Run contract

Build `darktidevr-xr-harness` in `build/xr-frame-stage-timing`. Prepare the pinned
[simulator dependency and shutdown fix](../tools/simulator/README.md), then pass
its manifest and the explicitly verified DLL hash:

```powershell
tools/stereo/run-synthetic-framegen-benchmark.ps1 -FrameGeneration On -FrameRateLimit Unlimited -RuntimeJson PATH_TO_SIMULATOR_JSON -RuntimeSha256 VERIFIED_DLL_SHA256 -OutputDirectory artifacts/unattended/fg-on-run1 -DurationSeconds 120
```

Repeat with `Off`, using a new output directory. Keep the native DLL, consumer,
runtime, eye resolution, cap policy and other settings identical. Use repeated
on/off runs in alternating or balanced ABBA order before deciding whether a
difference persists.
`FrameRateLimit` defaults to `Preserve`; `Unlimited` explicitly sets both active
Reflex cap fields to zero for that run. The saved cap was 120 FPS, so the initial
capped checks are not an uncapped measure of rendering overhead. The cached
detected-user settings are preserved.

The default simulator profile is Quest 3, 64 mm IPD and 2112×2304 per eye, with
desktop preview disabled. `EyeWidth` and `EyeHeight` are explicit parameters.
This is a separate benchmark baseline from the VirtualDesktopXR frusta used by
the original synthetic-head publisher. Do not run that publisher concurrently;
the XR consumer publishes the simulated head state itself.

The wrapper snapshots settings and flags before launch, writes local recovery
copies before mutation, selects the runtime only through `XR_RUNTIME_JSON`,
and restores the previous process environment. The game launcher owns game
shutdown. The consumer's `--stop-file` requests clean shutdown; `--flush-log`
retains redirected evidence. A bounded teardown wait prevents restoring files
while Windows is still closing the game. Restoration is verified against the
saved bytes. Failed trials retain their evidence and recovery manifest.

An optional focused native trial requires all three of `NativeDllPath`,
`NativeSha256` and `ExpectedInstalledNativeSha256`. Both installed copies must
match the expected baseline; both are restored after the simulator run. The
default performs no native deployment and always skips blanket deployment sync.
The simulator run does not certify physical XR readiness or worn acceptance.

`-ClusterLightTrace` is an explicit diagnostic option. It temporarily owns the
bootstrap trace flag, requires a fresh trace header matching the launched game
PID, and restores the flag afterward. This requires the native deferred-trace
selection fix; older native builds can leave the flag unconsumed in offline
mode. Keep trace-enabled captures separate from performance controls.

## Functionality evidence, 10 September 2026

The first simulator control delivered 2,407 fresh stereo pairs with zero pose
mismatches and no generated frames. The first On attempt correctly failed the
generation gate: continuous submission stopped with `missing_state_api`.
The engine had resolved `slDLSSGSetOptions` but never `slDLSSGGetState` in this
startup path; merely observing engine lookups did not supply the latter.

The native fix explicitly resolves that function before submitting stereo tags.
It accepts only a successful non-null result, serializes with the feature API
lock, and retries delayed availability at most eight times at one-second
intervals. Until available, it leaves original stereo running without starting
an input lifetime that cannot be tracked. Completion-ticket validation remains
unchanged.

Focused native `9d11a26`, based on accepted `23345e5`, passed its resolver and
native hook tests. DLL SHA-256:
`D2D84673FBEB7BD8663970B71E6E50AE3AB058EC62CEE799AA789E87C2F0180F`.
The subsequent 30-second On check submitted 990 fresh original pairs and 977
generated stereo frames, with zero pose mismatches. Native status recorded
1,691 publications, both-eye version-3 completion tickets with status zero,
and zero busy output slots at the final health sample. Publication and consumer
submission counts differ because the 90 Hz consumer selects from the source
stream; they are not interchangeable measures.

The accepted native SHA-256
`FCCDD0DE699F9D50D2BD316792829D4EE5700843D925D194BE4DF1F3EEB02369`
and all twelve saved files were restored. The focused fix is a tested simulator
candidate, not a newly accepted physical-headset deployment.

## Reports

Initial uncapped comparison used Off A, On A, On B, then Off B, with 120-second
workloads and the first ten seconds of each gameplay generation excluded. The
four completed runs were:

| Run | Measured seconds | Fresh pairs/s | Generated pairs/s | Distinct pairs/s | Cached repeats/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Off A | 110.20 | 81.67 | 0 | 81.67 | 0 |
| On A | 108.07 | 33.85 | 33.84 | 67.69 | 22.25 |
| On B | 110.67 | 33.60 | 33.60 | 67.20 | 22.80 |
| Off B | 109.69 | 83.15 | 0 | 83.15 | 0 |

All four completed cleanly with zero reported pose mismatches and verified
file restoration. The On repeats submitted 4,031 and 3,994 generated frames in
total. These results establish generation, but currently show fewer distinct
submitted frames than either Off control. They do not isolate DLSS GPU cost
from consumer selection and pacing. Native health records and consumer counters
must remain separate; the legacy shared-slot rate is not engine FPS.

Both settings used native hash `D2D84673...0180F`, simulator `FB154E44...02AA6`
and consumer SHA-256
`ABA30C4E091FC2EFC6D14EDABBFFF0C36A1B6FCD44E56D9D05C951FB7C8AA1D1`.
Full hashes are recorded in each local configuration receipt. Selection
diagnostics are the next check before a performance decision.

Run `tools/stereo/analyze-synthetic-framegen.py RUN_DIRECTORY` to write
`summary.json`. It excludes startup and a per-generation warmup, weights rates
by each recorded interval, separates original/generated/cached submissions,
and derives legacy shared-slot publication rate from monotonic ready-counter
differences. That slot can be throttled independently of the original-frame
ring; it must not be reported as engine or source rendering FPS. Native health
records report engine and original-ring rates separately.
Missing interval data stays unknown. Compare only matching configurations.

Diagnostic consumers additionally emit `openxr.generated_selection` once per
report interval. Each frame with a generated ring records either a reserved
original or one generated-candidate outcome: unavailable transport, no new
completed image, invalid/stale metadata, missing matching original, rejected
temporal order, missing endpoint history, or selection. The counters observe
the existing decisions without relaxing them. The analyzer reports these counts
and original/generated ring publication rates separately. Publication rate
includes frames skipped by the consumer and is not a displayed-frame rate.
Logs predating these counters report selection data as unknown.

The 60-second diagnostic run used consumer
`6D96B934CA9C2CCF18161B4E42280BF9ADE4733317E66B3F6509D14B1367691A`.
Its 48.00 measured seconds contained 1,608 selected generated frames and 2,712
frames reserved for their originals, with zero unavailable, missing, stale,
ordering or history rejections. Only 1,608 fresh originals were displayed in
that interval: the other 1,104 reserved frames repeated the cached image while
waiting for the original deadline. Distinct rate was 67.00/s, original-ring
publication 83.88/s and generated-ring publication 73.73/s. Restoration and
clean exit passed, with zero reported pose mismatches.

The selected simulator computes each prediction as actual wake time plus one
period (`xrWaitFrame_runtime`), so successive predictions carry scheduler
jitter. The consumer compares the next prediction to an exact one-period
deadline; a slightly early prediction can defer an original by an entire
additional display frame. This explains the observed reservation losses and
motivates testing a nearest-display-slot boundary. It does not establish that
the physical runtime has the same jitter or performance loss.

The next consumer candidate retains the nominal original deadline but accepts
predictions from the nearest display slot, using the midpoint between that
slot and its predecessor. This permits small prediction jitter without placing
the original in the generated frame's own slot or collapsing a two-slot wait
to one. Source-rate estimation, generated-frame matching and buffer completion
rules are unchanged. Focused tests cover early/late predictions and one/two-slot
spacing, including repeated early/late next-slot predictions.

Its first 120-second run used consumer
`69A584521C102D8EBCEBBABEE777FE90125773DE1C0BB30B6C4EC420B1E74ABA`
with the same native/runtime/settings. Over 109.33 measured seconds it delivered
89.96 distinct pairs/s (44.98 original + 44.98 generated), with 0.037 cached
repeats/s. The measured interval had only four excess original reservations,
versus 1,104 in the 48-second diagnostic control. Original/generated publication
rates were 80.06/79.69 per second. The run submitted 5,391 generated frames in
total, exited cleanly, restored files and reported zero pose mismatches.

The second 120-second run confirmed 90.00 distinct pairs/s (45.00 original +
45.00 generated) over 108.00 measured seconds, with zero cached repeats and
4,860 selections matched by exactly 4,860 original reservations. Original and
generated publication rates were 81.94/81.25 per second. All 5,345 generated
submissions completed with zero reported pose mismatches; clean shutdown and
file restoration passed. Both runs used the same consumer hash above.

This supports retaining frame generation for further development: the initial
67-pair delivery ceiling was largely a deadline issue, not proof of excessive
stereo generation cost. These are simulator delivery results; physical-runtime
benefit, latency, image quality and comparison with SSW remain unmeasured.

Build validation includes the settings-selection test (active fields, preserved
cache, explicit cap control, missing/duplicate rejection), analyzer tests and
native resolver tests. Simulator smoke tests require submitted frames and clean
shutdown. A successful benchmark additionally requires at least 30 fresh pairs;
On requires at least 30 generated submissions, while Off requires none.

Local evidence is under `artifacts/unattended/synthetic-framegen-*`. Raw game
assets, simulator binaries, native logs and settings backups remain outside Git.

## Bounded world submission census

`-RenderWorldCensusSourcePath <focused-main-lua>` together with
`-ExpectedInstalledLuaSha256 <installed-main-hash>` temporarily installs only
the selected main Lua chunk and its adjacent `darktidevr_render_world_census.lua`
module. The source package and installed package pass the pinned LuaJIT gate.
Both files and the enabling flag have byte backups in the normal recovery
manifest and are restored after shutdown. Use a focused candidate based on the
installed Lua revision; this option does not synchronize other modules.

The explicit flag enables an `Application.render_world` hook. After 120 gameplay
world visits it logs at most 64 actual submissions, recording world name,
classification, target viewport name and current render queue size. A direct
prepared right-eye submission is counted too. The frame field advances at the
gameplay `ScriptWorld.render` boundary; worlds rendered before that boundary
retain the previous index. It is not a GPU frame identifier or a timing metric.
Unmapped targets are reported explicitly. Metadata errors end tracing while
the original render call still executes, with arguments and returns preserved.

The isolated contract test covers the disabled flag, warm-up, bounded logging,
render forwarding with nil arguments/returns and a metadata failure. These logs
identify submission owners; they do not prove which shader or clear each world
executes and do not justify suppressing a world by themselves.

The first 30-second Off census used focused Lua `845118a` on installed baseline
`3341afb`, with the accepted native DLL unchanged. All 64 records completed.
Each complete sampled gameplay boundary had five submissions: `level_world`
to `player1` and `darktidevr_right_eye`, followed by `ui_world`,
`HudElementTacticalOverlay_ui_tactical_overlay_world` and
`UIConstantElements_ui_world`. Each queue contained one active viewport.
There was no third gameplay submission in this sample. Cached stock Lua creates
the three UI viewports with the `overlay` template; its decoded layer config
has no explicit clustered-shading stage. This does not assign the earlier third
clear to a UI world, especially because the two traces sampled different runs
and different startup windows.

Fresh synchronized stereo initialization was present; the consumer submitted
2,406 fresh pairs, zero generated pairs and zero reported pose mismatches,
then stopped cleanly. All 13 saved files were restored, including exact Lua
bytes and removal of the temporary module/flag. Evidence is in
`artifacts/unattended/synthetic-world-census-20260910`. The census trace was
extracted from the launcher-selected console after this first run; the wrapper
now performs that extraction and requires the completion marker automatically.
