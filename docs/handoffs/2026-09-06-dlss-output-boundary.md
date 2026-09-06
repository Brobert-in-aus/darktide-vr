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

Follow-up diagnostic records up to 32 exact output barriers per captured NGX
callback in a separate ngx-state-PID log, including flags, before/after state,
subresource and alias resources. It buffers during the callback and writes after
Evaluate returns. State acceptance and generated publication are unchanged.
Pose failures are now logged outside the DLSS transaction window too (bounded
256 failures), because the user's single startup flash may precede that window.
Native Release and four focused transport/NGX CTests pass. Live trace pending.
The second eight-frame consecutive pass is archived as auto-start-pass-*.

Barrier trace live pass (120848): eight consecutive stereo Presents, 16 reported
generated-eye Presents, 16 complete FG evaluations and 16 completed queue fences.
No failed head-pose reads were recorded, including startup. Trace shows the first
FG call in each pair emits a null/null alias barrier, followed by whole-resource
UAV(8)->COPY_SOURCE(1024)->UAV(8). The second eye has no output transitions.
The observer incorrectly kept alias uncertainty after a new explicit transition;
it now recognizes the final explicit state, while split/partial observations
remain unresolved. It does not infer right-eye state across callbacks or copy
output. See Microsoft's resource-barrier documentation:
https://learn.microsoft.com/en-us/windows/win32/direct3d12/using-resource-barriers-to-synchronize-resource-states-in-direct3d-12

Continuous submission now checks the returned DLSS status and rejects a failed
input-ticket registration. The reader reports StateStatusVerified separately;
old archives remain readable but cannot establish that status. Reader tests
cover failed result/status and old struct versions. The corresponding NVIDIA
2.7.30 header defines status zero as success and completion-fence requirements:
https://raw.githubusercontent.com/NVIDIA-RTX/Streamline/v2.7.30/include/sl_dlss_g.h
Native build and focused state/command tests pass. Evidence: barrier-trace-*.

The next candidate observes an adjacent left/right FG pair as one recording
scope. It carries explicit left-output state only when command list, thread,
output resource, capture window, extents and consecutive NGX call identity all
match, with distinct nonzero feature lifetimes. It observes intervening barriers
and invalidates on Reset/ExecuteCommandLists or any different evaluation. This
is one pending pair, not a long-lived state cache. NGX_PAIR records in the state
trace remain evidence only; no output retention, copies or XR publication.
Release native and focused paired-state/continuous-reader tests pass, including
mismatched identities, unknown initial state, aliasing and reset invalidation.
Live paired-state verification is next.

Paired-state live PASS (19644): seven adjacent generated stereo pairs establish
end state UAV(8) on their exact packed 4992 x 2688 output, with both calls complete
on the same observed queue. Eight consecutive input frames pass and all sixteen
GetState calls report status zero. No failed pose reads recorded. The new
read-ngx-pair-state-probe.ps1 cross-checks state scopes, exact left/right regions,
feature lifetimes, threads, resource identities, complete barrier counts and GPU
fences. It rejects mutated unknown state, wrong output, call gap, truncated scope
and duplicate pair evidence. Evidence: pair-state-* including report.json.
Output pixels are still not retained/copied/published; next is a single bounded
private output copy/readback at the verified right-eye callback boundary.

Private readback candidate: -NgxOutputCopyProbe implies the consecutive stereo
probe and enables exactly one packed-output capture. At a complete successful
right-eye NGX callback with verified adjacent-pair UAV state, it allocates an
independent texture/readback from the actual output descriptor, copies on that
same command list, and restores the source UAV state. All three resource owners
remain alive until process shutdown. Export waits for the existing observed
queue fence covering that right call; a worker writes a BMP and per-eye nonblack
counts/hashes, so file I/O is off Present. Allocation is capped at 512 MiB per
resource as a safety bound, not a resolution target. No generated XR publication.
Release native, launcher parsing and five focused NGX/startup CTests pass.
Live pixel ownership/visual inspection is next.

Private readback live PASS (114936): exact successful FG calls 260/261 copy one
4992 x 2688 packed output into a distinct owned texture and readback buffer.
The covering queue fence completes before export. Each 2496 x 2688 eye contains
6,709,248 nonblack pixels and their RGB hashes differ. Inspection of the lossless
PNG conversion shows two complete scene views without a black half or mis-sized
colour overlay; HUD/reticle are excluded as intended. This is offline pixel
inspection, not worn generated-frame acceptance. Source UAV state is restored.
Evidence: readback-* plus readback.bmp/readback.png, all ignored artifacts.

