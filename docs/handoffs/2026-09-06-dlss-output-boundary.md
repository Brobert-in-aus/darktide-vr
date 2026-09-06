# DLSS outer-runtime observation candidate

Branch: `codex/dlss-output-boundary-2026-09-06`.

The user requested a hub-capable headset launch and continued DLSS investigation
while testing. Ready preflight passed; Quest proximity override was reapplied.
The old launch was stopped, its Psykhanium flag removed after shutdown, and the
new launch omitted `-EnterPsykhanium`. It uses `-EnableHudPanel
-AutoAdvanceSplash -ManualCharacterSelect -StreamlineStereoSwapchainProbe
-StreamlineTargetTokenProbe`. Startup verified windowed presentation. Gameplay
subsequently reported fresh shared pairs, nonzero `shared_ready` and zero interval
fallback/pose mismatches. Those counters do not establish worn acceptance.

## New candidate boundary

Read-only module inventory found the driver runtime `_nvngx.dll` version
32.0.16.1088. Its exported `NVSDK_NGX_D3D12_EvaluateFeature` is distinct from the
caller-validated `nvngx_dlssg.dll` feature export examined previously. Static
disassembly of this installed runtime shows the outer export forwarding the
original command list, feature, parameters and callback into its internal
feature dispatch and then returning the result.

In this binary the runtime export is at RVA 0x66f90, the internal indirect call
at 0x67044, and its return address at 0x6704a. These are inspection evidence only:
the diagnostic resolves the export by name. A trampoline at the outer entry
resumes the runtime before its internal call, so the feature's return address
should remain within NVIDIA's real runtime. This is a compatibility hypothesis
pending live testing, not proof that the output blocker is resolved.

## Parameter ABI gate

The official [Streamline v2.7.30 NGX parameter interface](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/external/ngx-sdk/include/nvsdk_ngx_params.h)
provides typed resource getters. MSVC x64 reverses each overloaded method group:
the D3D12 resource getter is vtable slot 9 (byte offset 0x48), not declaration
index 14. The unsigned getter is slot 12 (0x60).

`ngx_abi_reference` implements the official interface, dispatches through the
local ABI adapter, and checks overload selection, pointer/value results and
unchanged failure returns. The two reference headers are external, pinned by
SHA-256 during CMake configuration, and are not bundled into the mod. The local
reader is not a generic pointer validator; only a synchronous verified NGX
callback may use it.

NVIDIA's [DLSS-G helper](https://github.com/NVIDIA/DLSS/blob/main/include/nvsdk_ngx_helpers_dlssg.h)
names an interpolated-output resource separately from backbuffer, depth, motion
and HUDless inputs. Newer helper declarations alone do not certify installed
feature support, so missing/failed resource queries remain explicitly recorded.

## Prepared diagnostic (not deployed in the user's test session)

`ngx_output_probe.cpp` is registered only when
`darktidevr_ngx_output_probe.flag` exists in the mod root (one directory above
the native capture DLL). It requires the inspected runtime version and export
prologue, and a readable parameter object whose resource getter belongs to that
runtime. Unsupported versions or signatures reject the requested diagnostic.
Normal launches without the flag do not install this hook.

The observer preserves arguments and the original result. It samples at most
256 evaluations with a nonnull interpolated output within 32,768 runtime calls.
It logs the command list, feature/parameter identity, output and four input
resource addresses, getter statuses, evaluation status, thread and timestamp to
`%TEMP%/darktidevr-ngx-output-<pid>.log`. It neither dereferences the returned COM
resources nor retains them, and adds no GPU commands, waits or XR publication.
Logging `output_complete=0 publication=0` is intentional: successful evaluation
does not mean GPU completion or correct stereo/pose association.

No feature-library patch or return-address spoofing is used. The live game has
not been restarted or hot-patched for this candidate. At the next diagnostic
launch, first verify hook acceptance, successful evaluations and populated
input/output records before trying to match them against stereo submissions.
Do not enable generated XR publication from pointer records alone. Queue/fence
ownership, pose association and continuous stereo history remain outstanding.

## Validation

