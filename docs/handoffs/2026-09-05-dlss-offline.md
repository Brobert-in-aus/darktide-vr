# DLSS offline continuation

User explicitly switched interim work from queued menu acceptance to DLSS.
Branch: `codex/dlss-submission-2026-09-05`, based on menu commit `322ac82`.
VD remains closed. No deployment, launch or live test occurred.

Added paired tag/constants preparation and input-retirement bookkeeping.
The pair owns stable descriptors and copied constants, rejects unknown ABI
versions/chains and cross-eye aliases, and preserves jitter/matrices. The
lifetime guard requires per-eye completion tickets plus tag clearing before
retirement after Present. Submission identifiers cannot be reused. The owner
must still retain GPU resources and fence COM references; these helpers do not
call Streamline or represent enabled frame generation.

Validation on Windows x64:

```powershell
cmake --build build/windows-vs2022 --config Release --target darktidevr-streamline-input-lifetime-tests darktidevr-streamline-stereo-inputs-tests darktidevr-streamline-abi-reference
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -R '^streamline_(input_lifetime|stereo_inputs|abi_reference)$'
git diff --check
```

All three Release builds and tests passed, with compiler warnings treated as
errors. The ABI test uses the locally configured official 2.7.30 headers;
they remain outside Git. No Lua changed, so no Lua compilation was needed.

Next offline work: connect preparation and retirement to the native snapshot
owner, implement submission failure cleanup and resource transitions. Obtain
completion state through the existing coordinated Present-thread observation;
do not independently poll and consume presentation counters. Generated-output
identity and actual GPU completion remain necessary before publishing to XR.
Keep the accepted DLSS Quality/jitter configuration. Fresh Ready preflight is
required before the next deployment/live session. Menu acceptance remains
queued separately in MENU-INTERACTION-AUDIT.md.

## Submission integration continuation

The submission adapter now calls constants/tags through supplied Streamline
entry points. It handles both explicitly selected legacy and frame-based tag
APIs, partial tag-call failures, retryable per-eye null-tag cleanup, cancellation,
and completion-gated retirement. It marks inputs potentially consumed before
Present, since a failing Present does not prove no input work was queued.
It does not issue Present or alter feature options. Fault-injection tests cover
each of the four staging calls, cleanup failure/retry, and cancellation.

Native snapshot state owns this adapter and prepares it from the actual three
input resources per eye after packing completes. `STEREO_SUBMISSION_PREPARE`
reports readiness and colour/depth/motion widths. It checks resource shape and
does not submit cropped mismatched input sets. The native DLL compiles with
warnings as errors; all four Streamline CTests pass (including the new
`streamline_submission`). ABI tests also compare constructed viewport metadata
against the official SDK. Build targets are `darktidevr_native_capture`,
`darktidevr-streamline-submission-tests`, and
`darktidevr-streamline-abi-reference`; CTest regex is
`^streamline_(submission|input_lifetime|stereo_inputs|abi_reference)$`.

The existing temporary probe log from 3 September provides concrete evidence:
source frame 3518 has 4992x2688 HUD-less textures and 3328x1792 depth/motion
textures for each eye. The packing probe produces a 4992x2688 stereo backbuffer
with 2496-pixel eye regions by cropping colour only. Resource tags use
`slSetTag`, with empty extents, rather than `slSetTagForFrame`. Treating cropped
colour as a full matching eye without establishing depth/motion regions and
projection correspondence would be incorrect. The new validation rejects it.
This older log does not establish the current runtime layout.

Live dependency: after VD reconnects and Ready preflight passes, capture current
per-eye colour/depth/motion and projection evidence with the existing snapshot/
stereo probes. Determine the correct eye subregions (or change capture to full
matching eyes) before enabling adapter calls in native Present. The source
and target token/history association must also be validated: the current probe
is a one-shot delayed snapshot, not a continuous submission loop. Generated
output identification, actual fence ownership and continuous publication remain
unfinished. Do not label DLSS complete from these isolated tests.

Reference reviewed: NVIDIA Streamline v2.7.30 DLSS-G guide, sections 5 and 7
(independent viewport tags sharing one backbuffer, null-tag cleanup and matching
per-frame constants). No GPU output was generated or accepted during this pass.

## VD reconnected: menu test and fresh input capture

User authorized launch for menu acceptance and DLSS capture. Proximity Disable
then Status applied; Ready preflight passed 600/600 frames, report
`artifacts/unattended/menu-dlss-preflight-20260905.json`. Deployed aa1d10c through
the standard launcher (26-chunk LuaJIT gate passed), using `-EnableHudPanel
-EnterPsykhanium -StreamlineInputSnapshotProbe`. No wide-swapchain, target-token,
Present-stage, synthetic-controller or legacy menu injection switches enabled.
Live runner log: `artifacts/unattended/menu-dlss-live-20260905.log`.

Fresh stereo initialization at 08:38:17 UTC; shared_ready reached 1287 and
approximately 55 fresh pairs/s with zero pair-pose mismatches. Game remains
running for the user's menu acceptance. The harness startup label still says
`semantic-with-cursor-sync`; that string is stale, while actual default
OS-cursor movement was removed in 322ac82. Correct the label in a later build.

