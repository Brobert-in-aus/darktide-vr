# SteamVR and Steam Frame readiness

Investigation, 17 September 2026. The project has only ever run against
Virtual Desktop's VDXR runtime on a Quest 3. A Steam Frame arrives within the
week; Virtual Desktop is not expected to support it at once, so the first
session will use **SteamVR as the OpenXR runtime**, with the headset streaming
over its own 6 GHz adapter. This note records what is already runtime-neutral,
what will break or degrade, and the order in which to fix it.

Nothing here has been measured: no SteamVR runtime, no Frame and no Windows
machine were available to this investigation. Every claim about the codebase is
cited to source; every claim about SteamVR or the Frame is cited to public
documentation and must be confirmed by the first live run.

## What the headset changes

- The PC side is ordinary SteamVR. Valve documents the Frame as maintaining
  "full compatibility with SteamVR and OpenXR"; the headset creates a
  point-to-point 6 GHz link that SteamVR on the PC joins through the bundled
  adapter. So the target is the SteamVR OpenXR runtime
  (`steamxr_win64.json`), not a new streaming runtime of its own.
- Panels are 2160x2160 per eye, refresh options from 72 Hz to 120 Hz with
  144 Hz marked experimental, about 110 degrees, pancake lenses. SteamVR's
  recommended eye extent will be the panel resolution plus its distortion
  oversampling and the per-application render-resolution setting, so it will
  be materially larger than the Quest 3 through VD.
- Controllers are Frame controllers. By Valve's documentation they are
  presented to applications as **emulated Oculus Touch** unless the
  application enables `XR_VALVE_frame_controller_interaction` and suggests
  bindings for `/interaction_profiles/valve/frame_controller_valve`.
  SteamVR's fallback order for an application with no Frame binding is:
  Frame binding, then an OpenXR generic-controller binding, then an Oculus
  Touch binding, remapped to the Frame layout.
- Foveated streaming is applied in the encoder from eye tracking. It needs
  nothing from the application.

## What already ports without change

The OpenXR viewer is written against the core specification, not against VDXR:

- One graphics binding, D3D12, enabled from the enumerated extension list
  (`src/xr/main.cpp:212`, `src/xr/main.cpp:227`). SteamVR exposes
  `XR_KHR_D3D12_enable`; the first run must confirm it in the probe output.
- `XR_EXT_frame_synthesis` and `XR_FB_space_warp` are probed and logged only
  (`src/xr/main.cpp:216`-`src/xr/main.cpp:225`). Neither is used for
  submission, so SteamVR's lack of them costs nothing. The mod's generated
  frames come from the game's own DLSS frame generation, not from the runtime.
- `LOCAL`, `VIEW` and, when enumerated, `STAGE` spaces
  (`src/xr/main.cpp:362`-`src/xr/main.cpp:389`). SteamVR provides all three;
  the standing calibration keeps its floor reference.
- Colour formats are chosen from the runtime's own enumeration, preferring
  8-bit sRGB (`src/xr/main.cpp:5273`-`src/xr/main.cpp:5282`). SteamVR's D3D12
  colour list contains those formats.
- Asymmetric per-eye frusta are already handled generally: the submitted views
  are recentred to a symmetric frustum with a per-eye orientation offset
  (`src/core/xr_math.cpp`, `recentered_symmetric_projection`;
  `src/xr/main.cpp:4128`-`src/xr/main.cpp:4167`). A runtime whose optical
  centres differ from VDXR's needs no new maths.
- The eye extent follows the runtime recommendation and is republished to the
  game, which replaces its bootstrap 2112x2304 with the live extent
  (`src/xr/main.cpp:1610`-`src/xr/main.cpp:1614`;
  `mods/.../darktidevr.lua:2739`-`2746`). Resolution adaptation is already
  dynamic; only its cost is new.
- The one Virtual Desktop-specific call in the viewer, reading LibOVR's last
  error after a swapchain failure, is guarded by `GetModuleHandleW` and is
  simply skipped under another runtime (`src/xr/main.cpp:5305`).
- The native producer, the Lua mod and the launcher contain no runtime-specific
  code paths; the only "SteamVR" reference in the mod is a log of the engine's
  absent VR namespace (`mods/.../darktidevr.lua:649`).

## What needs work, in priority order

### 1. Controller bindings — the one true blocker — DONE (18 September)