Windows x64 Release native-capture and NGX-reference targets build successfully.
The focused CTest selection `ngx_abi_reference|streamline_abi_reference|
streamline_submission|streamline_input_lifetime|streamline_stereo_inputs` passes
all five cases. No Lua source changed. The reference headers live under ignored
`artifacts/diagnostics/dlss-output-boundary-20260906`; configure their directory
with `DARKTIDEVR_NGX_REFERENCE_INCLUDE_DIR` to reproduce the ABI test.

Live caller compatibility and resource association are still unverified. This
checkpoint prepares the next experiment without disturbing the user's hub test.

## Observation tooling follow-up

`-NgxOutputProbe` now arms the observer for one launcher session and restores
the previous flag bytes on exit. `tools/stereo/read-ngx-output-probe.ps1 -Path
<log>` reports complete identity observations separately from rejected records.
It rejects malformed/repeated identities, unsupported headers and claims of GPU
completion/publication. Failed evaluations, missing resources, getter failures
and output/input aliases cannot become complete observations. Even complete
records always report stereo association, GPU completion and publication as
unverified. Optional absent HUDless input is incomplete for this stereo-input
association report, not proof that NVIDIA's evaluation itself is invalid.

The parser's positive/negative fixtures, NGX ABI reference, launcher focus and
early-failure checks pass (four CTest cases). A later user report of frozen VR
after manual Psykhanium entry interrupts live NGX testing; this observer remains
disabled in that run. Its logs show fresh pose-matched pairs rejected by an
unchanged gameplay-generation resume gate, which is being handled separately.

## Submission-gated observation window

The initial observer could spend its finite query/sample budget on menu frames
before a useful stereo submission. `-NgxOutputProbeAtStereoSubmit` now enables
the NGX observer and existing bounded stereo-submit diagnostic, opening the
observation window immediately before the first prepared batch's Present.
Startup callbacks still return through the original function and may emit the
first four call summaries, but do not query resources or consume capture budget.

The window permits 32,768 subsequent calls and at most 256 output observations.
Later batches cannot reopen it, replenish the budget or relabel in-flight calls.
Schema 2 adds `window_batch`, `window_present`, and `window_first_call` to each
record. These describe temporal context only, not causal stereo/pose ownership.
The report accepts older schema 1 evidence and rejects out-of-window captures,
missing gated context and any changed/replenished capture window.

`-NgxOutputProbe` alone remains available for initial runtime compatibility
observation without staged stereo submission. Both modes remain opt-in and
restore the flag after launcher exit. For a hub-capable later diagnostic run:

```powershell
tools/stereo/start-darktide-vr.ps1 -EnableHudPanel -AutoAdvanceSplash -ManualCharacterSelect -NgxOutputProbeAtStereoSubmit -StreamlineStereoSubmitFrames 4
```

Do not add automatic Psykhanium entry to the user's current manual-hub workflow.
This command is prepared, not yet executed. The running game was not interrupted
or updated during this work. Release native-capture and capture-window targets
build; seven focused CTest cases pass: NGX capture window, output observation,
parameter ABI, Streamline submission/input lifetime, launcher focus and early
failure. Cases include a million-call startup, exact budget boundaries, failed
and repeated arming, integer wraparound, immutable window context and false
publication claims. Live runtime compatibility remains the next check.

## First live output observation

The user authorized another diagnostic and re-enabled automatic Psykhanium
entry. The in-progress manual launch was stopped and its launcher cleanup
completed before restarting with `-EnableHudPanel -EnterPsykhanium
-NgxOutputProbeAtStereoSubmit -StreamlineStereoSubmitFrames 4`. No synthetic
gameplay attacks were issued. Psykhanium entry and fresh stereo presentation
passed; the full stereo analyzer reports four retired batches, nonconsecutive
submission, and generated publication unverified.

The outer runtime hook receives successful evaluations. Its parameter-owner
check and resource getter work in this installed runtime. Of 256 output-bearing
records, 12 include all four input resources; the other 244 lack HUDless data.
Depth/motion/HUDless tuples in the complete records match the captured per-eye
snapshot addresses. Paired candidate calls share an interpolated-output address,
consistent with packed output, but its dimensions/subrects and GPU completion
have not been established.

