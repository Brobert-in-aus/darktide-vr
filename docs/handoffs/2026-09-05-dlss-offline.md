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
