# Warhammer 40,000: Darktide VR Mod

## Comprehensive design brief

- **Status:** Research and pre-production brief
- **Date:** 23 August 2026
- **Target:** Windows PCVR, Steam build first
- **Primary runtime:** OpenXR 1.1
- **Baseline game artifact inspected:** Darktide `1.12.0-b773907`, executable file version `1.3.770.210`
- **Confidence:** Architecture recommendation - medium; camera seam - medium/high; stereo mode feasibility - unproven; anti-cheat compatibility - unresolved release blocker

---

## 1. Executive decision

Build this as a **hybrid injected VR renderer with an optional Darktide Mod Framework (DMF) companion**, not as an ABI/Godot port.

The native component should own:

- OpenXR session, spaces, views, swapchains, actions, and haptics;
- D3D12 interception, frame-boundary detection, backbuffer/depth capture, GPU synchronization, and composition;
- late head-pose sampling and additive camera/projection changes;
- stereo scheduling and safe fallback modes;
- HUD extraction/composition where it can be identified reliably; and
- frame timing, diagnostics, crash containment, and version/capability probes.

The optional DMF component should own only game-semantic policy that can be expressed safely in Lua:

- identifying gameplay, hub, menu, loading, downed, cutscene, and spectator states;
- suppressing or scaling camera shake, head bob, forced roll, and other discomfort effects;
- configuring existing FOV, near-plane, reticle, subtitle, and HUD behavior;
- exposing user options and an in-game emergency disable; and
- providing low-rate context to the native component if a robust local IPC seam is proven.

Darktide remains authoritative for simulation, input validation, combat, animation, AI, physics, inventory, progression, matchmaking, and networking. The VR layer changes how the local user sees the game and expresses ordinary supported input. It must not alter damage, cadence, stamina, reach, hit testing, cooldowns, target acquisition, inventory, currency, progression, or any data visible to other players.

### Recommended stereo strategy

Use a capability-driven ladder rather than betting the product on one render method:

1. **Mono projection / head-tracked diagnostic mode** - first bring-up and universal safe fallback.
2. **Synchronized sequential stereo (same simulation tick)** - preferred quality mode only if a render-scoped second view and tick/snapshot lock can be demonstrated without affecting networking, audio, jobs, physics, animation, or watchdogs.
3. **Alternate-eye rendering plus alternate-frame warp (AER + AFW)** - likely practical shipping baseline if same-tick stereo is unsafe or too costly.
4. **Depth-assisted stereo reprojection** - an optional performance mode after depth capture is proven.
5. **Optical-flow frame generation** - late optimization, never a prerequisite for the first playable release.

Plain cross-tick AER is a diagnostic mode, not an acceptable default. Its stale-eye disparity, temporal rivalry, TAA interaction, and per-eye update rate are especially hazardous in Darktide's fast lateral movement and dense melee combat. UEVR similarly describes synchronized sequential rendering as fully synchronized while warning that unsynchronized AFR can cause eye desynchronization and nausea ([UEVR rendering modes](https://github.com/praydog/UEVR/blob/master/README.md)).

### Release gate

Do not publicly distribute or test native injection in protected matchmaking until Fatshark has explicitly confirmed that this type of local rendering/input modification is acceptable. Fatshark allows mods only within stated boundaries and reserves warnings or bans for mods that affect unmodded players, service stability, progression/value, or toxic behavior; mods are unsupported and used at the player's own risk ([Darktide Modding Policy](https://forums.fatsharkgames.com/t/darktide-modding-policy/75407/1)). Darktide's Lua source also contains an Epic Online Services Easy Anti-Cheat client session path. DMF's existence is not evidence that arbitrary native graphics injection is sanctioned.

---

## 2. Product vision

The mod should make Darktide feel like a deliberate seated-or-standing PCVR adaptation of the existing game, not merely a large stereoscopic screen and not a balance-changing motion-control remake.

The intended experience is:

- the player's head is the view, with natural 6DOF lean and peek;
- locomotion, dodging, sprinting, crouching, jumping, weapon switching, abilities, and interactions preserve the game's existing rules;
- the right hand can eventually direct ordinary look/aim input without creating aim reach or turn speeds unavailable to a gamepad/mouse player;
- melee remains animation- and input-driven in the initial product, avoiding gesture-based damage or reach;
- the HUD is legible, stable, configurable, and never painted at an arbitrary scene depth;
- camera shake, forced roll, full-screen overlays, and cutscenes have deliberate comfort treatment;
- the mod fails to a safe mono/head-locked presentation instead of presenting invalid stereo; and
- installation, version mismatch, active render mode, and emergency exit are obvious to a non-developer.

### Success statement

A player can complete a full mission with normal online teammates using standard gameplay semantics, with stable binocular imagery, responsive head tracking, readable UI, no measurable service impact, and no unexplained mode changes or frame-time spikes.

---

## 3. Scope

### In scope

- Windows x64 Steam build first; Microsoft Store support after the Steam path is stable.
- OpenXR runtimes for SteamVR, Meta, Virtual Desktop/VDXR, Pimax, and Windows-compatible vendor runtimes.
- HMD rotation and translation, recentering, seated/standing offsets, snap/smooth turn, comfort vignette, and world-scale calibration.
- Gamepad and keyboard/mouse compatibility from day one.
- Optional tracked-controller input mapping that produces normal Darktide intent.
- Stereoscopic D3D12 presentation, depth capture, view/projection manipulation, HUD handling, and native mirror output.
- Gameplay, hub, menu, loading, cutscene, disabled/downed/grabbed, spectator, and mission-end states.
- Diagnostic captures and repeatable performance/comfort tests.

### Explicitly out of scope for the first public release

- Replacing Darktide's simulation, renderer, assets, or network stack.
- A Godot reimplementation or standalone headset port.
- Physics-based melee, arbitrary hand collision, manual magazine simulation, or new weapon mechanics.
- Full-body inverse kinematics visible to other players.
- Server protocol changes, custom lobbies, gameplay rebalance, or anti-cheat bypasses.
- DLSS/FSR multi-frame generation inside the VR path.
- Eye-tracked foveated rendering as a launch dependency.
- Linux/Proton support before Windows behavior is understood.

### Non-goals

- Pixel-perfect parity with the flat HUD.
- Supporting every OpenXR extension or every headset on the first build.
- Preserving cinematic composition at the cost of comfort.
- Hiding compatibility failures. An explicit fallback is preferable to plausible-looking broken stereo.

---

## 4. Evidence base and confidence

The recommendations combine four evidence classes. They should not be treated as equally certain.