Crucially, the parameter object is shared across feature handles. Calls through
the two recurring upscaler handles retain the preceding frame-generation
resource values. A nonnull `DLSSG.OutputInterpolated` parameter therefore does
not identify an evaluation as frame generation. The analyzer intentionally
reports complete *parameter observations*, not verified generated evaluations.
Next add explicit CreateFeature/ReleaseFeature lifetime tracking and classify
evaluation handles using the official feature enum (FrameGeneration=11). Do not
infer feature type from call thread, timing, a changing handle or retained keys.

Local ignored evidence: `first-live-ngx.log`, `first-live-streamline.tsv`, and
their reports under `artifacts/diagnostics/dlss-output-boundary-20260906`.
The guarded outer call path has passed this first live compatibility check;
continuous stereo history, feature-qualified source/output association and
queue completion are still required before any generated XR publication.

## Feature identity refinement

Prepared explicit hooks for the inspected runtime's exported CreateFeature and
ReleaseFeature, preserving the original arguments/results and internal NVIDIA
dispatch. The bounded registry accepts successful observed creations, records
their feature kind and a new lifetime identity, and invalidates at release entry.
Unknown handles, failed creations, ambiguous duplicate creation without release,
and registry saturation never become inferred frame-generation identities.
Resource queries now require a known FrameGeneration (11) handle. The official
header ABI gate also verifies that enum value.

Schema 3 carries feature kind/lifetime. The reader retains schema 1/2 parameter
observations as historical evidence, but only schema 3 can increment
`FeatureQualifiedObservations`. That field still does not certify source-frame
association, GPU completion or generated publication. Native Release and four
focused tests pass (registry, window, reader, official ABI), including handle
reuse across feature kinds and rejection of stale keys on an upscaler handle.
These lifetime hooks have not yet been live-tested at this checkpoint.

The user reports that initial gameplay switched between stereo and two
side-by-side frames several times during the first live run. Record this as a
visual regression, not a pass inferred from counters. Presentation logs show
loading/menu mode changes followed by world mode, but do not identify the exact
image seen at each reported switch. Packed-output fallback leaking into XR is a
hypothesis to investigate. Later intervals are fresh stereo with zero fallback;
that does not close startup visual acceptance.

## Feature-qualified live result and repeated flicker

The second run with the same four-batch flags passed runtime compatibility and
automatic Psykhanium entry. Schema 3 identifies six complete observations as
FrameGeneration (11), with explicit creation lifetimes. Calls 335/336, 347/348
and 359/360 match the left/right depth, motion and HUDless snapshot addresses;
each pair shares an output address. The other 250 captured observations lack
HUDless input. Upscaler calls remain unqueried. Feature lifetimes change between
these pairs (13/14, 17/18, 21/22): this is not persistent temporal history.

The Streamline analyzer passes four retired batches at Presents 3539, 3542,
3545 and 3548, with two intervening Presents each. Generated publication remains
unverified. Saved ignored evidence is `feature-live-ngx.log`,
`feature-live-streamline.tsv` and their reports alongside the first-run evidence.

The user again reports stereo/side-by-side switching, approximately four times.
That count matches the four staged packed-buffer submissions, but there is no
timestamped visual observation proving their exact correspondence. The stage
copy overwrites the ordinary desktop mirror before Present. The XR eye capture
normally occurs earlier and has an isolated-eye extent guard, so the staged
copy alone does not yet explain a headset image change. Existing eye-boundary
logging expires during startup; extend it around the actual submission window
to distinguish source selection/extent, camera projection and presentation-mode
changes before changing rendering behavior. Do not count later fresh counters
as a visual pass. Desktop input is left untouched while examining logs, per the
user's request to release control when idle.

The next native build extends eye execute/capture and isolated-eye validation
logging for 16 Presents from each batch's refresh arming. Capture records now
include source dimensions, vertical FOV, aspect, presentation mode and gameplay
generation. The window includes refresh before the staged Present and expires
after the final batch; normal launches do not arm it. Rendering, publication and
resource lifetimes are unchanged. Validation: Windows x64 Release
`cmake --build build/windows-vs2022 --config Release --target
darktidevr_native_capture` passes.

