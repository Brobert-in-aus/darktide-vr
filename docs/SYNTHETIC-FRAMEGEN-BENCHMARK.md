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
first three completed runs were:

| Run | Measured seconds | Fresh pairs/s | Generated pairs/s | Distinct pairs/s | Cached repeats/s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Off A | 110.20 | 81.67 | 0 | 81.67 | 0 |
| On A | 108.07 | 33.85 | 33.84 | 67.69 | 22.25 |
| On B | 110.67 | 33.60 | 33.60 | 67.20 | 22.80 |

All three completed cleanly with zero reported pose mismatches and verified
file restoration. The On repeats submitted 4,031 and 3,994 generated frames in
total. These results establish generation, but currently show fewer distinct
submitted frames than the first Off control. They do not isolate DLSS GPU cost
from consumer selection and pacing. Native health records and consumer counters
must remain separate; the legacy shared-slot rate is not engine FPS.

Both settings used native hash `D2D84673...0180F`, simulator `FB154E44...02AA6`
and consumer SHA-256
`ABA30C4E091FC2EFC6D14EDABBFFF0C36A1B6FCD44E56D9D05C951FB7C8AA1D1`.
Full hashes are recorded in each local configuration receipt. Off B and
selection diagnostics are the next checks before a performance decision.

Run `tools/stereo/analyze-synthetic-framegen.py RUN_DIRECTORY` to write
`summary.json`. It excludes startup and a per-generation warmup, weights rates
by each recorded interval, separates original/generated/cached submissions,
and derives legacy shared-slot publication rate from monotonic ready-counter
differences. That slot can be throttled independently of the original-frame
ring; it must not be reported as engine or source rendering FPS. Native health
records report engine and original-ring rates separately.
Missing interval data stays unknown. Compare only matching configurations.

Build validation includes the settings-selection test (active fields, preserved
cache, explicit cap control, missing/duplicate rejection), analyzer tests and
native resolver tests. Simulator smoke tests require submitted frames and clean
shutdown. A successful benchmark additionally requires at least 30 fresh pairs;
On requires at least 30 generated submissions, while Off requires none.

Local evidence is under `artifacts/unattended/synthetic-framegen-*`. Raw game
assets, simulator binaries, native logs and settings backups remain outside Git.