Valve's own documentation turned out to be richer than the summary below, and
corrected it twice: **the left controller has four face buttons**, spelled
`dpad_up/down/left/right`, and **the left hand does have a menu button** --
it is spelled `view/click`, while the right hand's is `menu/click`.

What shipped: `XR_VALVE_frame_controller_interaction` probed and enabled from
the enumerated list (the enabled-extension array is a built vector now), a full
20-binding set for `/interaction_profiles/valve/frame_controller_valve`, and a
21-binding set for `/interaction_profiles/valve/index_controller`. The Frame
face buttons are mapped by POSITION so Touch muscle memory carries over: bottom
is primary (Touch X/A), top is secondary (Touch Y/B) -- on the Frame's right
hand the top button is spelled `y`, where Touch puts `b`. `menu` is read from
the LEFT hand only (`core/gameplay_input.cpp`), so left `view/click` keeps
today's behaviour rather than moving the menu to the other hand.

Index has no menu button and `system/click` is runtime-reserved, so its menu is
the left trackpad's force press -- SteamVR's binding editor can move it.

Neither new profile can stop the session: both are suggested through a
non-fatal helper that logs `openxr.interaction_profile.<name>=suggested` or
`=rejected result=<n>`, because a path that differs from the documentation by a
character rejects the whole call, and a viewer that then refuses to start is
worse than one that comes up emulated and says so. `--no-simple-profile`
withholds the generic binding SteamVR prefers.

`tests/tooling/test-interaction-profiles.py` holds the contract from source,
since no runtime here can: a Frame or Index session must not reach the game
with fewer actions, on fewer hands, than a Touch session, and every component
path must be one the vendor documents.
`tools/lua/mutate-interaction-profiles.py` proves it catches all of that.

*The original analysis follows.*

#### The original analysis

The viewer suggests exactly two profiles: `oculus/touch_controller` with the
full gameplay set, and `khr/simple_controller` with select and menu only
(`src/xr/main.cpp:4941`-`src/xr/main.cpp:4970`). Against SteamVR that is a
risk rather than a certainty: SteamVR looks for a generic-controller binding
**before** a Touch binding, and this application offers one. If SteamVR
auto-rebinds from the simple profile, the session comes up with select and
menu and no trigger, squeeze, thumbstick or face buttons — the failure mode
already described for non-Touch controllers in the user guide, now reachable on
the Frame.

Work:

- Enable `XR_VALVE_frame_controller_interaction` when the runtime enumerates
  it, and suggest a full binding set for
  `/interaction_profiles/valve/frame_controller_valve`. The enabled-extension
  array at `src/xr/main.cpp:227` is a fixed single entry and must become a
  built vector; `xrSuggestInteractionProfileBindings` for a profile whose
  extension is not enabled fails with `XR_ERROR_PATH_UNSUPPORTED`, so the
  suggestion must be conditional on the same probe.
- Frame paths, from Valve's profile: `trigger/value`, `squeeze/value`,
  `thumbstick` and `thumbstick/click`, `a`/`b` (right), `dpad_*` (left),
  `menu/click` (right) and `view/click` (left), `system/click`, `output/haptic`,
  plus a shoulder/bumper click whose component name changed from `bumper` to
  `shoulder` in a SteamVR update — do not make the binding set depend on it
  until it is read from the live runtime.
  Note that the left hand has no X/Y: the current left-hand primary and
  secondary bindings (`x/click`, `y/click`) have no direct Frame equivalent,
  and the menu button lives on the right hand, not the left as bound today.
  Decide the mapping deliberately rather than inheriting Touch emulation.
- Add `/interaction_profiles/valve/index_controller` while the binding code is
  open: it is cheap, it is the rest of the SteamVR ecosystem, and the Nexus
  page already promises those bindings as future work
  (`docs/NEXUS-PAGE.md:73`).
- Keep the simple profile for genuinely generic runtimes, but add a switch to
  suppress it (`--no-simple-profile` or equivalent) so a degraded SteamVR
  session can be diagnosed in one run instead of a rebuild.
- Fallback that needs no code: SteamVR's per-application binding editor can
  rebind an OpenXR application by hand. Worth knowing on day one; not worth
  shipping as the answer.

Alignment follows from the same change. Emulated Touch supplies Touch grip and
aim poses, not Frame ones; Valve offers the native profile partly for
"Frame Controller specific offsets". Expect hand, weapon and holster alignment
to sit slightly off until the native profile is in use, and re-check the worn
calibration afterwards rather than tuning against the emulated poses.