| Evidence | What it establishes | Confidence |
| --- | --- | --- |
| Inspected local Darktide installation | D3D12-era renderer assets and DLLs, Stingray renderer naming, settings layout, executable/build identifiers, ray tracing/upscaler components | High for the inspected build |
| Public Darktide Lua source mirror | Camera tree, camera manager post-update path, first-person/ADS/sprint/cinematic modes, EAC client state, viewport and ScriptCamera calls | Medium/high; source mirror may lag or differ from a specific binary |
| DMF/DML repositories and Fatshark policy | Existing Lua hook/options/events ecosystem, bundle patching, update behavior, policy boundary | High for documented behavior |
| Local AER/6DOF PDFs and public VR frameworks | Established injector patterns, stereo taxonomy, timing hazards, validation methods, comparable implementation choices | High as design guidance; Darktide applicability remains to be proven |

### Observed locally

The inspected `bundle/application_settings/settings_common.ini` identifies `core/stingray_renderer/renderer`. `win32_settings.ini` exposes a D3D renderer, D3D debug/GPU validation switches, a deadlock detector, RTXGI state, console/crash logging, and window/render settings. The binary folder contains `D3D12Core.dll`, DLSS, DLSS frame generation, Reflex, FSR, XeSS, NRD, PIX event runtime, Wwise, and Oodle components. This is consistent with a heavily modified Fatshark branch of Bitsquid/Stingray and a modern D3D12 renderer, but it does not reveal the internal frame graph or prove a usable second-view call.

The inspected artifact reports game version `1.12.0-b773907`. Every signature, shader/pass identity, pointer chain, and capability record must therefore be keyed to build identity, not merely the marketing version.

### Public game-source findings

The public source mirror's camera settings define separate trees for world, cinematic, cinematic-gameplay, first-person, third-person/hub, downed/grabbed states, ADS, sprint, lunge, and scanning. The first-person root has an adjustable FOV, near range, and child nodes such as `FirstPersonAnimationCamera` and `AimDownSightCamera` ([camera settings](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/settings/camera/camera_settings.lua)).

The camera manager calculates a final `camera_data` in `post_update`, applies sequence/shake offsets, then writes position, rotation, FOV, custom FOV, near/far range, and forces the ScriptCamera update. This is an unusually useful semantic seam: it identifies where the clean game camera is finalized. It does not by itself solve stereo because Lua has no demonstrated route to create a second D3D12 view or OpenXR swapchain.

### Comparable mod findings

