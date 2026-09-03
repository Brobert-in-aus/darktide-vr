# Development-session handoff — 2026-09-03

This session continued from
[`2026-09-02-development-session.md`](2026-09-02-development-session.md).
Read `AGENTS.md`, both handoffs and
[`../phase1/todo-2026-09-03.md`](../phase1/todo-2026-09-03.md) before the next
edit, build, synchronization or launch.

## Session state

- Branch remains `phase0/feasibility-bootstrap`.
- The unrelated user-owned `Codex Image 25 Aug 2026, 08_53_34.jpg` remains
  untracked and untouched.
- The 20-minute development heartbeat is active.
- Worn acceptance of the clustered-light correction and visible fleshy hands
  remains pending. Unattended counters and captures are not substitutes for
  those checks.

## Unattended title transition

The first authenticated run stopped at the title screen because its one-shot
Space arrived before the title view accepted input. The hub helper now retries
Space every two seconds only until the console log proves `StateMainMenu`.
That log-owned boundary prevents retries leaking into character select or the
hub. The source gate now requires the title retry as well as the existing
character-select retry.

The follow-up launch reached `StateGameplay` without manual title input.

## Settings retained-surface format fix

New presentation telemetry recorded all three extents involved in the report:

- the physical captured Windows client is `1920x1080` (`1536x864` through the
  launching process's 125% DPI view);
- SystemView mode 5 was published as `2496x1404` after
  `RESOLUTION_LOOKUP=2496x2688`, scale `1.3`;
- OptionsView mode 4 used a `2496x2688` source with centered
  `2496x1404` crop.

A deterministic desktop activation opened the real Options row. The native
menu-resource trace then exposed the actual failure: OptionsView's completed
retained layer is `R8G8B8A8_TYPELESS` with an `R8G8B8A8_UNORM` RTV. The direct
menu surface already had the correct typed UNORM mailbox identity, but the
copy path discarded the RTV type and requested a typeless replacement. Every
capture returned code 89 because recorded direct-menu command lists correctly
prevented replacing their live shared resource. This was the repeated failure
behind the stale/partial settings surface, not a pointer-scale guess.

The copy policy now canonicalizes this exact typeless backing resource to its
typed UNORM shared surface. Unit coverage checks both the typeless conversion
and a non-typeless pass-through. In the clean deployed follow-up, the first 173
observed Options retained-layer copies all returned `result=0`, with zero
description-mismatch recreations and no code-89 failures. The complete
600-second run then passed with 28,125 of 28,125 submitted frames, 14,907 fresh
shared pairs, and zero reused pairs, pose mismatches, capture failures, stale
frames or pair-driven timeouts. Visual extent and laser alignment still
require a worn check.

## Tracked-hand surface visibility

The hands-only profile proxy reports four enabled body-skin meshes and four
enabled glove meshes, but those counters did not identify which resource
actually reached the render graph. A candidate `lua_visible` flow event was
tested on the body-skin slot because unit and mesh visibility can coexist with
a retained hidden equipment-flow state.

A fresh authenticated five-minute hub run initialized the module cleanly,
reached nonzero `shared_ready`, and passed with 18,002 of 18,002 submitted
frames, 11,080 fresh pairs, and zero reused pairs, pose mismatches, capture
failures, stale frames or pair-driven timeouts. Direct readback under inactive
controller tracking contained a rendered right-hand/glove surface, proving
that at least one proxy surface reaches the render graph. This did not isolate
the body-skin contribution or establish independent two-hand behavior.

The follow-up 150-second offline Psykhanium matrix exercised both tracked
hands plus repeated one-second tracking-loss/reacquisition windows. Both proxy
chains became active, equipment-hand ownership stayed on the tracked proxy for
7,200 sampled syncs, maximum positional error remained `0.000001 m`, and
maximum angular error remained `0.002058 rad`; no presentation-disable or Lua
error was logged. A concurrent direct-eye capture could not advance because
the offline producer retained readiness generation 1, so this is pose/hold
telemetry rather than new visual evidence.

A production OpenXR synthetic follow-up supplied the missing direct-eye
evidence. It made the remaining defect unambiguous: `astra_gloves_b` includes a forearm cuff
skinned across the stock elbow-to-wrist chain, and that cuff balloons into a
large detached sleeve around extended tracked poses. The hands-only proxy now
briefly retained `slot_body_arms` plus the required unarmed record only and
recursively hid all attachment units. A second production matrix proved that
the body-skin slot contributes no visible hand surface in this presentation;
all sampled phases lost the hands while the gameplay-owned weapon remained.
That failed skin-only experiment was rejected and the prior glove selection
restored, along with removal of the unproven body-slot flow change. The next implementation must use a genuinely hand-local visual
resource or controlled mesh duplicate rather than hiding the only rendering
attachment.

### Hand-local resource survey

A one-shot live inventory scan established that the equipped human
`slot_body_arms` item uses the same
`content/characters/player/human/attachments_base/female/base_body/female_arms_01`
resource for both `base_unit_1p` and `base_unit_3p`; there is no separate
first-person body-arm resource to substitute. It also enumerated the cached
`gear_hands` items. The only explicitly one-sided human glove resources found
were `hmn_gloves_b_left_only` and `hmn_gloves_b_right_only`; the other glove
items are combined profile attachments rooted at `j_spine2`.

Three isolated-surface production experiments then removed the body-arm skin
and retained only glove geometry:

- `hmn_gloves_b` tracked both controller-authored wrists and eliminated the
  long triangular arm stretch, but rendered as oversized cloth mitts;
- the equipped `astra_gloves_b` profile attachment had correct production
  materials and articulated detail, but exposed large cylindrical cuffs;
- representative NPC, Imperial Guard, Frateris Militia and Missionary glove
  items either omitted the skin/fingers or ended in a visible open cuff.

Dense direct-eye evidence is under
`artifacts/unattended/hand-compact-only-dense-cycle-20260903`,
`artifacts/unattended/hand-profile-glove-only-dense-20260903`,
`artifacts/unattended/hand-imperial-guard-b-dense-20260903` and the
`hand-carousel-*` directories. These captures prove the stretch belongs to
the shoulder-connected body skin, while standalone cosmetic glove shells are
not complete hand replacements. The temporary item scan, compact-glove swap
and candidate carousel were removed after the survey; tracked-hand source and
the source gate were restored to commit `b0abd0a` behavior.

### Independent rigid-hand roots

The hand-local architecture is now implemented and runtime-proven. Tracked
hands mode creates two independent `UIProfileSpawner` roots, equips
`hmn_gloves_b_left_only` on the left root and `hmn_gloves_b_right_only` on the
right root, suppresses the private animation state machine, and hides every
surface except the selected hand item. Each frame solves the root transform
that maps the profile's authored `j_lefthand` or `j_righthand` joint exactly
onto its corresponding controller target. The gameplay avatar remains the
equipment owner; its left and right equipment hand joints are synchronized to
the matching rigid root after placement.

The first 180-second production run reached
`DARKTIDEVR_IK rigid_hands=ready`, reported four visible meshes for each
one-sided item, and completed with 14,358/14,358 submitted OpenXR frames,
7,129 fresh shared pairs, zero reuse/timeouts/capture failures and one startup
pair-pose mismatch. A 60-pair direct-eye capture is under
`artifacts/unattended/hand-rigid-one-sided-dense-20260903`. It confirms two
stable, independently positioned gloves and eliminates the shared-chain skin
stretch. The stock one-sided meshes still expose open cloth cuffs when their
wrist ends face the camera; that remaining asset-quality limitation needs a
purpose-built closed hand/cuff mesh or a compatible one-sided bracer.

A follow-up control used `astra_gloves_b` on both rigid roots and logged the
mesh bounds. All four meshes share the same approximately 1.09-metre-wide
combined-pair bounds, so there is no left/right mesh subset to suppress. Its
30-pair capture under
`artifacts/unattended/hand-rigid-astra-dense-20260903` shows the unwanted
partner geometry displaced across or outside the view. The production glove
control was rejected and the one-sided resources restored. The source gate now
asserts the two spawners, both one-sided resources, rigid joint-to-controller
alignment and per-side equipment synchronization.

The cached catalog also exposes side-specific material masks named
`mask_arms_keep_wrist_and_hands_left` and
`mask_arms_keep_wrist_and_hands_right`. Runtime inspection found that they set
`assymetry_right_left_body_mask` per side and use `mask_top_bottom = (0, 0.65)`.
Darktide's `VisualLoadoutCustomization.apply_material_override_item` applied
both masks successfully to separate rigid-root `slot_body_arms` units, but the
60-pair direct-eye capture under
`artifacts/unattended/hand-rigid-masked-wrists-dense-20260903` rejected the
result: large shoulder-connected skin sections still deform into the view in
several controller phases. The 150-second run itself passed with 12,586/12,586
submitted frames, 5,318 fresh shared pairs, zero reuse/timeouts/capture
failures and one startup pair-pose mismatch. The masked-body experiment was
removed and the installed game restored to the independent one-sided-glove
baseline. A fresh 150-second production confirmation of that restored baseline
passed with 12,645/12,645 submitted frames, 5,282 fresh shared
pairs, zero reuse/timeouts/capture failures and zero pair-pose mismatches.
The 30-pair capture under
`artifacts/unattended/hand-rigid-baseline-restored-20260903` again shows two
stable gloves without the rejected skin geometry.

A recursive scan of every cached master-item value then broadened the resource
survey beyond item names. It found 129 human `gear_arms` items, all normally
spine-rooted arm attachments, and only three singular hand-named resources:
Hadron's left hand plus `servitor_arms_02_hand_01` and
`servitor_arms_02_hand_02`. The two servitor hands spawned successfully as
separate rigid roots with four meshes per side and no stretching. Direct-eye
evidence under `artifacts/unattended/hand-rigid-servitor-singular-20260903`
shows complete mechanical hands, however, so they are not acceptable player
surfaces. A second experiment layered each servitor hand beneath the matching
one-sided cloth glove. Both roots reached eight visible meshes and the run
passed, but the 40-pair capture under
`artifacts/unattended/hand-rigid-glove-servitor-underlay-20260903` shows the
mechanical fingers and palm protruding beyond the glove in multiple phases.
That underlay was rejected. The catalog probe and both servitor experiments
were removed; shipped human resources are now exhausted as a compatible cuff
solution.

A final semantic sweep recursively searched the live master-item catalog for
`bracelet`, `bangle`, `vambrace`, `gauntlet`, `armguard`, `wristband`,
`armband`, `bracer`, `cuff` and `wrist`. It completed with 419 matching values.
Nearly all human results were the already-rejected wrist-preserving body masks.
The only independent geometry family was the Ogryn grenadier-gauntlet weapon:
its receiver, barrel and magazine parts belong to a chained weapon rig, not a
small human wrist-rooted cosmetic. Two Ogryn upper-body descriptions mention
wrist chains or a wrist plate but expose no separable wrist item. No standalone
human cuff, bracer, bracelet, vambrace or armguard exists in the cached item
catalog. The successful 95-second production run submitted 9,252/9,252 frames,
advanced 2,099 fresh shared pairs and reported zero reuse, pair-pose mismatch,
capture failure, stale frame or pair-driven timeout. The temporary semantic
logger was removed and the installed mod was synchronized back to the clean
one-sided-glove baseline.

## Opt-in compositor cuff prototype

The first engine-independent cuff prototype is now implemented in the OpenXR
consumer. `tracked_cuff_mesh` generates a sealed, tapered 24-segment elliptical
cuff aligned to each Touch grip pose. Its test verifies finite vertices, the
intended bounds, outward winding and exactly two uses of every triangle edge.
The harness builds a small D3D12 pipeline at runtime and draws the cuff for both
hands into both eye swapchains after copying a valid live or cached game pair.
It uses the pair-associated eye poses and explicit
`COPY_DEST -> RENDER_TARGET -> COMMON` transitions.
An offscreen GPU integration test renders a known tracked pose into a 256x256
texture and verifies 494 bounded non-background pixels, covering the matrix,
winding, culling, shader and readback conventions without a headset wearer.

The feature is deliberately disabled by default. Pass `-TrackedCuffOverlay` to
`start-darktide-vr.ps1` or `run-darktide-shared-eyes.ps1`; this becomes the
harness option `--tracked-cuff-overlay`, which fails closed without
`--shared-eyes`. The compositor does not have the game's depth buffer, so this
opaque geometry always wins foreground occlusion. It must remain diagnostic
until worn inspection confirms alignment and determines whether that depth
policy is acceptable.

A 120-second private-range exercise initialized the runtime shaders and PSO,
attached the real game eye producer and completed 2,084 cuff-rendered stereo
frames with 8,336 draws: exactly two hands times two eyes per rendered frame.
The run submitted 11,805/11,805 OpenXR frames, advanced 2,484 fresh shared
pairs, and recorded zero reuse, pair-driven timeout, capture failure or stale
frame. The single pair-pose mismatch occurred at initial producer attachment;
subsequent live reporting remained at one while the range ran. This proves the
renderer and resource-state path, but it is not a substitute for worn visual
acceptance.

The harness now supports an on-demand post-compositor eye readback for this
prototype. Creating `%TEMP%\darktidevr-projected-eye-readback.request` while a
tracked-cuff run is active writes `darktidevr-projected-eye-left.ppm` and
`darktidevr-projected-eye-right.ppm` after the cuff draw and before swapchain
release. A simultaneous existing shared-eye readback therefore gives a direct
before/after pair from one command list. The request also logs each cuff
centre's normalized device coordinates, which distinguishes a successful but
off-frustum draw from missing raster output.

This diagnostic exposed and fixed an inconsistency in `SyntheticBodyPath`:
after replacing the Darktide body-local poses, the sample retained unrelated
absolute OpenXR poses from the generic panel-ray path. The harness now
reconstructs absolute aim/grip poses from the recenter anchor after all
synthetic transforms. The inverse conversion is shared and round-trip tested
in core math.

Two synchronized live captures then established both negative and positive
controls. With `SyntheticBodyInspection`, the deliberately pitched-down camera
placed the cuff centres at NDC y=2.27, and raw/projected eyes were byte-identical
as expected for fully clipped geometry. Without the inspection override, both
eyes differed. The left-eye delta contained 13,933 pixels in bounds
1861,1685-1996,1801; its amplified difference image cleanly isolates the
procedural cuff. Evidence is under ignored
`artifacts/unattended/tracked-cuff-visible-paired-20260903`. This is GPU
readback proof of visible compositor pixels, not worn alignment acceptance.

## Launcher Play retry

The first Play press in that run moved WPF's `Process.MainWindowHandle` to a
tiny auxiliary window but did not start Darktide. The original authenticated,
titled launcher window remained alive and accepted a second press. The launcher
helper now retains that exact window handle and retries its already-validated
Play region every three seconds while rechecking process ownership, title and
client geometry. It still succeeds only after the configured Darktide
executable appears and otherwise fails at the existing deadline.

## Runtime frame-synthesis capability gate

The OpenXR harness now reports extension availability and advertised spec
versions for `XR_EXT_frame_synthesis` and `XR_FB_space_warp` alongside the
existing D3D12 capability. This is telemetry only; neither extension is enabled
and presentation is unchanged. Mandatory XR preflight reports retain both
capability lines so a runtime update cannot silently change this gate.

The active VirtualDesktopXR 1.0.10 runtime reported both synthesis extensions
`unavailable spec_version=0`. A 120-frame rendering-required smoke test still
submitted 120/120 frames at 108.93 Hz with `result=pass`. Runtime-owned frame
synthesis is therefore unavailable on this installed VDXR path. Do not build
depth or motion-vector swapchains for either extension unless a future runtime
probe reports support; continue with the separate Streamline-generated-output
feasibility gate.

## Observe-only Streamline Present probe

The first Streamline feasibility layer is now launch-scoped behind
`start-darktide-vr.ps1 -StreamlineProbe`. It opens
`%TEMP%\darktidevr-streamline-probe.tsv` only when requested and records the
unhooked Present target before MinHook builds its trampoline, loaded module
paths and file versions, exported resolver availability, COM swapchain
identity, Present thread/frame/QPC, result, and the DarktideVR ready fence
before and after Present. Sampling is bounded to the first five frames and one
frame in 120. `read-streamline-probe.ps1` validates and summarizes the trace.

The 90-second authenticated hub run proved that the real target of the native
Present hook is Darktide's loaded `sl.interposer.dll` 2.7.30.0. The process also
loaded `sl.common.dll` and `sl.dlss_g.dll` 2.7.30.0 and
`nvngx_dlssg.dll` 310.2.1.0. All 56 sampled calls used one thread, one
swapchain pointer and the same COM identity. Once stereo attached, sampled
ready values advanced from 20 through 1,280 and were complete or one fence
value behind at Present entry. The OpenXR run submitted 8,700/8,700 frames,
advanced 1,313 fresh shared pairs, and reported zero reuse, capture failures,
stale frames, pair-driven timeouts or pair-pose mismatches. This establishes
that the game calls the Streamline proxy Present path and correlates that path
with the stereo producer; it does not yet prove whether generated asynchronous
presents re-enter that same proxy method.

The probe now wraps Darktide's existing `slDLSSGGetState` and
`slDLSSGSetOptions` resolutions, forwards every intercepted invocation exactly
once, and records bounded post-call results. It adds no Streamline API calls.
That constraint matters because NVIDIA's exact 2.7.30 header marks the state
function non-thread-safe and defines `numFramesActuallyPresented` since the
previous call, so a second observer could perturb Darktide's own query.

A confirming 90-second authenticated hub run observed one successful state
query with ABI version 3, status 0, minimum dimension 100, maximum generation
count 1, and an input-completion fence. The setter initially used mode 0 on
viewport 1488243306. Its first sampled mode-1 call was option call 2,760 at
Present 4,574 on viewport 1821058217; every later sample remained mode 1 with
one generated frame requested and result 0. Calls arrived from multiple worker
threads, while the outer Present samples retained one thread, one swapchain and
one COM identity. The run submitted 8,461/8,461 OpenXR frames, advanced 1,402
fresh shared pairs, and reported zero reuse, capture failures, stale frames,
pair-driven timeouts or pair-pose mismatches. This proves Darktide activates
DLSS-G on its gameplay viewport.

The observe-only probe now also unwraps Streamline's proxy through its exact
`StreamlineRetrieveBaseInterface` IID and hooks the native swapchain Present
target in Windows `dxgi.dll` 10.0.26100.9168. Before DLSS-G mode 1, every outer
Present produced exactly one native Present on the game thread. After mode 1,
extra native calls appeared on a second thread against the same native
swapchain. At sampled outer frame 6,120, the native count was 7,653: 1,533
surplus calls, effectively one generated call per source frame since
activation. The first sampled asynchronous call was native call 4,680 at outer
frame 4,633. Its pre-Present backbuffer was accessible through `GetBuffer` and
was 2496x2688 `DXGI_FORMAT_R8G8B8A8_UNORM`; later asynchronous samples retained
the same swapchain and valid rotating backbuffers. The confirming run submitted
8,481/8,481 OpenXR frames, delivered 1,344 fresh pairs, and retained zero reuse,
capture failures, stale frames, pair-driven timeouts or pose mismatches.

This closes the generated-call interception question: the output reaches an
addressable seam before native scanout. The remaining hard gate is a safe GPU
synchronization and copy experiment that assigns an exact source/generated
pair index and transports the generated resource without stalling or racing
the plugin's private queue.

The next observe-only trace identified that queue. For 26 of 29 sampled
asynchronous Presents, the immediately preceding global `ExecuteCommandLists`
snapshot was on the same secondary thread, used one command list on one direct
D3D12 queue, and preceded Present by an average 86 microseconds with a
124-microsecond maximum. The other three snapshots were overwritten by
concurrent queue traffic rather than contradicting the same-thread sequence.
The third 90-second run again showed
mode 1 and 1,668 surplus native calls by sampled outer frame 6,120. It submitted
8,371/8,371 OpenXR frames with 1,377 fresh shared pairs, zero reuse, capture
failures, stale frames and pair-driven timeouts; one pair-pose mismatch was
reported.

A 64-entry lock-free execute history removed the fragile same-thread
assumption and correlated every sampled Present with all submissions in the
preceding five milliseconds. In the confirming observe-only run, 144 command
submissions contained a hooked swapchain transition to `PRESENT`; all 144 used
exactly one direct queue. That resource-semantic queue was also the stable
immediate precursor to generated native Presents. This is stronger evidence
than timing alone and lets the probe retain the queue through the existing
`swapchain_present_queue` COM reference.

The opt-in `-StreamlineCopyProbe` then performed exactly one non-blocking GPU
readback on that transition-verified queue. At asynchronous native call 4,440
and outer frame 4,441 it transitioned the addressable 2496x2688 generated
backbuffer from `PRESENT` to `COPY_SOURCE`, copied a centered 64x64 tile to a
readback buffer, restored `PRESENT`, and used a queue fence for deferred CPU
mapping. The copy completed successfully: all 16,384 bytes were nonzero, byte
range 101-255, FNV hash `3e0488ee207d8211`. No additional Streamline API call
was made and the native Present was still forwarded exactly once.

The 100-second copy run submitted 8,789/8,789 OpenXR frames and delivered 1,852
fresh shared pairs. It reported zero reused shared frames, capture failures,
stale frames, pair-driven timeouts or pair-pose mismatches. The analyzer found
one schedule and one successful completion, and the launcher restored both
run-scoped probe flags. This closes the safe single-frame readback gate: a
generated DLSS-G output is demonstrably addressable and copyable before native
scanout without disturbing the production stereo transport. The next step is
to assign source/generated pair identities and prototype bounded transport of
generated outputs; do not infer pair identity from alternating Present calls
alone.

The follow-up pair-identity trace wraps Darktide's existing imported
`slGetNewFrameToken` and `slSetConstants` calls, forwarding each exactly once.
Darktide supplied an explicit, unique frame index on every observed token call;
the 100-second run recorded 1,080 successful token calls over six recycled
token objects and 2,061 successful constant updates over three viewports. A
bounded 240-native-Present burst carried the latest Streamline token identity
and frame index into every output record.

Once DLSS-G owns presentation, both source and generated native Presents run on
its worker thread, so thread identity is not an output label. The bounded burst
instead found 111 Presents immediately preceded by a one-list direct submission
on one verified queue, 61-300 microseconds earlier, and 129 Presents without
that generator submission. The sequence was predominantly generated/source but
contained source-only gaps and pacing reorderings. This provides a semantic
generated-output classifier (the plugin's generation submission plus
Streamline's source token), while disproving strict alternating-call pairing.
Transport must use the classifier and tolerate missing/reordered generated
outputs rather than incrementing a synthetic pair counter on every other call.

The classifier is now explicit in the native hook. A deliberately over-strict
first copy attempt required the generator submission and the swapchain
transition to use the same queue; it safely classified zero candidates and
performed no injection. Complete trace data showed that the one-list generator
submission uses a stable direct queue distinct from the transition/presentation
queue. The corrected design therefore uses the generator queue only to label an
output and retains the independently proven transition/presentation queue for
copy ordering.

The corrected 100-second run classified 121 of the 240 bounded asynchronous
Presents as generated candidates and 119 as source candidates. Every generated
candidate correlated with the same generator queue, 52-269 microseconds before
Present (102.71-microsecond average). Exactly one generated candidate was copied
on the retained presentation queue; the centered 64x64 sample completed with all
16,384 bytes nonzero, byte range 103-255 and FNV hash `2ae8b893882dec43`.
OpenXR submitted 8,742/8,742 frames with 1,869 fresh shared pairs and zero
reused frames, capture failures, stale frames, pair-driven timeouts or pose
mismatches. This closes the output-labeling gate without assuming queue identity
or strict source/generated alternation. The next transport prototype can carry
the explicit Streamline frame index, generated/source label and missing-output
tolerance into a bounded producer/consumer ring.

The opt-in `-StreamlineTransportProbe` now exercises the producer half of that
ring without exposing an unproven cross-process ABI. It owns three reusable
full-resolution GPU slots, submits only classified generated outputs on the
transition/presentation queue, tags each slot with the latest explicit
Streamline frame index and native-call identity, and never waits on the CPU.
A slot is reused only after its private completion fence advances; a saturated
ring drops the candidate rather than blocking Streamline. The diagnostic is
bounded to 120 submissions.

The first 100-second transport run moved 120/120 unique generated frame indices
at 2496x2688 RGBA8, completed every GPU fence, and reported zero ring-full or
resource failures. Only two of the three slots were needed at the observed GPU
latency, leaving one slot of headroom. The concurrent OpenXR run submitted
9,541/9,541 frames, delivered 1,292 fresh shared pairs, and reported zero
reused frames, capture failures, stale frames, pair-driven timeouts or pose
mismatches. This proves bounded, non-blocking full-frame staging. The remaining
transport gate is to give these slots stable shared handles plus producer-ready
and consumer-consumed sequencing, then make the XR bridge select outputs by
explicit metadata rather than timing or alternation.

The cross-process contract now exists independently of the live hook. A
versioned seqlock metadata mapping publishes writer generation, latest sequence,
2496x2688/format identity, and per-slot sequence, native-call and Streamline
frame-index identity. Sequence N deterministically maps to `(N - 1) % 3`, and a
new writer generation resets sequence so a surviving bridge cannot confuse a
producer restart with old ring contents. The bridge-side D3D12 helper opens and
validates all three typed textures plus shared ready and consumed fences. Unit
tests cover five metadata publications across slot wrap, writer restart, and
real named-handle opening from a second D3D12 interface. The next change should
replace the transport probe's private surfaces/fences with this tested shared
contract, retaining its non-blocking saturation policy.

The live transport now uses that contract. Its three output textures are
cross-process D3D12 shared resources, with one shared producer-ready fence and
one consumer-consumed fence. The producer publishes metadata before submitting
the copy and ready-fence signal, never waits for the consumer, and reuses a slot
only after the consumed fence reaches that slot's prior sequence. The first
deployment exposed an initialization bug: newly created command lists had not
been closed before their first reset, so all 122 attempted candidates failed
closed with `command_reset_failed`; no unsafe submission occurred and the
concurrent XR run remained healthy. Closing each list during initialization
fixed the defect.

An independent D3D12 consumer executable then opened the named metadata,
textures and fences, waited for each ready sequence, copied a center pixel from
the deterministic slot, returned the texture to `COMMON`, and signalled the
consumed sequence. A deliberately short observation window first delivered and
acknowledged 118/118 frames with one `ring_full` drop, confirming that consumer
backpressure drops rather than stalls Streamline. Expanding only the bounded
classification window produced the final clean proof: 120/120 contiguous
transport sequences submitted and completed across all three slots, zero drops,
and 120/120 nonzero pixel samples in the external process. Those sequences
covered 119 distinct Streamline source-frame indices because one source index
legitimately repeated; transport identity therefore uses its own monotonic
sequence rather than requiring frame-index uniqueness.

The enclosing 100-second run submitted 8,982/8,982 OpenXR frames, delivered
1,784 fresh shared-eye pairs, and reported zero not-rendered, stale, reused,
capture-failure, timeout or pose-mismatch frames. The analyzer independently
confirmed 120 submits, 120 completions, three slots, 120 unique contiguous
sequences, the expected 2496x2688 RGBA8 resources, and no fatal or saturation
drops. This closes the cross-process mechanics gate, but the transported image
is still Darktide's single desktop generated output, not a matched binocular
pair. It must not enter XR presentation until independent left/right inputs and
pair identity are proven.

The next observe-only layer mirrors NVIDIA Streamline 2.7.30's exact resource,
tag and extent ABI and wraps Darktide's existing `slSetTag` and
`slSetTagForFrame` exports. It forwards each call exactly once, makes no new
Streamline calls, and records only a bounded startup/generated-Present window.
The live run used only legacy `slSetTag`, with every resource marked
`eValidUntilPresent`; no frame token is attached by that API. The producer's
already-armed capture boundary supplied an independent logical-eye label for
each call without changing rendering.

The 100-second confirming run established an exact dynamic mapping: one
gameplay viewport was exclusively eye 0 and the other exclusively eye 1 during
the bounded sample; a third viewport appeared only outside an armed gameplay
eye. Each eye made 119 depth, motion-vector and HUD-less-colour tag calls, plus
120-121 scaling input/output calls. Both eyes use distinct 2496x2688 format-27
HUD-less colour resources. Critically, they alias the same 1664x1792 format-19
depth texture, the same 1664x1792 format-33 motion-vector texture, the same
1664x1792 format-26 scaling input and the same 2496x2688 format-26 scaling
output. DLSS-G mode-1 options were set only on the primary eye-0 viewport.
The analyzer now turns this census into a fail-closed contract:
`resource_tag.stereo_input_ready=0` with
`resource_tag.stereo_input_blockers=cross_eye_aliasing`. Both eyes contain all
five required tag classes, while the four shared temporal/scaling classes are
named explicitly. It also reports `resource_tag.ui_color_alpha.samples=0`;
Darktide supplied HUD-less colour but no separately tagged UI colour/alpha in
the bounded run.

The same observe-only layer now mirrors Streamline 2.7.30 common constants v2
and records the values Darktide already supplies, including all five row-major
matrices. A bounded lock-free 16-entry token history resolves constants against
the monotonic frame index despite the game's multithreaded calls and
Streamline's six reused token pointers. The confirming run captured 119
complete left/right frame-index pairs; all 119 pairs shared the exact token and
jitter. Both eyes used motion-vector scale `-1,-1`, non-inverted depth, camera
motion included, 2D undilated and unjittered motion vectors, near/far
`0.08/1000`, FOV `1.90447712`, and aspect `0.928571403`. Mean camera-position
separation was `0.06259995` (range `0.06259966`-`0.06260015`), matching the
OpenXR runtime IPD of `0.0626`. The projection/inverse/lens matrices remained
stable per eye while both temporal clip transforms evolved frame by frame.

Because legacy `slSetTag` has no frame parameter, the analyzer correlates each
tag to the nearest constants call sharing its exact logical eye, viewport and
armed pose. The confirming run resolved all 1,200 gameplay resource tags. The
early depth, motion and HUD-less calls were only 60.60 microseconds from their
matched constants on average (227.10 microseconds maximum); the full set,
including later scaling calls, averaged 920.36 microseconds with an 18.295 ms
maximum. This yielded 118 complete early-resource frame pairs and 119 complete
scaling pairs. Depth and motion aliased on all 118 early pairs; scaling input
and output aliased on all 119 scaling pairs; HUD-less colour aliased on zero of
118 pairs. A trial forward label agreed with the offline join on only 483/618
comparable tags when poses repeated, so it was removed rather than promoted to
architecture.

This explains why the present-seam output is unsuitable for direct binocular
submission: the existing sequential dual-render path has two colour endpoints
but does not preserve independent per-eye temporal inputs through Present. A
valid next prototype must snapshot or allocate independent depth, motion and
scaling histories per eye, pack both eyes into one side-by-side backbuffer, and
tag two viewports under one explicit frame identity before invoking DLSS-G. The
confirming run itself remained clean at 8,829/8,829 OpenXR submissions, 1,869
fresh shared pairs, zero reuse, capture failures, stale frames, timeouts or pose
mismatches.

The later constants-identity confirming run remained clean at 8,725/8,725
OpenXR submissions, 1,848 fresh shared pairs, and zero reuse, capture failures,
stale frames, timeouts or pose mismatches.

The implementation groundwork now includes a platform-neutral C++ stereo-input
policy. It accumulates the five required resource identities for each eye and
fails closed on incomplete sets, mismatched frame identities, null resources,
or any cross-eye alias. It reports an exact aliased-resource bitmask and marks
inputs ready only when both complete sets are same-frame and fully distinct.
This is the invariant the future D3D12 snapshot path must satisfy before it can
reach Streamline evaluation or XR publication.

The frame-level resource confirming run remained clean at 8,949/8,949 OpenXR
submissions, 1,867 fresh shared pairs, and zero reuse, capture failures, stale
frames, timeouts or pose mismatches.

The resource observer now also timestamps the existing per-eye output-copy
boundary around the exact game `ExecuteCommandLists` call and after the
diagnostic copy is enqueued. It remains observe-only and bounded to the same
240-native-Present burst. The live run recorded 240 complete begin/end/capture
triples. Correlation uses logical eye, armed pose and outer present frame so a
pose reused by the following frame cannot be mistaken for the prior boundary.
All 238 matched depth, motion-vector and HUD-less-colour tag groups occurred
before their eye boundary. All 240 scaling input/output groups also occurred
before it, by 0.555-4.420 ms (1.576 ms average). The early three-resource tag
groups preceded it by 1.318-6.011 ms (3.657 ms average). This establishes a
CPU ordering seam at which the current eye's complete tagged resource set is
known before the game submission that completes the captured eye output. It
does not yet prove those resources are safe to copy there: the next diagnostic
must preserve the observed D3D12 states and order copies on the resource-owning
queue without changing Streamline traffic or publishing aliased inputs.

That run remained clean at 8,793/8,793 OpenXR submissions, 1,863 fresh shared
pairs, and zero capture failures, stale frames, timeouts, reuse or pose
mismatches.

The first opt-in snapshot probe now exercises that seam without changing any
Streamline call or publishing diagnostic resources. On one matched frame it
retains the exact depth tag for each eye, transitions the observed state 128 to
copy-source and back, and enqueues each copy on the existing eye's direct queue
after the game submission. A dedicated fence proves completion without a CPU
wait. The live pair used one aliased 1664x1792 format-19, flags-2 source for
both eyes and produced two distinct committed destinations. Both scheduled
copies shared present frame 4,542 and pose 7,130; fence value 2 completed and
the analyzer reported `source_alias=1`, `snapshot_alias=0`, and `result=pass`.
The run remained clean at 8,805/8,805 OpenXR submissions, 1,687 fresh pairs,
and zero capture failures, stale frames, timeouts, reuse or pose mismatches.
This proves state-preserving per-eye preservation is mechanically viable for
depth. It does not prove content divergence yet; the next expansion should
copy all five classes and add GPU/readback evidence that the two preserved
depth images contain different eye-time content.

That mechanism is now generalized behind `-StreamlineInputSnapshotProbe`.
The confirming run copied depth, motion vectors, HUD-less colour, scaling
input and scaling output for both eyes on one matched frame/pose. The live
source alias mask was 27: depth, motion, scaling input and scaling output were
shared while HUD-less colour was not. All ten committed snapshot identities
were unique, the cross-eye snapshot alias mask was zero, and fence value 2
completed. The run remained clean at 8,781/8,781 OpenXR submissions, 1,869
fresh pairs, and zero capture failures, stale frames, timeouts, reuse or pose
mismatches. These completed resources are now evaluated by the same C++
five-class invariant used for the planned integration; only its explicit
`ready` verdict can promote a diagnostic pair to the next stage.

The policy-confirming run reported `policy_status=3` (`ready`),
`policy_aliased_mask=0`, and `input_snapshot.ready=1`. It submitted
9,939/9,939 OpenXR frames with 1,240 fresh shared pairs and zero capture
failures, stale frames, timeouts, reuse or pose mismatches. The next gate is
content identity: fence-complete GPU readback must show that the separately
timed snapshots are populated and, where eye-dependent content is expected,
not byte-identical.

That content gate now passes. The probe performs one fence-ordered, nonblocking
readback after the ten snapshot copies complete. It uses driver-derived placed
footprints, copies the full depth subresource as D3D12 requires, and hashes a
centered 64x64 region from every resource. All ten samples were populated and
all five eye pairs differed (`content_divergent_mask=31`): depth hashes were
`91723da6b17ff476`/`8ac40b2ecb5de771`, motion vectors
`70598842c8c7297f`/`486edabaf701d165`, HUD-less colour
`bc90cd93ba3c4b75`/`4ac4ff4c6b2b1675`, scaling input
`4e2a5bfb2adb8f8c`/`3eee8747c6b25062`, and scaling output
`618188e69f3e1b63`/`acb7cb0b5d5d705a`. The analyzer reported `result=pass`.
The confirming run remained clean at 8,258/8,258 OpenXR submissions, 1,069
fresh pairs, and zero capture failures, stale frames, timeouts, reuse or pose
mismatches. This closes the independent-content prerequisite; no snapshot was
published to XR or passed to a Streamline evaluation.

The preserved pair is now also bound to its exact observed Streamline temporal
identities. Each eye retains its full version-2 constants plus frame token,
resolved frame-token call/index and viewport handle. The stereo-input policy
uses the common armed pose as the pair identity and fails closed unless source
token calls/indices are the same or adjacent while viewports and constants
calls are distinct. One Psykhanium confirmation resolved both eyes to token
call 4,644 and frame index 4,643, with constants calls 2,749/2,750 and
viewports 1,342,883,970/2,738,829,751. Another valid pair used adjacent source
indices 4,648/4,649. All ten snapshots again passed the content gate with
`content_divergent_mask=31`. This proves neither outer Present equality nor one
shared source token is a universal join key; a future stereo evaluation must
allocate one new target token after both source snapshots are ready.

The first packed output resource is now complete without invoking Streamline.
After the snapshot readback fence, the probe copies the two preserved scaling
outputs into x=0 and x=2,496 of one 4,992x2,688 format-26 texture on the same
direct queue, restores both sources, transitions the destination to the
observed unordered-access state 8 and proves fence value 4. The analyzer
requires exactly one scheduled/completed pack, the 2:1 extent invariant and no
failure, and reported `result=pass`. This texture was not passed to Streamline
or published to XR.

A header-only evaluation-transaction policy now guards the next step before
any new Streamline call exists. It requires snapshot readiness, same-or-adjacent
source token calls/indices, distinct source viewports, a non-null target token
whose index follows both sources, an exact 2:1 format-26/state-8 backbuffer and
a reserved transport slot. After submission it remains non-publishable until
the generated-output fence completes. Unit coverage exercises every rejection
and the `ready_to_evaluate`, `awaiting_generated_output` and
`ready_to_publish` transitions.

## Runtime evidence

The initial 30-minute hub run completed with:

- `result=pass`, 163,308/163,308 submitted OpenXR frames;
- 40,668 fresh shared pairs and zero reused shared frames;
- zero pair-pose mismatches, capture failures or stale-frame failures;
- clustered-light correction at 564,414/564,414 patches, with zero rejects,
  root misses or resource misses at the last live report.

Window and shared-eye diagnostics are under ignored
`artifacts/unattended/*-20260903*`. An accidental `--help` invocation of the
window-capture helper was moved intact to
`artifacts/unattended/accidental-eye-capture-help-20260903`; no repository
source was removed.

## Validation commands

```powershell
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 1800 -GameStartTimeoutSeconds 600 -AutoEnterHub
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr_native_capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr-shared-eye-surfaces-tests
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release -R 'shared_eye_surfaces|native_capture_hooks' --output-on-failure
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 600 -GameStartTimeoutSeconds 600 -AutoEnterHub -EnableMenuInput -EnableMenuTestControls -SkipDeploymentSync
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 300 -GameStartTimeoutSeconds 600 -AutoEnterHub -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-flow-visible-20260903 4 2496 2688
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-controller-publisher.exe --seconds 360 --weapon-aim-matrix --neutral-body-pose
.\tools\stereo\start-darktide-vr.ps1 -OfflineDualViewBenchmark -SyntheticWeaponAimMatrix -DurationSeconds 150 -GameStartTimeoutSeconds 600 -SkipDeploymentSync
.\tools\stereo\start-darktide-vr.ps1 -SyntheticWeaponAimMatrix -DurationSeconds 180 -GameStartTimeoutSeconds 600 -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-flow-production-synthetic-20260903 12 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -SyntheticWeaponAimMatrix -DurationSeconds 120 -GameStartTimeoutSeconds 600 -SkipDeploymentSync
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 150 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-compact-only-dense-cycle-20260903 60 2496 2688
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-profile-glove-only-dense-20260903 60 2496 2688
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-imperial-guard-b-dense-20260903 40 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 180 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-rigid-one-sided-dense-20260903 60 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 155 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-rigid-astra-dense-20260903 30 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 150 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-rigid-masked-wrists-dense-20260903 60 2496 2688
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 150 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-rigid-baseline-restored-20260903 30 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 120 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-rigid-servitor-singular-20260903 30 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 150 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts\unattended\hand-rigid-glove-servitor-underlay-20260903 40 2496 2688
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 105 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 95 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -SkipDeploymentSync
.\tools\stereo\sync-darktide-vr-dev.ps1
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build/windows-vs2022 --config Release --target darktidevr-xr-harness darktidevr-tracked-cuff-tests darktidevr-tracked-cuff-renderer-tests
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build/windows-vs2022 -C Release --output-on-failure -R '^(tracked_cuff_mesh|tracked_cuff_renderer|xr_harness_help)$'
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe --frames 1 --require-rendering --xr-frames 120 --shared-eyes --synthetic-controller-path --tracked-cuff-overlay
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 120 -GameStartTimeoutSeconds 600 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -TrackedCuffOverlay -SkipDeploymentSync
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr-core-math-tests darktidevr-synthetic-controller-tests darktidevr-tracked-cuff-renderer-tests darktidevr-xr-harness
.\build\windows-vs2022\tests\core_math\Release\darktidevr-core-math-tests.exe
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-controller-tests.exe
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-tracked-cuff-renderer-tests.exe
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 150 -GameStartTimeoutSeconds 600 -SyntheticWeaponAimMatrix -SyntheticBodyPath -SyntheticBodyInspection -TrackedCuffOverlay -SkipDeploymentSync
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 150 -GameStartTimeoutSeconds 600 -SyntheticWeaponAimMatrix -SyntheticBodyPath -TrackedCuffOverlay -SkipDeploymentSync
& .\build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe --frames 1 --require-rendering --xr-frames 120
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Debug --target darktidevr-xr-harness
.\tools\unattended\invoke-unattended-preflight.ps1 -RunXrSmoke -XrFrames 120
& 'C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe' 'build\windows-vs2022\src\producer\darktidevr_native_capture.vcxproj' /m /p:Configuration=Release /p:Platform=x64 /t:Build /v:minimal
.\build\windows-vs2022\tests\native_capture\Release\darktidevr-native-capture-tests.exe .\build\windows-vs2022\src\producer\Release\darktidevr_native_capture.dll
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 90 -StreamlineProbe -AutoEnterHub
.\tools\stereo\read-streamline-probe.ps1
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 100 -StreamlineCopyProbe -AutoEnterHub
.\tools\stereo\read-streamline-probe.ps1
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 100 -StreamlineTransportProbe -AutoEnterHub
.\tools\stereo\read-streamline-probe.ps1
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build/windows-vs2022 --config Release --target darktidevr-generated-frame-state-tests darktidevr-shared-eye-surfaces-tests -- /p:TreatWarningsAsErrors=true
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build/windows-vs2022 -C Release -R '^(generated_frame_state|shared_eye_surfaces)$' --output-on-failure
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build/windows-vs2022 --config Release --target darktidevr_native_capture darktidevr-generated-frame-consumer -- /p:TreatWarningsAsErrors=true
.\build\windows-vs2022\tests\generated_frame_transport\Release\darktidevr-generated-frame-consumer.exe 120
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 100 -StreamlineTransportProbe -AutoEnterHub
.\tools\stereo\read-streamline-probe.ps1
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 100 -GameStartTimeoutSeconds 600 -StreamlineInputSnapshotProbe -AutoEnterHub -SkipDeploymentSync
.\tools\stereo\read-streamline-probe.ps1
```

The Lua source gate passed at 198/198 file-scope locals throughout. The native
hook and rebuilt shared-surface tests passed. Mandatory preflight reports for
the later hand-surface work include
`artifacts/unattended/preflight-20260902T212336Z.json` and
`artifacts/unattended/preflight-20260902T213527Z.json`. The material-mask
rejection and baseline restoration used
`artifacts/unattended/preflight-20260902T232345Z.json` and
`artifacts/unattended/preflight-20260902T232452Z.json`; the deployed-baseline
confirmation used `artifacts/unattended/preflight-20260902T232544Z.json` and
the final clean-state check used
`artifacts/unattended/preflight-20260902T232904Z.json`. The final semantic
catalog sweep and clean-baseline restoration used the later
`preflight-20260903T004741Z.json` through
`preflight-20260903T005727Z.json` reports. The compositor cuff build, synthetic
OpenXR exercise, live private-range run and GPU pixel test used
`preflight-20260903T010908Z.json` through
`preflight-20260903T011706Z.json`. The synchronized readback and synthetic-pose
correction used `preflight-20260903T013512Z.json` through
`preflight-20260903T015301Z.json`.

## Next work

1. Prototype independent per-eye Streamline inputs and one side-by-side stereo
   backbuffer. The current eye viewports share depth, motion and DLSS scaling
   allocations and only the primary viewport enables DLSS-G, so do not route
   the transported desktop generated image into XR presentation. The bounded
   diagnostic snapshot now proves fence completion, unique identities, a
   `ready` fail-closed policy verdict and distinct content for all five input
   classes. The preserved pair is now bound to one exact observed Streamline
   source frame token/index records, two version-2 constants records and two
   viewport handles. Source indices may be the same or adjacent for one pose;
   a future evaluation must allocate one new shared target token. The
   diagnostic 4,992x2,688 side-by-side scaling-output resource now packs and
   reaches its fence without changing live presentation. Next define and guard
   the opt-in evaluation transaction. The pure transaction policy is now in
   place; next connect its transport-slot reservation without issuing an
   evaluation. Preserve the external consumer as the later binocular-output
   transport gate.
2. Perform worn inspection of the opt-in compositor cuff against the proven
   independently rooted one-sided gloves. Calibrate its grip-relative offset,
   radii and length if its alignment is sound; reject the route if the lack of
   game depth causes unacceptable weapon/world occlusion.
3. Perform the worn Options extent, cursor and representative control pass;
   do not change the proven pointer transform without contrary evidence.
4. Perform the required worn Penances clustered-light acceptance.
5. Complete worn independent-hand acceptance, then continue HUD and
   world-marker resolution/placement work.