The image-trace run completed four batches at Presents 2988/2991/2994/2997.
Each four-Present neighborhood has eight successful captures covering both
eyes: 2496x2688, vertical FOV 1.72787595, aspect 0.928571403, world mode 1 and
gameplay generation 112 throughout. No captured resource aliases that batch's
packed destination. This rules out those sampled source-identity, extent and
metadata changes; it does not establish pixel contents, actual shader camera
constants or worn visual acceptance. The reader reports these values per batch
without certifying the image. Historical logs explicitly report no available
image-trace captures. The input readiness, NGX observation and submission CTest
cases pass. Ignored evidence: `image-trace-streamline.tsv` and
`image-trace-report.txt` in the same evidence directory. The game remains open.

## Output-region observation candidate

Schema 4 inspects the live, feature-qualified output resource description and
the four `DLSSG.OutputInterpolatedSubrect*` unsigned parameters. Both getter
vtable entries must belong to the guarded runtime. No resource is retained and
no GPU work is inserted. Missing/unsupported parameters remain unavailable;
zero size or a rectangle outside the observed output extent is not accepted as
a region. The values are read from the runtime, not derived from a fixed headset
size. Even a valid region does not certify queue completion or output ownership.
Release native build and NGX observation/official-header ABI tests pass, covering
a second-eye rectangle, overflow of the texture bounds, zero size and failed
queries. Live output-region compatibility is the next check.

The schema-4 live run completed all four batches and resumed fresh stereo. Six
complete FG observations report output textures 4992x2688, matching twice the
observed eye width and one eye height. All four newer output-subrect queries
return 0xBAD00010, so every region remains unavailable. Do not substitute the
full texture or assume half-width output placement. The official header also
defines deprecated `DLSSG.BackbufferSubrect*` parameters applying jointly to the
input and output backbuffers; checking that older parameter family is the next
compatibility step. Saved ignored evidence: `region-live-ngx.log`,
`region-live-streamline.tsv`, `region-live-report.json` and
`region-live-streamline-report.txt`. No generated XR publication is enabled.

Schema 5 additionally queries the four legacy BackbufferSubrect parameters,
preserving both parameter families and their individual results. The reader
reports legacy availability separately and checks nonzero dimensions and output
bounds. It does not infer a legacy rectangle when a getter fails or certify an
eye association from a valid rectangle. Release build and the observation and
ABI tests pass, including supported legacy data with unsupported newer data,
out-of-bounds/empty legacy rectangles and failed queries. Live check underway.

The legacy live check passes: complete feature-qualified pairs report
`0,0,2496,2688` for left and `2496,0,2496,2688` for right within the observed
4992x2688 output. All legacy getters succeed; newer output-specific getters stay
unavailable. Calls 10248/10249 and 10260/10261 provide paired evidence. This
establishes observed rectangle placement, not GPU completion or pixel validity.
Startup waited at selection while another app was foreground; briefly activating
the game let the existing startup helper advance. The desktop automation kernel
was reset immediately afterward. No manual gameplay input was sent.
Ignored evidence: `legacy-live-ngx.log`, `legacy-live-streamline.tsv` and
`legacy-live-report.json`. Next trace evaluation command-list submission and
recording lifetime before attempting any generated-output copy.

## Queue observation candidate

Successful captured FG calls now register their command-list address and call
identity in a bounded 256-entry observer. The existing ExecuteCommandLists hook
consumes matching records into a separate `darktidevr-ngx-queue-<pid>.log`;
successful Reset consumes unmatched old records as `NGX_RESET`, never submission.
Multiple eyes on one list are preserved. An atomic empty check avoids scanning
or locking once the capture budget drains. No COM objects are retained and no
commands/fences are inserted. Queue-hook entry proves only observed submission,
not GPU execution completion; evaluations internally submitted before returning
may be missed and must not be guessed. Release native build and three tests pass
(command observations, output observations, official ABI), including reset/reuse,
duplicate/unknown identities, paired calls, bounded capacity and no double consume.