read-ngx-copy-probe.ps1 verifies the exact known-state, GPU-complete pair, distinct
private resources, row footprint, one staged/exported lifecycle and complete BMP
header/size. Negative checks reject empty eye counts, aliased owner, wrong call
and failed HRESULT. Single-output copy ownership is now demonstrated. Continuous
input/output reuse, source-frame/pose association and OpenXR scheduling/publication
remain unfinished; no generated frames have been submitted to the headset.

## Continuous generated stereo delivery

The -DlssGeneratedStereo opt-in now has an end-to-end path: eight reusable input
owners, three fence-owned generated textures, exact six-input-resource identities
associated with source poses, and three XR-owned original-image slots. The game
mailbox is acknowledged after copying the original into XR ownership, independently
of when it is displayed. Generated images precede their corresponding original
and use midpoint poses. Dimensions come from actual runtime/engine resources.

Pair detection accepts either eye order. Only successive frame-generation calls
on the recording thread advance pairing order; unrelated SR evaluations on other
threads no longer clear a valid pair. Constants/resource observations take the
short boundary lock instead of silently dropping updates when it is busy. Exact
publication pose must match before output inherits an original mailbox ID.

Live evidence in ignored artifacts/diagnostics/dlss-output-boundary-20260906:
- generated-delivery-streamline.tsv: first sustained generated output.
- generated-crop-streamline.tsv: native DXGI source crop avoids the packed desktop
  mirror without GPU writes into NVIDIA-owned buffers. The earlier native buffer
  copy caused DEVICE_REMOVED/ACCESS_DENIED entering Psykhanium and was removed.
  Loading/menu crops restore full extent.
- generated-final-color-streamline.tsv: user confirms HUD flicker fixed. Pack
  completed final eye colour including UI while tagging HUDless scene separately.
  Packing HUDless colour into both removed the HUD from generated images.
- generated-queued-streamline.tsv and the generated-stereo-queued-live-20260906.log
  under artifacts/unattended: over 2,640 generated pairs delivered. Active samples
  have zero recorded pose mismatches, roughly 29-31 originals/s plus generated
  images, despite about 119 compositor submissions/s. User still reports low
  perceived framerate. This is NOT performance acceptance.

The next built candidate schedules the original half a measured source interval
later than its generated image, rounded to the nearest runtime display slot. It
caches the generated image and midpoint poses through intervening refreshes rather
than reverting to the older original. Telemetry separates original, generated,
distinct and cached rates and reports source period. Loading gaps reset cadence.
This change has NOT received live or worn acceptance: the Ready preflight returned
no usable HMD on 6 September, so no launch followed that failure.

Validation: Windows x64 Release native and XR builds pass. Five focused CTests
pass: generated_frame_state, streamline_input_lifetime, streamline_submission,
ngx_command_observations, startup_advance. Cadence checks cover 30/60-ish source
rates on a 120-ish display and a runtime-period change after a loading gap. Pair
checks cover reversed eye order and SR interleaving. The last live launch passed
all 31 Lua chunks; no Lua source changed here.

Next: repeat Ready preflight when streaming resumes, then launch with
-AutoEnterHub -EnableHudPanel -EnterPsykhanium -DlssGeneratedStereo. Compare actual
distinct-image cadence and worn smoothness. Still required before promotion:
performance/pacing, repeated menu/loading recovery, resolution/quality changes,
source-generation resets and resource lifecycle review. Default launch remains
unchanged; DLSS frame generation is not complete.

Follow-up: spacing alone did not satisfy worn smoothness. User reports about
70 FPS before the FG work. New once-per-second native health telemetry separated
engine Presents from legacy mailbox delivery: engine about 48/s, original mailbox
only 28-35/s. Generated partners were also rejected whenever their original had
been dropped by that mailbox. The new original ring captures the exact final
packed input before Present, in three separately fence-owned textures with its
own metadata channel. XR ingests these independently and associates generation
with that ring ID. Original delivery can start and continue without generation;
the old mailbox is still consumed for baseline/transition metadata.

The original-ring run delivered about 48 originals plus 48 generated pairs/s,
versus about 60 total distinct pairs/s before the transport correction. Over
6,000 generated pairs completed. When foreground was lost, NVIDIA evaluations
stopped while input submission continued; originals then reached XR at about
65/s. The application must not steal focus to hide this behavior. Actual GPU
utilization with generation was sampled at 94 percent; the remaining 70-to-48
render-rate loss still requires investigation, not a claim of success.

Native/XR Release builds and the five focused tests pass. A new isolated WARP
original_stereo_ring test additionally checks full-ring backpressure, acknowledged
slot reuse, independent original metadata and retained pixels in an unconsumed
slot. It passes after isolating every explicit GPU object name as well as the
metadata mappings. No live output objects are used by that test.