### 2. Readiness and preflight tooling — DONE (18 September)

`Assert-XrReadiness` takes a runtime profile now, decided by
`Get-XrRuntimeProfile` from the active manifest's name:
`virtualdesktop-openxr.json` is VDXR, `steamxr_win64.json` is SteamVR, an empty
registration is `none` and anything else is `unsupported` and refused. VDXR
asks exactly what it did. SteamVR asks for the Steam manifest and a live
`vrserver`, and nothing else -- there is no Streamer, no ADB and no proximity
override on a Frame.

The preflight reads the runtime BEFORE the Quest section rather than after it,
which is what actually makes a Frame run possible: the transport resolution,
the proximity broadcast and the power dump are skipped, not failed, when
`$questExpected` is false. The summary carries
`openxr_runtime_profile` and `quest_expected` so a run says which path it took.

`validate-xr-readiness.ps1` covers both profiles and, in particular, that the
split does not leak in either direction -- a SteamVR session must not pass with
`vrserver` down because a Quest happens to be ready, and a VDXR session must
not pass with no Streamer because SteamVR happens to be running.
`test-preflight-device-inventory.ps1` gained five SteamVR cases asserting that
none of them rejects and none of them touches the Quest.
`tools/lua/mutate-xr-readiness.py` puts eight mutations through the gate.

`AGENTS.md`'s policy is updated, including that the proximity override is a
Quest procedure that does not apply to a Frame.

*The original analysis follows.*

#### The original analysis

`Assert-XrReadiness` hard-requires a running `VirtualDesktop.Streamer`, an
active runtime whose file is literally `virtualdesktop-openxr.json`, and an
ADB read of Quest power state (`tools/unattended/xr-readiness.ps1:58`-`72`,
called from `tools/unattended/invoke-unattended-preflight.ps1:94`-`155`). On a
Frame every one of those throws: there is no Streamer, the active runtime is
`steamxr_win64.json`, and there is no ADB.

Work: give the readiness gate a runtime profile — `VDXR` as today, `SteamVR`
requiring the Steam runtime manifest and a live `vrserver`/`vrmonitor`, with
the ADB power check replaced by the existing bounded XR smoke run as the
"headset is really there and rendering" proof. The fixtures in
`tests/tooling/validate-xr-readiness.ps1` and the device-inventory and
watcher tests need the same split. `AGENTS.md`'s "Live XR readiness" section
states the VD/VDXR/Quest requirement as policy and must be updated with it;
the Quest proximity-override procedure simply does not apply to the Frame, and
whatever keeps a Frame awake for unattended work has to be found separately.

### 3. Render cost at Frame resolution