Live queue observation passes: all six complete FG evaluations (312/313,
324/325, 336/337) match the same compute queue (D3D12 type 2). Each paired output
has the correct legacy left/right rectangles. Another 250 incomplete-input
evaluations also submit; no captured calls were discarded by Reset. All four
batches retire. The queue reader joins by call and exact command-list identity,
rejects duplicates/mismatches and keeps GPU completion false. Its positive and
mismatched-command fixtures pass. Evidence: `queue-live-ngx.log`,
`queue-live-submit.log`, `queue-live-streamline.tsv`, `queue-live-report.json`.
Next place completion evidence on the observed compute queue, not merely the
game's direct/render queue. This still will not retain output pixels against
future reuse; output copying and ownership remain separate required work.

The next diagnostic allocates one bounded fence group per matched queue
submission, signals after the original ExecuteCommandLists returns on that exact
queue, and polls completion from Present without CPU waits. At most 256 groups
can be created from the observation budget; completed fences are released and
empty polls return without locking. This changes queue synchronization only by
inserting signals, not waits or pixel copies. The reader requires matching
call/ticket/fence/queue identities and successful signal evidence; device removal
never becomes completion. `EvaluationCommandsCompleted` is deliberately separate
from output ownership and generated publication. Native Release and four NGX
tests pass, including missing/mismatched/duplicate/device-removed evidence.

The live compute-completion run passes: all six complete, feature-qualified
evaluations match submissions and successful fence completion on the observed
compute queue. `EvaluationCommandsCompleted=True`; output ownership and generated
publication remain false. Evidence: `completion-live-ngx.log`,
`completion-live-queue.log`, `completion-live-streamline.tsv` and
`completion-live-report.json`. Next establish the output resource state within
the evaluation command recording, then preserve pixels before future reuse.

Schema 6 observes output transitions during the live NGX evaluation through the
existing ResourceBarrier hook, after forwarding the unchanged barrier call.
Evidence is scoped to the evaluation thread/command list/output resource, never
retained as a global resource-state guess. Split/partial transitions and aliasing
make state ambiguous. No observed transition means unknown. Native Release and
four NGX tests pass; this state probe still inserts no pixel copies.

The user adds that the four visible side-by-side images seem to face different
directions, perhaps about 90 degrees apart. Historical completion-run constants
show a repeated large jump from headings -41.95/-27.43 to 83/97 degrees and back,
not a confirmed sequence of quarter turns. Extent/FOV stability did not cover
these actual direction vectors. `apply_head_tracking` returns the untracked
base camera when native pose reading fails; the shared reader rejects data older
than 250 ms. A bounded HEAD_POSE_READ trace around submission refresh is prepared
to correlate read failures with camera direction changes. Do not relax pose
freshness or claim this is the confirmed flicker cause before the correlation.

The first state run reports two output transitions for each complete left-eye
evaluation, ending in UAV state 8; right-eye evaluations have no observed output
transitions. The conservative all-subresources-only rule leaves state unknown.
The refinement accepts subresource zero only when the live description proves a
single-mip, single-array, one-plane RGBA8 2D texture; other partial or split
barriers stay ambiguous. Its whole-resource/single-subresource/alias tests pass.
No cross-evaluation state inheritance is assumed.

This run also exhausted the 8192-line background budget before the batches,
suppressing the newly scoped pose/eye/matrix records. Those records now share
the reserved transaction budget during the 16-Present capture window; the total
16384-line bound remains. `state-first-ngx.log` and
`state-first-streamline.tsv` preserve the incomplete first evidence. Next launch
repeats the pose-read correlation with that logging gap closed.

The reserved pose trace captures seven failed reads around the batches. Frames
2853, 2854, 2857 and 2862 have failed reads and fixed base-eye headings 83/97;
surrounding successful tracking has changing user-facing headings. Other failed
reads share a Present interval with a later tracked frame, so call order matters.
The fixed-direction fallthrough is now corroborated. A cached-camera fallback
was proposed but rejected by the user before implementation: diagnose the
failed reads instead. Native freshness checks and the camera fallback remain
unchanged. The reader now reports pose sample/failure counts and per-eye
headings around each batch. `pose-live-streamline.tsv`, `pose-live-report.txt`,
`pose-live-ngx.log`, `pose-live-queue.log` preserve this evidence. Output state
remains ambiguous after the single-subresource refinement; inspect precise
barrier flags/subresource coverage before copying, rather than assuming UAV.