The user also flagged compositor reporting 120 while distinct delivery is about
96. The generated path had bypassed the baseline pair-driven wait, deliberately
submitting cached copies on intervening refreshes. The next candidate restores
new-image readiness waiting for both image classes, retaining tracking updates
while waiting, and leaves intervening reprojection to the runtime. It preserves
the xrWaitFrame/xrBeginFrame/xrEndFrame sequence and runtime display predictions:
https://registry.khronos.org/OpenXR/specs/1.1/man/html/xrWaitFrame.html
This frame-loop follow-up has not yet received live acceptance.

Distinct-image wait live result: generated-stereo-distinct-live-20260906.log
records 99.5-102.4 application submissions/s and exactly the same distinct-image
rate in the latest intervals, zero cached submissions. About 50-51 originals/s
reach XR, matching native engine and original-ring rates. This resolves the
measured 120-versus-96 reporting mismatch; user confirmation of the compositor
overlay and worn smoothness is still pending. One cumulative legacy-mailbox pose
mismatch was recorded; generated/original association uses its own exact poses.
The native health stream confirms steady evaluations and input association.
Six focused CTests including original_stereo_ring pass. Native/XR Release builds
pass; all 31 Lua chunks passed at launch. Remaining original render throughput
regression is not resolved and DLSS is not marked complete.

## F3 editor recovery

Branch codex/dlss-hud-editor-recovery-2026-09-06 follows 9727970.
The first mode-5-only attempt resumed stereo across F3/ESC but the user correctly
reported a stale loading/menu image. The gameplay HUD GUI does not own final
desktop output under DLSS. Added a separate layer-200 overlay UI world, disabled
on editor close and recreated when canvas dimensions change; no dependency source
or saved layout was changed. The next live run visibly shows the full editor and
returns to ~51 original + ~51 generated distinct submissions/s after F3 close.
Desktop control was reset/released after each short inspection/action.

Continuous submission now pauses on non-world modes and binding gaps, clears only
its active tags, retains all NVIDIA input-ticket ownership, and waits for exact
capture/cleanup fences before discard/reuse. Original ring expiry allows baseline
stereo consumption instead of a stuck 500-ms ring wait. Original and legacy ready
sequence namespaces remain separate; legacy fallback acknowledges after GPU copy.
Native pause/resume diagnostics survive the finite diagnostic record budget.

Validation: native/XR Release builds; pinned LuaJIT 31 chunks; generated_frame_state,
original_stereo_ring, streamline_input_lifetime, streamline_submission,
ngx_command_observations, startup_advance, continuous_recovery, hud_panel,
hud_options and lua_source_compile pass. New WARP recovery test repeatedly rejects
partial/full captures then resumes; Lua fixture verifies final overlay lifecycle.
Latest run artifacts/unattended/dlss-editor-overlay-live-20260906.log (session68180).
The logging-only addition after launch is built for the next run. No claim of
saved layout dragging/persistence or worn readability acceptance. Return to the
remaining original-render performance regression after committing this fix.

### 2026-09-06: preserve desktop input alongside VR

User requirement: keyboard and mouse must remain available alongside VR controls.
The DLSS editor's mode-5 output had unintentionally enabled the menu pointer
proxy, suppressing right/middle/confirm actions and replacing mouse wheel input.
The adapter now retains stock mouse buttons and confirmation actions, combines
wheel input with XR scrolling, and preserves stock mouse movement. Desktop-only
Custom HUD editing bypasses that proxy; actual views and modal dialogs still
receive the combined menu route. Right/middle mouse holds also select the desktop
pointer position in the harness, as left mouse already did.

Validation: Release harness and menu-input tests built; ctest menu_input,
menu_input_injector, hud_panel, hud_options and lua_source_compile all passed.
The Lua gate compiled 31 chunks. Live editor right-click/wheel acceptance remains
pending. Two Ready preflights created a VDXR session but submitted zero of 600
frames. Game was closed for the planned update; no deployment/relaunch followed
the failed readiness checks. Do not mark the editor regression visually accepted.

### 2026-09-06: base-framerate cost investigation, first measurement

Custom HUD right-click/scroll repair has user acceptance. Keyboard/mouse are
supplemented by VR input, not intentionally suppressed by the menu adapter.

New opt-in continuous-submission GPU timestamps use the existing performance
profile switch. Each input owner owns six queries and a 48-byte readback buffer.
The two eye captures and stereo packing/original publication are measured
separately. Results are read only when normal owner completion has already
retired; profiling introduces no fence waits. Default launches allocate none of
these resources. Timings survive the finite verbose-log budget, one aggregate
per 120 recycled owners. Missing profiling resources do not disable rendering.

