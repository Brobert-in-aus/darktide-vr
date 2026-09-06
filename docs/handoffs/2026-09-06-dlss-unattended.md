# DLSS unattended continuation, 6 September 2026

Branch: `codex/dlss-live-integration-2026-09-05`.
User authorized unattended headset setup and development while away.
Current result: the one-shot fresh stereo submission and native-target report
pass. Continuous generated output and XR publication remain unfinished.
Proximity override Disable/Status and default Ready preflight passed. VD/VDXR
remained connected. Character selection required an observed desktop Start
click; Psykhanium entry was armed while the game was closed.

## Packed Present copy

Launch: `tools/stereo/start-darktide-vr.ps1 -EnableHudPanel -EnterPsykhanium -StreamlineStereoStageProbe`.
The first attempt exhausted the 16,384-record diagnostic log before gameplay.
The logger now reserves half its bounded capacity for stereo transaction and
input snapshot records. The retry captured a complete transaction:

- Runtime eye/final/HUD-less size 2496x2688; engine depth/motion/input 1664x1792.
- Packed 4992x2688 image matched the actual Present target, format 28.
- Source frame 4167 reached the packed Present copy at outer frame 4174.
- Copy fence 5 completed. No extra Present, new stereo tags, or XR generated
  metadata were submitted. Both input-processing fence references were retained;
  they were pending at observation and describe the game's existing inputs.
- OpenXR continued delivering fresh pairs with zero reported pose mismatches.
  This is unattended transport evidence, not new worn visual acceptance.

Ignored evidence: `artifacts/diagnostics/dlss-live-20260906/stage-copy-probe.tsv`
and `stage-copy-report.txt` (`result=pass`). The exhausted log is preserved too.

## Submission preparation

`StreamlineSubmission::prepare` no longer retains a frame token. `stage` requires
the caller to provide it at the actual submission point and retains it through
cleanup. Tests cover a null token, a different token on a later batch, partial
API failures, cleanup retry and both completion tickets. At this initial
preparation checkpoint native code did not call `stage`; later integration is
recorded below. Preparation alone does not certify Present ownership.

The next live diagnostic records current per-eye constants/token identity and
successful game DLSS-G options at the prepared Present boundary. It makes no
additional Streamline API calls. This is needed before selecting a fresh token
and enabling/configuring paired viewport submission.

The pinned [NVIDIA 2.7.30 guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/docs/ProgrammingGuideDLSS_G.md)
supports multiple viewports writing one backbuffer, independent tags, matching
frame identity and retained inputs. A successful packed copy alone satisfies
none of the remaining temporal-history or generated-output identity requirements.

## Validation

Windows x64 Release native capture, submission tests and official-header ABI
reference builds passed. `ctest --test-dir build/windows-vs2022 -C Release
--output-on-failure -R '^(stereo_color_resample|streamline_(submission|input_lifetime|stereo_inputs|abi_reference))$'`
passed all five tests. Launch retained the LuaJIT gate. No Lua source changed.
`git diff --check` passed.

Next at this initial checkpoint was the current-frame/options diagnostic and
paired submission integration, completed in the continuation below.
Keep accepted HUD, menu, resolution and LOD configuration intact.

## Current-frame submission integration

Four Present-context observations found both game viewports enabled, with the
same token call, frame index and pose, and constants/options recorded in the
immediately preceding Present interval. Added a binding guard rejecting stale
intervals, mismatched identities, disabled options and recycled token pointers.

The first `-StreamlineStereoSubmitProbe` attempt failed with result 27
(`eErrorDuplicatedConstants`): constants for that frame already existed. It
cleared tags without submitting a stereo generation Present; XR kept running.
The revised path refreshes depth/motion/HUD-less copies at both current eye
boundaries, waits on separate copy fences, rebuilds packed colour from those
copies and uses the exact frame's already-supplied constants. It never resets
history or substitutes delayed snapshot constants for a current game frame.

A second attempt proved fresh-pair identity but returned 19
(`eErrorInvalidIntegration`) from frame-based tagging. The observed game uses
`slSetTag`; the frame-based API requires an initialization preference the game
does not use. The pending retry selects only the API mode observed succeeding
in game calls, with no failure-triggered fallback. A mutex holds subsequent game
tag calls outside the one-shot stage/Present/cleanup interval.

The native submitter retains input and command resources on failure. Success
requires tag clearing, cleanup GPU fence completion and both post-Present input
completion tickets before bookkeeping retirement. Generated XR publication
remains disabled. The analyzer now requires those records for a submit probe,
and derives expected packed size from captured dimensions instead of a fixed
4992x2688 check. Original copy-only evidence still passes the revised analyzer.

Failed attempt logs are ignored local evidence: `duplicate-constants-probe.tsv`
and `frame-tag-mode-rejected.tsv` under the session diagnostic directory.
The menu backlog also records the user's roughly one-second click suppression
after character selection loads, with immediate highlighting.

The legacy-mode retry exposed a startup race in the diagnostic trigger: it
captured loading-transition upscaler buffers at 1280x720/1920x1080 while the eye
targets were already 2496x2688. The existing size guard rejected the transaction.
The submit probe now waits for that viewport's active game options and matching
runtime-sized final/HUD-less output before consuming its initial sample. It
retains subsequent mismatch rejection and current-frame refresh requirements.