- **UEVR:** native engine stereo first, synchronized sequential as the compatibility alternative, AFR only as a last resort; 6DOF, OpenXR/OpenVR, projected UI, controller emulation, and roomscale are reusable product precedents ([UEVR](https://github.com/praydog/UEVR)).
- **REFramework:** a runtime abstraction plus D3D11/D3D12 components, camera integration, input bindings, and per-game adaptation shows the value of separating shared XR/rendering code from game-specific hooks ([REFramework](https://github.com/praydog/REFramework)).
- **BerZerker/Loop 6DOF family:** additive, version-scanned camera edits; capture-gate-edit; desktop wobble proof before tracking; OpenTrack UDP; INI-driven offsets; and an external OpenXR viewer provide a fast camera prototype pattern ([6DOF Head-Tracking Mods Hub](https://github.com/BerZerker96/6DOF-Head-Tracking-Mods-Hub)).
- **Osiris VR Viewer:** demonstrates a lower-risk external-viewer path using SBS/depth-derived stereo and 6DOF pose output, useful for validating camera feel before the native stereo renderer is complete ([Osiris VR Viewer](https://github.com/BerZerker96/Osiris-Vr-Viewer)).
- **Local ABI/Godot ports:** useful for boundaries, coordinate-space contracts, fixed-rate thinking, event/state separation, deterministic testing, asset ownership, and packaging discipline, but not for embedding a closed live-service game. See the local [native ABI and Godot guide](../../guides/vr/native-abi-godot-vr.md) and [Crimson VR architecture](../../crimson/docs/rewrite/architecture/abi-driven-godot-vr-port.md).

---

## 5. Darktide-specific constraints

### 5.1 Engine and rendering

Darktide is not Unreal or RE Engine, so neither UEVR nor REFramework can be adopted as a drop-in solution. Their architecture and techniques are references, not dependencies.

The design must assume:

- one engine-owned D3D12 frame graph and one normal scene view;
- substantial view-independent cost from horde simulation, animation/skinning, particles, shadows, ray-tracing support, streaming, and job submission;
- temporal reconstruction and frame-generation integrations that depend on motion vectors, jitter, history, and frame identity;
- dynamic resolution, window resize, device loss, loading/no-draw frames, and multiple cameras/passes;
- a separate shadow-cull camera and auxiliary render passes that must never receive eye transforms;
- the game may be CPU-bound in intense scenes; Fatshark explicitly notes frequent CPU limitation and designed DLSS frame generation around it ([Fatshark performance deep dive](https://www.playdarktide.com/news/dev-blog-performance)); and
- post-launch renderer changes are normal. Darktide has added FSR 3.1 and DLSS 4 multi-frame generation since launch ([FSR 3.1 update](https://www.fatshark.se/news/2022/3/31/darktide-release-date-announcement-6wsca-g8lx4-ssk5h-5fw2p), [DLSS 4 patch](https://www.playdarktide.com/news/nightmares-visions-patch-notes)).

### 5.2 Live service and anti-cheat

Darktide authenticates and plays through dedicated services. The public Lua mirror includes an EOS EAC client that authenticates, begins a client-server session, sets the server channel, and reports errors when EAC is absent. Treat native process injection as a policy and compatibility risk even if a local-only prototype appears to work.

Required controls:

- no anti-cheat disable, concealment, spoofing, or bypass logic;
- no protected matchmaking test until the policy gate is cleared;
- a prominent build banner stating experimental/unsupported status;
- log the loader route and EAC/session state without collecting credentials or tokens;
- a one-click clean-disable path that restores the original game files/configuration;
- never modify or ship Fatshark binaries, bundles, shader caches, assets, signing material, or authentication data; and
- keep the native renderer and DMF companion source available for review if a public release is pursued.

### 5.3 Update cadence

The Darktide Mod Loader states that game updates automatically disable mods and require re-enabling, while Fatshark support warns that large updates commonly make mods incompatible ([Darktide Mod Loader](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Loader), [Fatshark crash guidance](https://support.fatshark.se/hc/en-us/articles/7709661288733--PC-How-to-Resolve-Crashes-in-Darktide)). Native hooks add another failure surface.

Every supported build needs:

- executable SHA-256 and file/product version;
- content/game revision from settings;
- hook AOB IDs and matched address diagnostics;
- renderer pass census version;
- shader hashes and resolution classes;
- capability-probe result; and
- known-good driver, GPU, headset/runtime, and game-setting matrix.

Unknown builds start in **safe mono viewer mode with no memory edits**. Users may opt into a research probe, but stereo/camera hooks must fail closed.

---

## 6. Architecture options considered

| Option | Strengths | Weaknesses | Decision |
| --- | --- | --- | --- |
| ABI + Godot standalone port | Clean OpenXR, testable boundary, ideal UX control | Requires game source/simulation extraction; cannot preserve live service; asset/legal burden | Reject for Darktide |
| External viewer + DMF/6DOF camera | Fastest camera/comfort prototype; renderer isolation; no second engine view needed | Screen/depth stereo quality; extra capture latency; UI and temporal artifacts; still may require graphics hooks | Keep as research track |
| Native D3D12/OpenXR injector only | Lowest-latency render access; depth/motion-vector access; direct composition | Weak game-state semantics; difficult UI/cutscene policy; highest reverse-engineering and anti-cheat risk | Core renderer, but not alone |
| Native renderer + optional DMF companion | Strong render access plus semantic camera/UI states; clear modules and fallback | Two version surfaces; IPC seam must be proven; policy risk remains | Recommended |
| Official engine integration | Best correctness/performance and policy posture | Requires Fatshark cooperation/source access | Strategic ideal; not currently available |

---

## 7. Proposed system architecture

```text
OpenXR runtime / HMD / controllers
        ^                         |
        | stereo layers, HUD      | poses, actions, display timing
        |                         v
+---------------- DarktideVR.Native ----------------+
| XR lifecycle | pose/input | compositor | telemetry |
|        |             |            ^                 |
|        v             v            |                 |
| camera/projection patch       D3D12 frame capture   |
| render-pass census            depth / motion data   |
|        ^                                           |
+--------|-------------------------------------------+
         | build-scoped hooks and validated pointers
         v
+---------------- Darktide process ------------------+
| Fatshark simulation, networking, animation, audio  |
| camera tree -> ScriptCamera -> Stingray renderer   |
| D3D12 queues -> swapchain -> Present               |
+----------------------------------------------------+
         ^                         |
         | optional semantic hooks | context/options
         |                         v
+---------------- DarktideVR.DMF --------------------+
| mode detection | shake/bob policy | HUD policy     |
| settings UI | emergency disable | context export   |
+----------------------------------------------------+
```

### 7.1 Shared native core

Keep game-neutral code in a reusable library, inspired by REFramework/UEVR separation:

- `xr_runtime`: OpenXR instance/system/session, action sets, spaces, swapchains, extensions, event/state machine;
- `xr_timing`: dedicated wait/submission loop, predicted display times, late locate, compositor-rate tracking;
- `d3d12_intercept`: device/queue/swapchain discovery, command-list and resource tracking, resize/device-loss handling;
- `frame_ring`: at least four published GPU frame slots with acquire/release semantics and monotonically increasing fence values;
- `stereo_scheduler`: mono, synchronized sequential, AER, AFW, stereo warp, generation, and degradation state machine;
- `reprojection`: camera-only rotation warp first, depth-assisted translation/stereo later;
- `ui_compositor`: HUD classification, extraction, masking, quad/cylinder layer composition;
- `input_router`: OpenXR actions to ordinary keyboard/mouse/XInput intent, with user-mode paths only;
- `diagnostics`: log, overlay, timings, capability report, capture markers, crash-safe teardown; and
- `config`: versioned schema, conservative defaults, hot reload for presentation-only values.

### 7.2 Darktide adapter

All game-specific knowledge belongs behind an adapter:

- build fingerprint and AOB catalog;
- main camera address capture and validation;
- camera struct/layout or D3D12 constant-buffer fingerprint;
- view/projection convention and world-units-to-metres scale;
- frame/tick/render boundary hooks;
- pass census and overrides;
- backbuffer, scene depth, velocity, and UI resource classification;
- state mapping from DMF or native observations; and
- per-build known limitations.

No build address may leak into the shared XR core. The adapter must be replaceable and must refuse partial initialization.

### 7.3 DMF companion

DMF already provides shared Lua function hooks, keybinds, options, events, and compatible hook chaining ([DMF repository](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework)). Use those facilities instead of patching Lua functions independently.

The companion is not allowed to make frame-critical pose writes unless profiling proves a robust native-to-Lua transport and the write lands after the game's final camera update. Its primary value is semantics and policy:

- current camera tree/node and transition state;
- local player class/height and first-person state;
- menu/loading/cutscene/downed/grabbed/spectator flags;
- configured camera-shake multiplier;
- reticle/subtitle/HUD policy; and
- emergency disable/recenter commands.

Context transport may use a versioned localhost datagram or named shared memory only if the available Lua/native bindings support it without blocking. Otherwise, the initial native build should infer state and the DMF module should remain independent. Never poll files per frame.

---

## 8. Camera and coordinate design

### 8.1 Core rule: additive, idempotent, in-frame

For every render view:

```text
render_camera = clean_game_camera * calibrated_head_delta * per_eye_offset
```

Recompute from the clean game camera every time. Never accumulate `+=` offsets. Apply on the game/render thread at the point the renderer consumes the camera, and gate by the validated active gameplay camera. This follows the local 6DOF master reference's capture-gate-edit method and prevents drift, auxiliary-camera corruption, and racing the engine's per-frame rebuild ([6DOF master reference, pp. 3-16](<./6DOF-HeadTracking-Master-Reference-Revs6.pdf>)).

### 8.2 Named spaces

Maintain explicit transforms between:

- **OpenXR stage/local space:** metres, runtime-defined axes;
- **recenter space:** user's seated/standing reference and yaw origin;
- **VR body space:** locomotion-facing frame, height calibration, snap/smooth turn;
- **Darktide world space:** engine units and axis convention;
- **clean game camera space:** final camera after animation, recoil, shake, and transitions;
- **eye space:** left/right `XrView` pose and asymmetric FOV; and
- **weapon/aim space:** ordinary look/aim intent sent to the game, distinct from head view.

One tested mapper owns handedness, axis swaps, quaternion order, unit scale, recenter transform, and lean limits. No other module performs ad hoc coordinate conversion.

### 8.3 Camera discovery ladder

1. Use the Lua camera manager to identify semantic timing and active node names.
2. Find the native camera object or transform write/read using a signature scan keyed to the build.
3. Prove the target with a desktop six-axis wobble and no tracker.
4. Gate the edit to the active gameplay viewport/camera and reject shadow-cull, reflection, menu, cinematic, and dummy cameras.
5. If memory writes do not reach the displayed view, intercept the D3D12 constant-buffer upload/descriptor path and patch the validated view/projection immediately before GPU use.
6. Cross-check the candidate against render-target/pass identity, matrix structure, position continuity, FOV plausibility, and the clean Lua camera pose.

The mod must disable stereo immediately if camera confidence drops below threshold. It should keep the last valid frame head-locked for a short bounded interval, then fall back to a neutral mono layer.

### 8.4 Camera motion policy

Default policy by source:

| Source | Default VR treatment |
| --- | --- |
| Player yaw/pitch input | Drives body/aim; never directly overwrites HMD orientation |
| Head pose | Full 6DOF view, late sampled |
| Weapon recoil | Preserve weapon animation; reduce camera rotation/translation to 20-40% |
| Damage shake/explosions | 0-25%, comfort slider, zero forced roll |
| Sprint bob/sway | 0-20%, weapon motion may remain stronger than camera motion |
| Dodge/slide/lunge | Preserve translation through locomotion; vignette; suppress forced camera roll |
| Knockdown/grab/consume | Fade/vignette and clamp roll; optional head-locked theatre mode |
| Cinematics | Default to virtual screen; optional conservative 3DOF/6DOF if validated |
| Death/spectator | Stable theatre or spectator camera with explicit transition |

### 8.5 Collision and lean

Roomscale translation is visual only by default. Clamp the virtual head to a conservative capsule around the game camera and fade/vignette as it approaches geometry. Do not move the server-authoritative body because the player leaned. Do not permit leaning through walls to reveal hidden information. A depth-based near-plane/fade guard and a maximum horizontal/vertical lean limit are required.

---

## 9. Stereo rendering design

### 9.1 Mode ladder

| Mode | Use | Benefits | Principal risks |
| --- | --- | --- | --- |
| Mono quad/projection | Bring-up and safe fallback | Minimal engine intrusion | No stereo depth |
| Synchronized sequential | Preferred high-quality mode | Same-tick, paired, correct stereo | Two renders; re-entrancy; unsafe tick lock; CPU cost |
| AER + AFW | Likely practical baseline | One engine view per frame; low warp cost; good rotational freshness | Cross-tick world disparity, lateral motion, stale-eye artifacts |
| AER + depth stereo warp | Performance option | Synthesizes other eye at same instant | Disocclusions, particles, transparencies, HUD |
| Temporal generation | Late optimization | Raises display throughput | Flow artifacts, latency if interpolated, resource interop |
| Plain AER | Diagnostic only | Simplest stereo proof | Nausea, rivalry, half per-eye freshness |

### 9.2 Synchronized sequential feasibility gate

Do not implement global time freezing. The AER guide identifies audio/network stalls, watchdogs, job-system deadlocks, physics discontinuities, and animation corruption as predictable failures ([AER guide, pp. 48-54 and 78-79](<./AER_Modes_and_Optical_Flow_Frame_Generation_v3.pdf>)). Darktide is a networked, job-heavy horde game with an explicit deadlock detector, so the risk is unusually high.

Synchronized sequential is viable only if all of the following are proven:

- the renderer can be invoked or replayed for a second view without advancing simulation;
- both eyes reference the same immutable render snapshot;
- network, audio, job queues, particle simulation, animation state, and physics continue normally;
- TAA jitter/history, frame counters, exposure, temporal upscalers, and stochastic effects are either per-eye or deliberately shared;
- the second eye does not double-submit view-independent passes unnecessarily;
- both eye GPU completions can be paired to one predicted display time; and
- a differential test shows no simulation-visible state change between first and second view.

If any condition fails, ship AER + AFW instead of trying to disguise an unsafe tick lock.

### 9.3 AER + AFW baseline

The engine alternates left/right eye renders. For the stale eye, reproject from its captured render pose to the current predicted display pose. Start with rotation-only AFW because it needs no scene depth and removes the dominant head-rotation staleness at very low cost. Add depth-assisted translation after reliable depth capture.

Rules:

- eye assignment must come from a once-per-engine-frame signal, not a camera write that may occur multiple times;
- one capture latch per eye per engine frame;
- every slot records color, optional depth/motion, clean view/projection, render pose, eye, build/pass identity, capture sequence, and GPU fence;
- eye-slot publication uses acquire/release ordering and monotonically increasing fence values;
- head views are located every engine frame and again as late as practical for submission;
- cutscenes/loading/menu frames may stop alternation and use mono/theatre mode; and
- the scheduler tracks age/skew and prefers rendering the staler eye after hitches.

### 9.4 OpenXR timing

Keep three clocks separate: simulation, engine render, and HMD display. A dedicated XR timing/submission thread owns the blocking `xrWaitFrame`; the game render thread never waits on compositor pacing. Khronos specifies that `xrWaitFrame` throttles the application and may be called from a different thread than `xrBeginFrame`/`xrEndFrame`, with external synchronization ([OpenXR 1.1 specification](https://registry.khronos.org/OpenXR/specs/1.1/html/xrspec.html)).

The motion-smoothing fix is mandatory architecture, not a post-launch patch:

1. never block the game thread waiting for the XR grant;
2. continue capturing eye slots on engine frames that have no new XR submission grant; and
3. locate views on every engine frame before any early return.

The local guide documents the half-rate collapse, alternating eye freeze, and sawtooth head tracking caused by violating these rules ([motion-smoothing guide, pp. 9-18 and 22-28](<./VR-MotionSmoothing-AER-Fix-Guide.pdf>)).

### 9.5 Depth, motion vectors, and temporal systems

Build a render-pass census keyed by shader bytecode hashes, render/depth formats, dimensions, sample count, blend/depth state, and quantized resolution. Continuously validate it because menus, cinematics, dynamic resolution, ray tracing, and upscalers can change the pass set.

Depth requirements:

- identify the main opaque scene depth, not shadow/weapon/UI depth;
- copy/resolve it before clear/reuse;
- detect reversed-Z empirically;
- derive and validate near/far mapping;
- handle MSAA and dynamic resolution;
- never use stale depth after a capability regression; and
- visualize depth in-headset during bring-up.

Motion-vector support is optional. If found, calibrate units, scale, sign, Y orientation, jitter, and frame span against camera-derived motion. Never assume the engine's DLSS/FSR vectors can be consumed directly.

### 9.6 Upscaling and frame generation

- Support spatial resolution scaling from the start.
- Test DLSS/FSR/XeSS super-resolution separately per stereo mode; temporal history may require per-eye isolation or may be unusable in AER.
- Disable in-game DLSS/FSR frame generation and DLSS 4 multi-frame generation by default. Generated flat frames do not carry the mod's correct eye identity, pose, depth, or OpenXR display time.
- If VR generation is later added, use the mod's own stereo-aware extrapolation path. Prefer causal extrapolation to interpolation because interpolation adds a full source-frame of latency.
- Apply stereo/AFW correction before temporal frame generation so generation operates on coherent stereo pairs.

---

## 10. UI, HUD, menus, and cinematics

### 10.1 HUD strategy

Preferred order:

1. Identify the UI pass/resource and extract it before scene warp.
2. Composite as an OpenXR quad or shallow cylinder layer at configurable distance/size.
3. Preserve alpha correctly and keep the two eyes effectively identical.
4. If extraction fails, render the entire game in a comfortable theatre mode rather than warping small text with scene depth.

Default distances:

- core combat HUD: 1.8-2.2 m, 1.8-2.4 m wide;
- subtitles and interaction prompts: 2.0-2.5 m with optional gaze-follow lag;
- menus/inventory/crafting: larger head-locked or body-locked curved panel;
- reticle: engine HUD reticle on a stable layer for MVP; optional depth-aware reticle later.

The HUD may follow the head with a 120-200 ms critically damped lag and a 10-15 degree maximum deviation rather than being rigidly face-locked. Provide independent HUD scale, distance, opacity, curvature, and safe-area controls.

### 10.2 State behavior

| State | Presentation |
| --- | --- |
| Boot/loading | Neutral environment plus captured loading panel; no scene stereo if camera/depth absent |
| Login/Mourningstar menus | Theatre/curved panel; optional background scene stereo only when stable |
| Hub movement | Full VR with reduced locomotion speed policy only if the game already requests it |
| Mission gameplay | Selected stereo mode, world-space/quad HUD, full head tracking |
| ADS/scopes | Keep head view; controller/game aim drives weapon; magnified scopes default to a stabilized inset or theatre treatment |
| Auspex/scanner | Stable device panel; no forced camera takeover |
| Downed/grabbed/pounced/consumed | Strong vignette, roll clamp, optional instant theatre fallback |
| Cinematic | Default virtual screen with fade transition; opt-in 3DOF/full VR per validated sequence |
| Mission end/results | Theatre panel; release gameplay-specific resources after GPU completion |
| Alt-tab/HMD removed | Pause submission safely if runtime state allows; never stall the game thread |

### 10.3 Reticle and targeting

For MVP, the reticle represents game aim, not head gaze. If head-look and weapon aim diverge, display a small comfort-safe weapon reticle and optionally a faint head-forward marker for orientation. Never move the game aim silently to keep a target under the HMD center.

---

## 11. Input and interaction

### 11.1 Input tiers

**Tier 0 - gamepad/keyboard and mouse**

- Required for first playable build.
- HMD controls view; existing device controls locomotion and game aim/body orientation.
- Snap turn is implemented as body-yaw intent plus recenter-space adjustment, not by rotating the physical tracking space unpredictably.

**Tier 1 - tracked controller as conventional input**

- Left stick: movement; right stick: snap/smooth turn.
- Right-hand pointing maps to normal aim yaw/pitch with user-selected head-relative or body-relative reference.
- Triggers/grips/buttons map to the same existing attack/block/ADS/interact/reload/ability inputs.
- Haptics are presentation feedback only.

**Tier 2 - stabilized two-hand aiming**

- When support hand is near the weapon line and grip is held, blend its position into weapon orientation.
- Output remains ordinary aim angles; no new ballistic origin, recoil reduction, fire rate, spread, or server-visible reach.
- Apply a configurable stabilization filter with no prediction that could create aim assistance.

**Tier 3 - optional gestures**

- Gestures may trigger existing button actions only.
- No physical melee damage, variable swing strength, extended reach, automatic parry, or repeated attacks beyond the game's normal cadence.
- Default off until policy and balance review.

### 11.2 Input path rules

- Prefer OpenXR actions and user-mode input injection/hooking inside the already loaded mod.
- Do not require Interception, ViGEm, or other kernel drivers; they increase anti-cheat risk.
- Preserve the game's aim-assist setting and expose no stronger assistance. Darktide already offers Full, Light, Legacy, and Off controller aim-assist modes ([Patch #7](https://www.playdarktide.com/news/patch-7)).
- Edge-triggered actions must be sampled once; do not repeat a press on both eye renders.
- Simulation/game input is updated once per game tick, not once per XR submission or eye.
- UI pointer mode and gameplay aim mode have explicit transitions with visible cursor ownership.

### 11.3 Handedness and accessibility

Support left/right dominant hand, stick swap, one-controller mode where feasible, seated height, standing height, physical crouch toggle, snap angles, smooth-turn rate, hold/toggle actions, button remapping, haptic intensity, and independent subtitles/HUD scaling.

---

## 12. Comfort and safety specification

Defaults should favor sensitive users:

- snap turn 30 degrees, smooth turn available but off;
- smooth locomotion enabled because the game requires it, with acceleration vignette at moderate strength;
- camera roll zero unless explicitly opted in;
- camera shake 20%, sprint bob 10%, damage impulse 15%;
- roomscale lean clamped and faded near geometry;
- cutscenes and forced-camera states use theatre mode;
- HMD-relative locomotion optional; controller/body-relative recommended for sustained combat;
- emergency VR disable/recenter on a reserved controller chord and keyboard key;
- first-run calibration includes floor/eye height, forward direction, dominant hand, IPD/runtime check, world scale, and comfort preset; and
- display a warning and automatically degrade when the current mode repeatedly misses timing or loses stereo confidence.

Subjective sessions stop immediately on nausea or disorientation. Test transitions and hitches, not only steady state. The AER guide recommends blinded paired comparisons, time-to-discomfort measurement, sensitive testers, and explicit transition testing ([AER guide, pp. 44-47](<./AER_Modes_and_Optical_Flow_Frame_Generation_v3.pdf>)).

---

## 13. Performance budget

The budget is based on the HMD display interval, not flat-screen average FPS.

| Target | 90 Hz budget | 120 Hz budget |
| --- | ---: | ---: |
| Total display interval | 11.11 ms | 8.33 ms |
| Native VR overhead target (p99, excluding second engine view) | <= 1.8 ms | <= 1.2 ms |
| AFW rotation warp | <= 0.35 ms | <= 0.25 ms |
| Depth translation/stereo warp | <= 0.9 ms | <= 0.65 ms |
| UI extract/composite | <= 0.25 ms | <= 0.18 ms |
| CPU hook overhead at Present (p99) | <= 0.20 ms and never compositor-blocked | <= 0.15 ms |

These are design targets, not claims about the current build. A render census must first measure Darktide's view-independent, view-dependent, CPU submission, and fixed costs at multiple resolutions.

### Default graphics policy

- Ray tracing off.
- In-game frame generation off.
- Motion blur off.
- Depth of field, chromatic aberration, lens distortion, and film grain off where possible.
- Volumetrics, particles, shadows, ragdolls/corpses, decals, and screen-space effects exposed through a tested VR preset.
- Dynamic resolution allowed only after per-eye history/resource behavior is known.
- Super resolution tested mode-by-mode; recommend the lowest artifact setting that meets p99 timing.
- Mirror window at low cost with optional single-eye, stabilized, or cropped spectator view.

No performance option may alter enemy visibility or gameplay information beyond what the flat game's own graphics settings allow.

---

## 14. Capability probing and fallback

At startup and after every resize/device/render-mode change, probe and log:

- supported/active OpenXR runtime and extensions;
- HMD refresh rates, view configuration, swapchain formats, and recommended sizes;
- D3D12 device/queue/swapchain ownership;
- camera lock confidence and projection convention;
- render frame boundary and once-per-frame eye latch;
- scene color/depth availability and depth convention;
- motion-vector candidate and calibration;
- UI resource/pass identity;
- synchronized second-view and snapshot-lock viability;
- GPU timestamp/query availability and asynchronous compute feasibility; and
- current game build support level.

Fallback order must be explicit and visible:

```text
sync sequential -> AER + depth stereo warp + AFW -> AER + AFW
-> rotation-only AFW -> mono head-tracked projection -> head-locked theatre -> disabled
```

Descend after three bad frames; ascend only after at least 90 healthy frames; dwell at least 45-60 frames; never change a paired mode mid-pair; and show the active mode plus the reason for fallback in the headset. Do not oscillate.

---

## 15. Diagnostics and observability

### Mandatory log header

- mod/native/DMF/config versions;
- game executable hash, file version, game/content revision;
- GPU, driver, Windows build;
- headset, runtime name/version, refresh rate, render size, active extensions;
- loader route and whether EAC was observed, without tokens or identifiers;
- hook/AOB IDs, match counts, camera/projection confidence;
- depth/motion/UI/pass-census status; and
- selected stereo mode and fallback reasons.

### In-headset overlay

One glance should show:

- engine Present rate, XR submit rate, per-eye capture rate;
- app GPU time, synthesis GPU time, p50/p95/p99 frame time;
- missed display deadlines and repeated/held frames;
- active eye, eye age/skew, slot/fence state;
- camera confidence, depth age, motion-vector confidence;
- current camera/gameplay state;
- mode, degradation level, and transition cooldown; and
- `runFree`, capture-only, left/right capture parity, stale wait, and pose-locate counters.

The relationships matter more than absolute values. Under compositor half-rate operation, the engine rate should remain stable; run-free captures should be non-zero; per-eye captures should remain close; and poses must continue updating every engine frame.

### Capture package

A user-report bundle should contain only:

- sanitized log and config;
- capability block and pass-census hashes;
- recent frame-time histogram and counters;
- optional user-approved left/right/depth diagnostic images; and
- crash dump reference/path, not an automatic upload.

Never include account tokens, chat, player identifiers, inventory, network packets, or raw process memory.

---

## 16. Validation strategy

### 16.1 Headless/unit tests

- coordinate-space conversions and quaternion composition;
- asymmetric projection from `XrFovf`;
- world-scale/IPD calculations;
- recenter and seated/standing transforms;
- ring slot publication, sequence numbers, and fence monotonicity;
- stereo scheduler and safe transitions;
- config migration and validation;
- input edge handling once per game tick;
- shader/pass identity stability; and
- depth conversion for reversed/forward Z.

### 16.2 Synthetic graphics harness

Build a small D3D12/OpenXR harness independent of Darktide with:

- depth-staggered poles for disparity;
- oblique checkerboard for binocular rivalry;
- polished sphere for specular mismatch;
- reflective floor and edge-crossing object for screen-space effects;
- fine alpha-tested foliage for temporal history;
- strobe/rotor for resonance;
- near pole against distant wall for disocclusion;
- fast small object for flow failure;
- rapid 180-degree turn for off-screen intake; and
- dense small-text HUD for UI extraction.

Primary metrics:

- inter-ocular SSIM ratio >= 0.95 against full-stereo reference;
- disocclusion fraction < 3% on representative content;
- depth-pole disparity error < 5%;
- HUD-region SSIM > 0.99 and OCR within 2% of baseline;
- left/right capture counts within 3% over a long run; and
- no p99 synthesis budget regression above 10% without an accepted reason.

These scenes and thresholds come from the local AER validation specification ([AER guide, pp. 108-110](<./AER_Modes_and_Optical_Flow_Frame_Generation_v3.pdf>)).

### 16.3 Desktop Darktide bring-up

1. Load/unload without XR and verify exact game behavior.
2. Identify the camera and run the six-axis wobble on desktop.
3. Prove the camera gate across hub, mission, ADS, sprint, dodge, downed/grabbed, cutscene, death, and loading.
4. Capture a pass census at multiple resolutions and graphics presets.
5. Visualize scene depth and classify UI/weapon/shadow/transparent passes.
6. Run for two hours with hooks installed but camera/stereo disabled.
7. Confirm clean recovery after resize, alt-tab, display change, and device loss simulation.

### 16.4 Headset gates

Follow the local AER bring-up order without skipping stages:

1. mono game image in headset, no camera change;
2. mono 6DOF camera;
3. headset projection/FOV;
4. verified depth;
5. naive AER diagnostic;
6. rotation-only AFW, then translation;
7. stereo warp;
8. synchronized sequential only after safe snapshot/tick proof;
9. optional frame generation; and
10. state machine and two-hour hardening session.

See [AER guide, p. 77](<./AER_Modes_and_Optical_Flow_Frame_Generation_v3.pdf>).

### 16.5 Darktide scenario matrix

Test at minimum:

- Psykhanium with static targets, melee horde, ranged fire, explosions, and class abilities;
- low- and high-intensity missions with each base body scale, especially Ogryn;
- sprint, dodge, slide, vault, ladder/elevator where present, fall, ledge hang, revive, carry/interact;
- ADS, scoped weapons, plasma/charge weapons, flamers, throwable arcs, auspex/scanner;
- Psyker peril overlays and full-screen effects;
- smoke, fire, fog, transparencies, particles, decals, blood, dismemberment, and hordes;
- menus, chat, subtitles, mission terminal, inventory, crafting, end screen, reconnect;
- joining in progress, host/server hitch, packet loss, and disconnect/reconnect;
- cutscenes, scripted camera changes, death/spectator, and HMD removal; and
- DLSS/FSR/XeSS, dynamic resolution, ray tracing off/on, window modes, and supported runtimes.

### 16.6 Comfort study

Use short, blinded A/B sessions with a structured symptom scale. Include sensitive testers, lateral strafing, rapid target switching, sustained melee, sprint/dodge chains, forced-camera states, and mode transitions. Record time to first discomfort and stop immediately when symptoms appear.

---

## 17. Milestones and exit criteria

### Phase 0 - policy and feasibility (1-2 weeks)

Deliver:

- Fatshark/DMF outreach package describing local-only renderer/input behavior;
- build fingerprint tool;
- D3D12/OpenXR synthetic harness;
- desktop camera-source map and pass census; and
- go/no-go memo for protected-process work.

Exit when: legal/policy route is explicit, or the project is formally restricted to private research; camera and final Present can be observed without instability.

### Phase 1 - mono VR vertical slice (2-4 weeks)

Deliver:

- OpenXR lifecycle and D3D12 capture;
- mono head-locked theatre, then mono projection;
- 6DOF camera with recenter/world scale;
- gamepad input and emergency disable;
- basic overlay/logging; and
- loading/menu/cutscene theatre fallback.

Exit when: 60-minute headset session, correct pose/FOV, no game-thread XR wait, no crashes or camera loss across core states.

### Phase 2 - diagnostic stereo and AFW (3-6 weeks)

Deliver:

- per-eye frame ring and AER diagnostic;
- rotation-only then depth-assisted AFW;
- depth capture/visualizer;
- eye parity/skew counters and runtime smoothing tests; and
- synthetic comparison metrics.

Exit when: inter-ocular target met in representative scenes, no eye starvation, stable engine rate under runtime reprojection/smoothing, and no plain AER default.

### Phase 3 - UI and product shell (3-5 weeks)

Deliver:

- UI pass extraction or robust theatre fallback;
- HUD/menu/subtitle controls;
- comfort presets and camera-motion policy;
- first-run calibration;
- config schema/migration; and
- clean installer/uninstaller/update check.

Exit when: full mission is readable and operable without removing the headset.

### Phase 4 - controller aiming (3-6 weeks)

Deliver:

- tracked-controller action map;
- conventional aim mapping and two-hand stabilization;
- UI pointer mode;
- haptics; and
- balance/policy review.

Exit when: no duplicated inputs, no rate/reach advantage, full remapping/left-handed coverage, and parity with normal game input semantics.

### Phase 5 - synchronized sequential spike (time-boxed 2-4 weeks)

Deliver:

- render/snapshot boundary investigation;
- differential test for second view;
- CPU/GPU cost measurement; and
- written accept/reject decision.

Exit when: either same-tick stereo is proven safe and performant, or it is explicitly rejected with evidence. Do not let this spike block the AER + AFW product path.

### Phase 6 - optimization and compatibility (ongoing)

Deliver:

- optional stereo warp and flow generation;
- mode switching/degradation;
- runtime/GPU/driver matrix;
- per-build adapters and automated signature validation; and
- two-hour soak and release checklist.

Exit when: no unresolved P0/P1 defects, no mode oscillation, fallback is deterministic, and policy gate permits the intended distribution.

---

## 18. Risk register

| Risk | Likelihood | Impact | Mitigation / decision trigger |
| --- | --- | --- | --- |
| EAC or policy rejects native injection | High | Critical | Seek explicit confirmation; no bypass; private research or stop native path |
| Game update breaks signatures/passes | High | High | Build fingerprints, wildcard AOBs, pass census, safe mono unknown-build mode |
| CPU-bound hordes make stereo unaffordable | High | High | Measure early; AER + AFW; resolution/VR preset; avoid duplicated view-independent work |
| No safe same-tick second view | High | Medium | Time-box spike; ship AER + AFW baseline |
| Camera edit hits shadow/auxiliary view | Medium | High | Active-camera capture plus render-pass gate and continuous plausibility checks |
| Temporal upscaler history corrupts stereo | High | High | Per-mode validation; disable/replace; separate eye history if discoverable |
| UI cannot be cleanly extracted | Medium | Medium | Theatre mode and composited fallback; manual pass overrides |
| Depth unavailable/stale in some states | High | High | Per-frame capability gates; rotation-only AFW; immediate fallback |
| Motion smoothing halves engine or starves eye | Medium | High | Dedicated XR wait thread; no game-thread block; run-free capture and pose counters |
| Tick lock stalls network/audio/jobs | High | Critical | Never global-freeze; require render-scoped snapshot proof; reject M1 if not safe |
| Roomscale lean reveals through walls | Medium | High | Clamp, depth/collision fade, visual-only lean, conservative bounds |
| Controller mapping becomes aim advantage | Medium | High | Ordinary aim intent only; no auto-targeting/recoil/cadence changes; policy review |
| GPU resource-state bug causes TDR/device loss | Medium | Critical | Explicit state tracking, fence ownership, resize/device-loss teardown, D3D validation in lab |
| Comfort defect harms testers/users | Medium | Critical | Conservative defaults, fast fallback, stop rules, sensitive testing, no plain-AER default |

---

## 19. Proposed repository layout

```text
DarktideVR/
  CMakeLists.txt
  cmake/
  external/                 # pinned source dependencies, no game SDK/binaries
  src/
    core/                   # logging, config, build fingerprint, lifecycle
    xr/                     # OpenXR runtime, actions, spaces, timing
    gfx/d3d12/              # hooks, resources, barriers, fences, pass census
    stereo/                 # scheduler, AFW, reprojection, generation
    ui/                     # extraction and OpenXR layers
    input/                  # action maps and ordinary game input bridge
    adapters/darktide/      # signatures, camera/pass knowledge, state adapter
  shaders/
  dmf/DarktideVR/           # optional Lua companion
  configs/                  # schema and build profiles, no user machine state
  tests/
    unit/
    xr_harness/
    synthetic_scenes/
    fixtures/
  tools/
    fingerprint/
    pass_census/
    capture_compare/
    package/
  docs/
    design/
    compatibility/
    validation/
    handoffs/
```

Do not place the copied Darktide installation, generated shaders, build directories, crash dumps, captures, runtime manifests, user configs, or machine-specific state under version control.

---

## 20. Configuration surface

Keep the first release small and semantic:

```toml
[runtime]
preferred = "openxr"
refresh_rate = "runtime"

[stereo]
preferred_mode = "auto"
allow_sync_sequential = false
allow_depth_warp = true
allow_frame_generation = false
descend_bad_frames = 3
ascend_good_frames = 90
minimum_dwell_frames = 60

[world]
metres_per_game_unit = "auto"
scale = 1.0
lean_horizontal_m = 0.25
lean_vertical_m = 0.18

[camera]
shake = 0.20
recoil = 0.30
sprint_bob = 0.10
forced_roll = 0.0
cutscene_mode = "theatre"
incapacitated_mode = "vignette_theatre"

[locomotion]
direction = "body"
turn = "snap"
snap_degrees = 30
vignette = 0.45

[ui]
mode = "quad_layer"
distance_m = 2.0
width_m = 2.2
follow_lag_ms = 150
max_deviation_degrees = 15

[diagnostics]
overlay = false
pass_census = true
capture_images = false
```

Build-specific addresses, shader hashes, and pass overrides belong in separate signed/versioned profiles. Users should not need to edit offsets for normal operation.

---

## 21. Decision log and open research questions

### Decisions made

- Use OpenXR, not an OpenVR-only architecture.
- Use D3D12 as the initial graphics path.
- Keep the game authoritative and the VR layer presentation/input-only.
- Treat DMF as an optional semantic companion, not the stereo renderer.
- Make AER + AFW the likely baseline and synchronized sequential a gated optimization/quality mode.
- Keep plain AER diagnostic-only.
- Keep app-level frame generation off by default.
- Build the timing thread/ring-buffer architecture before stereo.
- Unknown game builds fail closed.
- No anti-cheat bypass or public protected-session testing without policy clearance.

### Questions to answer during Phase 0-2

1. What exact native function writes or binds the main ScriptCamera view/projection for build `b773907`?
2. Can the clean camera and active viewport be correlated with D3D12 constant-buffer uploads without false positives?
3. Is the final scene color available before UI, and can UI be isolated by render target/pass identity?
4. Which depth resource is stable across ray tracing, upscalers, dynamic resolution, and weapon/transparent passes?
5. Does Darktide use reversed-Z and an infinite far plane in every relevant mode?
6. Are temporal histories keyed per camera/view, or would alternating projection poison DLSS/FSR/TAA?
7. Is there a render-only replay/re-entry point or immutable render snapshot that can support synchronized sequential stereo?
8. Which view-independent passes can be shared between eye renders without altering the frame graph?
9. Can DMF export low-rate semantic state without adding a native loader or blocking the Lua/game thread?
10. What exact loader/injection route, if any, will Fatshark accept under EAC?
11. Can camera-only 6DOF plus external SBS/depth stereo provide a useful interim release if native injection is not approved?
12. What minimum PC/GPU and graphics preset sustain acceptable p99 timing in worst-case hordes?

---

## 22. Sources and research notes

### Local primary/reference material

- [AER Modes and Optical-Flow Frame Generation](<./AER_Modes_and_Optical_Flow_Frame_Generation_v3.pdf>) - architecture, three clocks, stereo taxonomy, AFW/warp/generation, capability state machine, validation, and failure catalog.
- [Making 6DOF Mods 3D - General Method](<./Making-6DOF-Mods-3D-A-General-Method-Rev4-AFR.pdf>) - stable AFR capture, compositor output, layering, diagnostics, and packaging.
- [6DOF Head-Tracking Master Reference](<./6DOF-HeadTracking-Master-Reference-Revs6.pdf>) - additive camera method, capture-gate-edit, hook families, camera math, version scanning, and proof workflow.
- [VR Motion Smoothing / AER Fix](<./VR-MotionSmoothing-AER-Fix-Guide.pdf>) - non-blocking XR wait, run-free capture, per-frame pose location, and counter relationships.
- [Native ABI + Godot guide](../../guides/vr/native-abi-godot-vr.md) - authority boundary, coordinate-space naming, fixed-rate separation, buffers/events, verification, and packaging lessons.
- [Crimson ABI-driven VR architecture](../../crimson/docs/rewrite/architecture/abi-driven-godot-vr-port.md) - local example of keeping simulation and presentation responsibilities explicit.

### External sources

- [Fatshark Darktide Modding Policy](https://forums.fatsharkgames.com/t/darktide-modding-policy/75407/1)
- [Darktide Mod Framework](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Framework)
- [Darktide Mod Loader](https://github.com/Darktide-Mod-Framework/Darktide-Mod-Loader)
- [Public Darktide source mirror - camera settings](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/settings/camera/camera_settings.lua)
- [Public Darktide source mirror - camera manager](https://github.com/Aussiemon/Darktide-Source-Code/blob/master/scripts/managers/camera/camera_manager.lua)
- [UEVR](https://github.com/praydog/UEVR)
- [REFramework](https://github.com/praydog/REFramework)
- [6DOF Head-Tracking Mods Hub](https://github.com/BerZerker96/6DOF-Head-Tracking-Mods-Hub)
- [Osiris VR Viewer](https://github.com/BerZerker96/Osiris-Vr-Viewer)
- [OpenXR 1.1 specification](https://registry.khronos.org/OpenXR/specs/1.1/html/xrspec.html)
- [OpenXR loader/API-layer design](https://github.com/KhronosGroup/OpenXR-SDK-Source/blob/main/specification/loader/api_layer.adoc)
- [Microsoft D3D12 resource barriers](https://learn.microsoft.com/en-us/windows/win32/direct3d12/using-resource-barriers-to-synchronize-resource-states-in-direct3d-12)
- [Fatshark performance deep dive](https://www.playdarktide.com/news/dev-blog-performance)
- [Fatshark DirectX debug-layer guidance](https://support.fatshark.se/hc/en-us/articles/25583934705309--PC-How-to-Enable-DirectX-Debug-Layers)
- [Fatshark crash and mod-update guidance](https://support.fatshark.se/hc/en-us/articles/7709661288733--PC-How-to-Resolve-Crashes-in-Darktide)

### Source caveats

The AER PDFs are technical project references rather than standards. Validate their recommendations against the OpenXR specification, D3D12 documentation, runtime behavior, and Darktide measurements. The public Darktide source mirror is invaluable for naming and control flow but is not an official SDK and may not match a particular shipping build. Community mod behavior is precedent, not permission.

---

## 23. Validation commands used for this brief

Research/inspection commands executed on the Windows PC:

```powershell
git status --short --branch
git worktree list
rg --files

(Get-Item '.\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe').VersionInfo |
  Select-Object FileVersion, ProductVersion, CompanyName, ProductName

Get-Content '.\Warhammer 40,000 DARKTIDE\bundle\application_settings\settings_common.ini'
Get-Content '.\Warhammer 40,000 DARKTIDE\bundle\application_settings\win32_settings.ini'

python -c "from pypdf import PdfReader; ..."
python -c "import pdfplumber; ... page.to_image(...).save(...)"

git clone --depth 1 --filter=blob:none --sparse `
  https://github.com/Aussiemon/Darktide-Source-Code.git `
  '.\tmp\research\Darktide-Source-Code'
git -C '.\tmp\research\Darktide-Source-Code' sparse-checkout set `
  scripts/managers scripts/settings/camera scripts/ui
rg -n 'Camera|camera|vertical_fov|first_person' `
  '.\tmp\research\Darktide-Source-Code\scripts'
```

The four local PDFs were text-extracted and representative architecture/bring-up pages were rendered to PNG and visually inspected. No Darktide executable was launched, injected into, modified, or tested under EAC. No GPU, headset, D3D12 validation-layer, OpenXR runtime, performance, or comfort validation has yet been performed; those are Phase 0-2 gates on the PC. No Mac-only validation applies to this Windows PCVR design.