The viewer renders and submits at exactly the runtime's recommendation, by
deliberate contract ("The application render and OpenXR swapchain extents
follow the runtime's exact recommendation", `src/xr/main.cpp:745`-`752`), and
the game's stereo render target is sized from it. `OutputLayoutRequest` has an
`eye_override` field (`src/core/output_layout.h:24`) but the production viewer
never calls `choose_output_layout`, so today the only lever is SteamVR's own
per-application render-resolution setting.

Two eyes of Darktide at Frame resolution, with DLSS super resolution and frame
generation on top, is a large step up from the tested Quest 3 setup even on a
4090. Before the first mission run, set SteamVR's render resolution well below
100% and raise it; and wire `eye_override` to a viewer option so the working
extent can be pinned from the launcher for repeatable comparisons instead of
drifting with a SteamVR setting. The existing evidence tooling compares only
like-for-like extents, so any performance comparison against the VD baseline
must state both extents or it means nothing.

### 4. Swapchain creation robustness

- `sampleCount` is taken from `recommendedSwapchainSampleCount`
  (`src/xr/main.cpp:5296`). Every delivery path writes the swapchain image with
  `CopyTextureRegion` (for example `src/xr/main.cpp:3057`), which is invalid
  against a multisampled destination. Both current runtimes are expected to
  recommend 1; request 1 explicitly rather than depending on that.
- SteamVR is reported to round swapchain extents up to a multiple of four. The
  copies and the submitted `imageRect` are built from the requested extent, so
  read back `GetDesc()` on the enumerated images and log any difference before
  trusting the first frame.
- The equal-extent assertion (`src/xr/main.cpp:292`-`src/xr/main.cpp:299`)
  should hold on SteamVR; if it throws, that is the message to look for.
- Up to eight composition layers are submitted (`src/xr/main.cpp:4484`) and
  `XrSystemGraphicsProperties::maxLayerCount` is never read. Read it once and
  log it; drop the optional quads rather than failing `xrEndFrame` if a runtime
  ever offers fewer.
- Quad and UI-projection layers assume premultiplied alpha
  (`src/xr/ui_projection_layer.cpp:20`-`21`). Compositors differ here. Look at
  HUD and pointer edges on the first worn run before concluding the layer
  geometry is wrong.

### 5. Head orientation from eye 0

The published head orientation is the left eye's orientation, with the position
averaged across both eyes (`src/xr/main.cpp:1505`-`src/xr/main.cpp:1519`). On
a headset with canted displays the left eye is rotated outward, and the
in-game camera would inherit that yaw; on the Quest 3 through VD the eyes are
parallel, so this has never shown. Log `openxr.runtime_fov.eye0/eye1` and
compare the two located view orientations on the first Frame session; if they
differ, take the head pose from the `VIEW` reference space, which is correct
for any optics and already created (`src/xr/main.cpp:372`).

### 6. Frame pacing, motion smoothing and diagnostics

Pair-driven pacing and the delivery cadence were tuned against VDXR, and the
unresolved "VDXR submission slowdown" has no meaning on SteamVR — it may be
absent, or replaced by something else. SteamVR's motion smoothing is a second
frame-synthesis stage on top of the mod's own generated frames; run the first
sessions with it off, then compare. The VDXR trace and application-statistics
tooling (`tools/stereo/summarize-vdxr-*.py`, `analyze-vdxr-wait-overlap.py`
and their tests) has no SteamVR counterpart: for SteamVR, the frame-timing
graph and `XR-FRAME-STAGE-TIMING` counters from our own viewer are the
starting evidence. Do not port the VDXR parsers speculatively.

### 7. User-facing text

`docs/USER-GUIDE.md:19`-`25`, `docs/NEXUS-PAGE.md:97`-`98` and
`tools/release/package-README.txt:13`-`15` all state VDXR on a Quest 3 as the
tested setup and warn that non-Touch controllers fall back to select and menu.
Those statements stay true until a Frame session passes; update them from
evidence afterwards, not in advance.

## Bring-up order for the first session

1. Set SteamVR as the active OpenXR runtime, start SteamVR with the Frame
   connected, and run the viewer's probe alone (no game). Record:
   `openxr.runtime_name`, the three extension lines, `openxr.stereo_views`,
   `openxr.recommended_size`, `openxr.swapchain_formats`,
   `openxr.floor_space`. This answers D3D12 support, extent and STAGE in one
   run and needs no mod deployment.
2. Run the bounded XR smoke with rendering required. A submitted layer proves
   session, swapchain and compositor before any game work.
3. Read `openxr.controller_profile` for both hands and the thumbstick and
   button counters in the same run. That single line says whether SteamVR
   chose Touch emulation or the generic profile, which decides whether item 1
   above is urgent or merely correct.
4. Only then deploy the mod and launch, and judge stereo delivery by the usual
   shared-stereo evidence summary rather than by "the headset showed
   something".
5. Expect to retune, not to be finished: alignment after the binding change,
   resolution against frame rate, and the cadence against SteamVR's own
   reprojection.

## Estimate

Items 1, 2 and 4 are a day of focused work each at most, and none of them needs
the headset to write — only to verify. Item 3 is a settings and measurement
exercise, item 5 is a one-line fix behind a live check, and item 6 is open
ended. The realistic reading is that a Frame session can be brought up in its
degraded emulated-Touch form on day one, and that a week of evenings turns that
into a supported second runtime.

## Sources

- Valve OpenXR Utilities (Steam Frame controller profile, Touch emulation):
  <https://github.com/ValveSoftware/Unity/blob/main/com.valvesoftware.openxr.utils/Documentation~/index.md>
- Steam Frame controllers and compatibility, Steamworks:
  <https://partner.steamgames.com/doc/steamhardware/steamframe/controllers>,
  <https://partner.steamgames.com/doc/steamframe>
- Steam Frame hardware summary: <https://en.wikipedia.org/wiki/Steam_Frame>,
  <https://vr-compare.com/headset/steamframe>
- SteamVR automatic rebinding: <https://www.uploadvr.com/steamvr-automatic-controller-rebinding-update/>
- SteamVR OpenXR D3D12 reports (formats, extent rounding, ignored usage bits):
  <https://steamcommunity.com/app/250820/discussions/3/4034725980849397816>