Live run: artifacts/unattended/dlss-base-profile-20260906.log, PID 131700.
Archived evidence: artifacts/diagnostics/dlss-base-framerate-20260906/.
52 timing windows: median sum of capture-left, capture-right and pack/publication
GPU spans = 0.488 ms. Component medians 0.1384, 0.1407, 0.22325 ms (medians do not
add to the median of sums). These are GPU execution spans, not CPU submission
times, and do not include NVIDIA async generation or generated-output transport.
69 steady foreground/generation-active health windows: median engine 50 fps.
35 steady background/generation-inactive windows with original ring still live:
median engine 72 fps. Existing coarse Present CPU median was 0.0 vs 0.44 ms;
its timer granularity prevents interpreting 0.0 as zero cost. FG evaluates two
eye regions per original pair, 2496x2688 each, in a 4992x2688 packed target;
no extra evaluations or incorrectly doubled eye extent found in captured data.

This is NOT a controlled foreground FG-on/off A/B: user motion/scene/focus and
GPU scheduling can change. It narrows the cause: measured integration copies
are much smaller than the approximately 6 ms source-frame delta. NVIDIA's
Streamline 2.7.30 guide lists 2.77 ms at 4K on RTX 4090 for one 2x evaluation;
two large eye evaluations plausibly account for much of the delta, but that is
context, not measured attribution or proof that all overhead is unavoidable.
Source: https://raw.githubusercontent.com/NVIDIA-RTX/Streamline/v2.7.30/docs/ProgrammingGuideDLSS_G.md
Remain open: matched foreground A/B and precise GPU timeline of NVIDIA async
work, generated-output copying and rendering contention. Do not optimize away
ownership fences, alter required extents, or disable quality without evidence.

Validation: Release native and continuous-recovery targets built; ctest
continuous_recovery (profiling enabled across partial/complete captures and
pause/resume), original_stereo_ring, streamline_submission and
streamline_input_lifetime all passed. Live timing readback also verified.

HUD blur follow-up from user research: check motion vectors and depth beneath
HUD boundaries, not only HUDless color. Captured HUDless/final per-eye extents
match; no UI color/alpha is currently provided. Do not zero the world's velocity
under UI rectangles: that destroys background motion and our stabilized HUD and
world markers are not static screen-space overlays. Capture the actual separate
UI alpha/color or compose after generation. Unreal plugin composition settings
are not directly applicable to Darktide's engine. No blur fix claimed yet.

### 2026-09-06: foreground comparison and NGX GPU timings

The user disabled frame generation in the stock graphics menu. Same live process,
resolution and Quality SR setting, foreground gameplay: 75 steady off windows
median 70 fps versus 134 generation-active windows median 50 original fps.
This removes focus as the off switch; scene/head motion were not frozen, so it
remains an observational same-session comparison rather than a deterministic
benchmark. Both original-frame output paths continued rendering normally.

New opt-in NGX GPU profiler: 32 query/readback/fence owners, no waits, safe reset
of unsubmitted samples, exact post-submit fence retirement before reuse. Handles
both direct and compute lists; NVIDIA uses the compute queue here. Samples bracket
Evaluate and the following output work on that command list. They do not claim
independent-engine timelines outside that list. Default profiling remains off.

Live PID 140744, artifacts/unattended/dlss-ngx-compute-profile-20260906.log.
56 windows per eye: median GPU Evaluate 2.06335 ms left, 2.06055 ms right.
Post-evaluate work 0.0740 ms left and 0.0001 ms right; this run evaluated right
before left, and the stereo copy occurs after the second eye. Combined measured
NGX spans plus prior input/copy publication approximately 4.7 ms versus the
50-to-70-fps source-frame difference of 5.7 ms. No duplicate FG evaluations or
oversized eye subrect found. The former 30-original-fps issue is absent. Most of
the current base-rate reduction is explained by real two-eye generation work;
remaining queue/contention/scene variability is post-release profiling work,
not evidence of a particular fix to make now. No claim that every millisecond
is unavoidable, and no image quality or ownership safety was reduced.

Validation: Release native and GPU timing tests built; ngx_gpu_timing and
ngx_gpu_timing_compute both pass capacity/reset/completion/readback and both-eye
aggregation checks. original_stereo_ring, continuous_recovery and
ngx_command_observations also passed before compute-specific extension.
Evidence archived under artifacts/diagnostics/dlss-base-framerate-20260906/.
Frame generation remains OFF in the user's live graphics setting after this test.
Re-enable for the next deliberate generated-HUD validation, not as a silent
background setting change.

Next: user rapid-headshake evidence identifies an entire world-space HUD element
shifted/duplicated beside its correct position in generated frames. Acceptance
must include fast real head movement, not just stationary clarity. Prioritize a
separate UI color/alpha or post-generation composition path while preserving
background velocity; do not zero world motion under the HUD.