## Head-pose starvation investigation

The instrumented reproduction identifies all seven failed reads as stale,
not seqlock collisions, invalid tracking, a missing mapping, or a writer restart.
Publication ages are 343, 469, 422, 390, 469, 469 and 421 ms. Matching monotonic
XR timings show the pair-driven wait blocking pose publication for 343–500 ms;
there are no matching long xrWaitFrame, swapchain, or GPU-fence waits.
Evidence: ignored `stall-before-streamline.tsv` and `stall-before-xr.log` in the
same diagnostics archive. The 250 ms reader threshold is unchanged.

This exposes an existing dependency from August 25: the XR loop waits for the
game's next ready image before locating/publishing the next pose, while the game
needs that pose to render. Four bounded DLSS submissions now make that wait long
enough to reject tracking. Feature lifetimes already show recreation between
batches; additional create/evaluate/Present timing separates the source of the
long game frames from the demonstrated transport starvation.

The candidate extracts the existing tracking/recenter/body-follow/pose-history
path and also services it during the pair wait at the runtime's predicted display
period. Each service calls xrLocateViews afresh at the previous predicted time
advanced by elapsed monotonic nanoseconds. It preserves eye-pair submission
cadence, pose-associated history, runtime extents and the 250 ms freshness gate.
No cached pose receives a refreshed timestamp. Synthetic diagnostic paths retain
their frame-count semantics and are excluded from intermediate updates.