Saved capture: `artifacts/diagnostics/dlss-live-20260905/current-probe.tsv` and
`report.txt`; the probe analyzer passes. Pair source frame 3186 uses one token,
two distinct viewports, version-2 constants and identical jitter. All ten
resource samples read back; divergent_mask=31 across the five input roles.
Current colour is 2496x2688 per eye and depth/motion 1664x1792, unlike the old
wide diagnostic capture. Packed output is 4992x2688. Thus the old crop mismatch
does not apply to this normal launch. `STEREO_SUBMISSION_PREPARE ready=0` is
expected here because this run deliberately does not allocate a target token;
it is not evidence of a layout failure. Layout shape and per-eye divergence are
established, not visual correctness of every pixel or temporal history. No
generated-frame submission or publication has occurred.

## After the complete menu registry pass

Menu source fixes are committed at fe98e37: 72 registered views covered, popup
and direct View-service input covered, mode-6 aspect rule unified. All four
targeted menu tests, Lua compilation and harness build pass. User requested
return to DLSS until the next headset-dependent check. Current run is unchanged.

Branch `codex/dlss-live-integration-2026-09-05` adds a bounded two-viewport
completion observation immediately after Present, once snapshot packing is
complete. It uses SDK-checked version-3 DLSSGState and viewport constructors,
serializes feature API calls with the game's calls, and retains returned D3D12
fence COM references. No resource is released based on this observation and no
stereo input is submitted. `STEREO_INPUT_COMPLETION` explicitly logs
`stereo_submission=0`. Fence values from the game's current frame must not be
attributed to our unsubmitted snapshots.

Fresh capture had only one DLSSG_STATE query, at startup/frame zero. That query
cannot validate subsequent input retirement. The new observation consumes
presentation counters only in this explicitly requested, one-shot snapshot
probe; it does not add continuous independent GetState polling. The two
viewport counters must not be interpreted as separate generated-eye counts.

Validation: native Release DLL and ABI-reference target build with warnings as
errors; all four Streamline CTests pass. Next headset check requires a relaunch
to load this DLL and the queued menu changes. Reuse the standard Ready preflight
and `-EnableHudPanel -EnterPsykhanium -StreamlineInputSnapshotProbe` launch.
Check confirmation interaction and store proportions, and inspect both
STEREO_INPUT_COMPLETION results/status/fence-retained/value fields on the
Present thread. A null, poisoned or unsupported fence result needs investigation
before live submission integration. DLSS remains incomplete; continuous frame
submission, generated-output identity and XR publication are still pending.

End-of-turn process check: the run has ended. Log reports
`openxr.capture_window=closed session_exit=clean`, elapsed 788963 ms, then
`XR owner exited; terminated the orphaned flat Darktide process.` No assistant
shutdown command was issued in this pass. Darktide is no longer running.

## Capture scheduling fixed; live completion evidence obtained

User requested continued DLSS work. Found that snapshot scheduling depended on
the short native-Present logging burst, so a slower startup could prevent it
entirely. 6ba4fe6 separates scheduling from log verbosity. Announced restart,
closed Darktide via CloseMainWindow, waited for runner cleanup, ran fresh Ready
preflight and relaunched with the same HUD/Psykhanium/input-snapshot flags.
Current runner session log: `artifacts/unattended/dlss-scheduler-live-20260905.log`.

Capture completed: ten unique snapshot resources, matching source frame 2978,
all five sampled input roles divergent between eyes. At Present 2983 both eye
state queries returned result/status zero, retained fences and value 2982 with
completed value 2980. Thus the inputs were still pending after Present returned.
Saved `artifacts/diagnostics/dlss-live-20260905/completion-probe.tsv` and analyzer
`completion-report.txt`. Analyzer now validates both completion records and
explicitly reports stereo_retirement_verified=0, because our stereo batch is
not submitted. Current game remains open; these are accepted probe results,
not proof of generated stereo output.

Next source build replaces the wide diagnostic path's colour crop with a
full-image compute resample. It emits separate matching HUD-less eye textures
plus packed colour, retains all source/descriptors/PSO resources and publishes
their actual COPY_SOURCE states in prepared tags. Normal-width packing remains
unchanged. Supported source formats are linear RGBA8 and RGBA8 typeless viewed
as UNORM; unsupported resources are rejected. Projection constants and normalized
motion-vector scaling are preserved. Runtime correspondence still needs checking.

Native Release build passed. `stereo_color_resample` executes the actual compute
shader on D3D12 WARP, checks both halves of both eyes survive 4-to-2 downsampling,
checks packed eye order and rejects a second recording into the one-shot owner.
It passes. This is GPU execution evidence, not a headset visual acceptance claim.
The other four Streamline tests also pass. New diagnostic header reports the
bounded independent state-call budget rather than falsely reporting zero.

Next headset gate: launch the wide-swapchain/target-token diagnostic with the new
resampler (without Present-stage copying initially), check full image/projection
correspondence and require STEREO_COLOR_RESAMPLE cropped=0 plus
STEREO_SUBMISSION_PREPARE ready=1. This needs a new launch; current normal game
was left untouched after the scheduler-fix restart. Live tag submission,
continuous batch/fence retirement and generated stereo XR publication remain
unfinished. Do not enable them based only on WARP test success.