## Successful one-shot API transaction

The ready-gated legacy run accepted both eyes' tags (result 0), submitted its
normal outer Present at 3381 for input frame 3380, cleared both viewports' tags,
completed cleanup fence 6 and retired both input tickets. Fresh XR pairs
continued. Both state queries returned status 0, one presented frame and fence
value 0; no additional generated frame was demonstrated. Zero-valued valid
input tickets are supported, but are not evidence of generated output.

Evidence: `fresh-legacy-submit-probe.tsv`. The full report initially failed
because normal telemetry had stopped before the native wide Present samples.
Added an eight-outer-frame native target observation window tied to the exact
submission. It uses reserved diagnostic capacity and records actual native
backbuffer extent/identity.

The verification retry passes the full analyzer: input frame 12130 was refreshed
for both eyes and submitted at outer Present 12131. The native call at that
same outer Present observed a 4992x2688 format-28 backbuffer. Later asynchronous
native calls also retained that extent, but their timing classifications remain
candidates, not proof that they contain our generated stereo pair. Cleanup and
input retirement passed; the state reported one frame and zero-valued valid
completion tickets again. XR continued with fresh pairs and no reported pose
mismatches. No worn visual acceptance is claimed for this new probe.

Evidence: `verified-submit-probe.tsv` and `verified-submit-report.txt`, ending
with `input_completion.stereo_retirement_verified=1`,
`generated_stereo.publication_verified=0`, and `result=pass`. Negative copies of
this log with missing retirement, invalid freshness or a mismatched native
extent all fail the analyzer. The original copy-only log still passes.

Next: sustain successive stereo submissions with coherent input history and
GPU-safe resource reuse, then identify and fence the actual generated output
before publishing any generated pair to OpenXR.

## Bounded reuse sequence

`-StreamlineStereoSubmitProbe -StreamlineStereoSubmitFrames 4` now runs four
fresh batches using one texture owner. The default remains one batch, and the
explicit diagnostic accepts 1..8. A batch is rearmed only after both retained
SL input tickets and the cleanup GPU fence complete. Stage/cleanup fence values
advance monotonically (5/6 through 11/12); completed command owners are released
before the next refresh. No CPU fence wait or additional Present was added.

Ready preflight passed (`stereo-sequence-preflight-20260906.json`). Native Release
build, five focused CTest cases and the 27-chunk launcher Lua gate passed. An
added eight-cycle submission test rejects old batch tickets and premature owner
reuse while one eye remains incomplete. Its initial pending-fence assertion was
corrected to match the API's false-until-complete contract, then passed.

Live evidence: `four-batch-probe.tsv` / `four-batch-report.txt`. All four fresh
pairs staged, presented, cleared and retired. Presents were 4181, 4184, 4187,
4190, with two intervening ordinary Presents each. Queries reported 1/1 then
2/2 for each later batch; the pinned header defines this as frames since the
last state query, so it does not identify our generated stereo output. XR
continued with fresh pairs and nonzero shared readiness. Worn acceptance remains
unverified. The analyzer reports four batches, `consecutive=False`, retirement
verified, publication unverified, and pass.

Analyzer regression checks accept both earlier one-shot and copy-only evidence;
mutations removing batch 3 retirement, making batch 2 refresh stale, or reusing
batch 1's cleanup fence for batch 4 are rejected. No generated XR publication
has been enabled. Next remains continuous history and exact output association.

## Publication blocker and next investigation

The user requested a documented commit and a switch to the todo list on a DLSS
blocker. Generated-pair publication is blocked on exact output/source association:
the present hook exposes a swapchain image and timing, not a generation token.
SL 2.7.30's completion fence covers input consumption, not generated-output
identity. Its frame count is an interval counter. Neither authorizes publishing
an image as a particular stereo pose.

The official NGX helper names a distinct interpolated output alongside depth,
motion and HUDless inputs, offering a possible future association point:
[NVIDIA helper](https://github.com/NVIDIA/DLSS/blob/main/include/nvsdk_ngx_helpers_dlssg.h).
However, static inspection of this machine's `nvngx_dlssg.dll` 310.2.1.0 shows
the exported D3D12 evaluation entry at RVA 0x21380 validating its return-address
module before evaluation. Its failure strings include "Not called from NGX
runtime" and "Unable to determine calling module". A normal C++ detour calling
the trampoline changes that caller and is not a compatible observation route.
No hook or binary patch was installed. These RVAs are evidence for this binary,
not portable offsets for a future implementation.

Resume by establishing a compatible, read-only NGX/runtime observation boundary
and validating its parameter ABI against the installed version. Associate both
eyes' exact input resources with output resources and originating command lists;
then establish queue completion and pose/frame ownership before any XR transport.
Separately replace gap-filled single-owner reuse with bounded consecutive-frame
ownership. Do not turn native timing candidates into generated-pair metadata.

DLSS is not complete. The four-batch diagnostic is committed and remains opt-in;
the accepted rendered-eye path continues. Development moves to the all-family
ranged aiming source audit while this output-boundary issue is documented.

After the user's return, an outer NGX runtime observation candidate and pinned
parameter-ABI check were prepared while the user tested in the hub. See the
[follow-up boundary investigation](2026-09-06-dlss-output-boundary.md). The new
candidate is built but not live-validated; output publication remains disabled.