Do not change the default to continuous duplicate submissions: that path was
previously rejected because it masks the game's actual frame rate from VDXR
reprojection. OpenXR frame timing and prediction semantics are documented in the
[Khronos xrWaitFrame reference](https://registry.khronos.org/OpenXR/specs/1.1/man/html/xrWaitFrame.html).

Validation so far: native producer and XR harness Release builds pass; five
focused CTests pass (`shared_head_pose`, `ngx_output_observation`,
`ngx_queue_completion`, `ngx_command_observations`, `ngx_abi_reference`). The
transport test checks fresh, missing, and stale diagnostic classification while
retaining rejection of data older than 250 ms. Ready preflight and the launch's
31-chunk Lua gate pass. Live candidate verification is in progress; this does
not establish worn visual acceptance or complete DLSS output ownership.


The tracking-service run passes the specific stale-read regression: all four
batch windows have zero failed head-pose reads, with fresh sequences and stable
per-eye camera headings. Long pair waits remain observable, but their most
recent pose publication stays current. After startup, shared-ready advances
and submission/fresh-pair rates match around 42–51 Hz without fallback, preserving
pair-driven cadence. Five camera-labelled CTests also pass. Worn flicker
acceptance remains open.

Slow-call timing identifies the triggering work precisely: each diagnostic
entry/exit recreates two NGX feature-kind-11 instances, about 140–171 ms each.
The corresponding eight Present calls take 328–391 ms. The frame-generation
creation churn, combined with the pre-existing pose publication dependency,
explains why these diagnostic runs exposed failed reads. Intermediate tracking
fixes that dependency; a continuous, correctly owned stereo submission history
is still required to eliminate the feature churn itself.

Evidence is archived as `stall-service-{streamline.tsv,ngx.log,queue.log,timing.log,xr.log,report.txt}`.
This run does **not** reproduce the earlier six complete output observations:
all captured FG evaluations lack HUDless input, so its output-completion count
is zero. The output association reader correctly refuses success. Do not treat
the pose regression pass as an NGX ownership pass. Next investigate when
stereo tags reach FG relative to the batch cleanup/recreation lifecycle.


## Bounded consecutive submission candidate

`-StreamlineContinuousSubmitProbe -StreamlineStereoSubmitFrames 8` selects a
2–8 frame consecutive experiment. Each frame has separately allocated depth,
motion and HUDless inputs copied at the existing eye boundaries. No allocation
is reused; GPU owners remain alive through process shutdown even on failure.
Successor tags replace both prior eye bindings without nulling the active
viewports, and final/failure cleanup removes tags once. Current Present token,
pose, viewport, options and consecutive-frame identity checks remain mandatory.
The first capture waits for game foreground; focus loss cancels the experiment.
It does not activate windows or publish generated XR images.

Native Release, the Lua gate, submission/lifetime/ABI tests and the new strict
continuous report tests pass. The first live attempt stopped before tag staging:
its copy compatibility check rejected the game's typeless RGBA8 HUDless backing
against typed RGBA8 Present. The corrected guard accepts that known bitwise-copy
family only. Evidence: `continuous-first-streamline.tsv`. A second run is active
but has not yet recorded a continuous transaction; live acceptance is pending.
Use `read-streamline-continuous-probe.ps1` for this path, not the old intermittent
batch report. Generated counters are reported separately from pixel ownership.

User requested working automatic character select for the next launch. Inspection
found old helpers still waiting for a stock `UIProfileSpawner` streaming message
absent in current logs, despite the mod's readiness message reporting Start ready.
Fixing that launch helper is the immediate follow-up before another DLSS run.


The next-launch character-select helper now uses the observed
`DARKTIDEVR_MENU_READINESS ... start_ready=true reason=ready` event instead of
waiting for the missing stock profile-spawner line. It binds to the launch's
PID/start time and one console log, refuses keys after a later game state has
arrived, and its parent retains/cleans up the helper process. Foreground-only
input is preserved. Offline `test-startup-advance.ps1` passes readiness, stale
menu state and process-replacement checks without loading desktop input APIs.
PowerShell parsing passes. The broad Lua invariant script still fails at its
pre-existing controller-fire/muzzle expectation (line 495); no Lua source was
changed by this helper fix. The pinned 31-chunk Lua compiler gate passed for the
DLSS launches. Live automatic entry is the next check.

The next helper retry also exposed an open-log timestamp trap: Windows retained
LastWriteTime from creation while fresh readiness lines were readable. Log
selection now uses the owned process start and log CreationTime, then pins that
path. The offline startup test covers this exact case. The helper reports its
actual Enter attempt count, so manual advancement cannot be mistaken for a pass.

The latest bounded consecutive run passes eight consecutive stereo submissions
at runtime eye extent 2496 x 2688, with 14 generated-eye Presents reported.
All 14 complete feature-qualified NGX evaluations have completed queue fences.
Evidence is archived as continuous-pass-{streamline.tsv,report.json,ngx.log,
queue.log,timing.log}. This establishes consecutive input history and GPU
completion; output ownership and generated XR publication remain unverified.

Automatic Start root cause corrected: the 88580 run emitted eight actual Enter
attempts but the user observed no automatic selection. MenuInput.proxy deliberately
suppresses confirm_* while the tracked pointer owns the menu, so reliable log
readiness was insufficient. Preserve that normal input rule. Explicit AutoEnterHub
launches now arm a one-shot mod request consumed at installation. The first
MainMenuView waits one second of continuous stock readiness, refuses nested menu
or popup activity, consumes its request before calling the stock Start hotspot,
and never replays it on a later view. Manual startup/character-select launches
disable the request. Launcher cleanup deletes the flag. The external helper sends
only title Space and reports whether the callback was observed when loading begins.
Offline menu input/startup tests and the pinned 31-chunk Lua gate pass. Live check
pending. The user observed one side-by-side frame at startup in run 88580;
worn startup-flicker acceptance remains open despite the prior stale-read fix.

Live automatic Start PASS: callback run reports ready at 04:10:37.430, invokes
stock Start at 04:10:38.434, enters StateLoading, and helper exits reporting
startup.character_select.callback_observed=True. No Enter/click was supplied by
the desktop tooling. Desktop control was reset immediately after observation.
Evidence: artifacts/unattended/auto-start-callback-live-20260906.log and the
corresponding character-select/console logs. Generated XR acceptance is separate.
