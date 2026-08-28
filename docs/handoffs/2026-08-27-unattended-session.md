# Unattended development handoff — 2026-08-27

## Cylindrical particle billboard checkpoint

The visible character-select motes are now localized to the exact graphics
pipeline pair below. This supersedes yesterday's colour-lattice candidate and
the earlier reflected-`c_billboard` guesses:

- vertex shader `42e436fb1ef1b392`;
- pixel shader `6020f2548f29fd47`;
- triangle-list topology with a generated six-vertex quad; and
- the original vertex stage owns `c_per_object` at `b2`.

A geometry-stage scale probe enlarged only these particles by 10x and left the
world and emissive lights untouched. It was useful localization evidence, but
adding `b2` to a new geometry stage was rejected by the original root
signature's stage visibility. The PSO hook correctly fell back to the complete
original pipeline. Geometry-stage injection is therefore removed from the
runtime path; the two probe sources remain diagnostic references.

The exact captured vertex shader was translated through `dxil-spirv` and
SPIRV-Cross, then repaired to retain its original raw/structured buffer types,
resource registers, output semantics, register packing and ordering. The
particle quad originally uses camera right/up from `c_per_object[8..10]`.
`tools/stereo/particle-horizon-lock.vs.hlsl` replaces only that orientation
construction:

- project camera forward onto Darktide world XY;
- normalize it and derive a horizontal right vector;
- use world `+Z` as up;
- preserve the particle's original in-plane rotation, size, UVs, fog and
  material outputs; and
- fall back to the projected original right vector at a near-vertical camera
  singularity.

The replacement passed the native fail-closed interface validator and PSO
creation. A 3x diagnostic/magenta run produced coherent enlarged quads in both
eyes, proving that both triangles remained paired and that this exact pipeline
owns the target particles. A fresh-cache production-shaped run then used 1x
scale and the original pixel shader: the scene rendered normally in stereo,
without tint, enlargement, device loss, or XR pair-pose mismatches. The latest
Quest capture is
`artifacts/unattended/particle-vs-horizon-natural-20260827-080654/quest.png`.
The user must still perform the final worn pitch/roll judgement; a stationary
unworn screenshot cannot prove perceived horizon lock.

`tools/stereo/build-particle-horizon-lock.ps1` now compiles the tracked source
to the hash-named module-adjacent replacement and checks its essential shader
interface. The exact hash was added to the production substitution allowlist.
Lua telemetry now reports all 14 allowlisted hashes, including the new final
slot. `start-darktide-vr.ps1 -FreshPsoCache` also now handles a single existing
cache file under strict mode instead of treating the scalar as lacking a
`Count` property.

## Fullscreen-menu pointer checkpoint

The desktop mirror reproduced the menu-input failure as a coordinate-space
fault. The Windows cursor could be visibly over `Options` while every Darktide
hotspot reported `cursor_hover=false`; on a control run the game's native
window-coordinate path opened `Party Finder` from that same visible location.
The XR harness now maps both the right-controller panel ray and the foreground
Darktide desktop cursor into the menu render source's pixel space. A desktop
button-down temporarily takes ownership from an active controller ray for that
atomic sample, while ordinary controller aiming remains preferred otherwise.

The pointer, its source dimensions, both button states, a sequence and a QPC
timestamp are published through a new shared-memory transport and native DLL
export. Lua rejects stale samples, resolves source pixels against engine-authored
scenegraph rectangles, and uses Darktide's own
`hotspot.force_input_pressed` seam. It does not synthesize a guessed Windows
coordinate inside the game.

Live logs prove both currently implemented ownership paths:

- `SystemView` source `(433,1341)/2112x2304` activated
  `grid_content_pivot_widget_11` and opened `options_view`;
- `OptionsView` source `(330,289)/2112x2304` activated its first custom-grid
  category widget; after restoring the grid's source-space interaction gate,
  source `(359,379)/2112x2304` activated Audio and populated the full settings
  pane.

Click edges remain readable throughout one render frame and are consumed only
by the widget whose rectangle contains the pointer. This prevents a lower
stacked view from stealing an edge merely by reading the shared sample. The
base static-widget path, SystemView dynamic grid and OptionsView category and
settings grids are covered. OptionsView's own `grid_interaction` hotspot used to
force-disable all children because its native cursor hover was false; the hook
now asserts that interaction region only while the source-space pointer is over
a visible child. At this initial checkpoint, hover visuals, scrolling and Back
routing were outstanding; the follow-up below resolves those three paths.
Nested view elements, other custom-grid view classes, and final
controller-in-headset acceptance remain outstanding.

### Menu interaction follow-up

The apparent desktop-mirror click failure is confirmed as an XR coordinate
misalignment: the visible menu is a cropped/scaled source render, while
Darktide's normal hit test consumes desktop-window coordinates. Source-space
hover and activation now use the same engine-authored widget rectangles and
hotspots, and live tests opened SystemView -> Options -> Audio.

The shared menu mapping is version 3. Primary, Back and scroll are represented
by persistent monotonically increasing counters so an event cannot disappear
between the independently paced compositor and Darktide UI loops. Lua accepts
an initial nonzero counter, rejects stale samples and consumes each counter
once. Named test events are available only under `-EnableMenuTestControls`.

Back is routed through the top view's own callback. A live event returned from
Audio/Options to SystemView and a second event closed SystemView; the log
recorded `source_back view=options_view` followed by
`source_back view=system_view`.

The first scroll attempt exposed an engine ownership detail rather than a
transport fault. OptionsView draws the large `settings_grid_interaction`
overlay with a nil `grid` argument; its actual scrollable grid is
`self._settings_content_grid`. Explicitly resolving that overlay to its owner
made the live XR event move Audio down to Headshot/Backstab Sound and log:

```text
DARKTIDEVR_MENU_INPUT options_source_scroll widget=settings_grid_interaction steps=-1
```

A separate deployment fault was also identified. Lua loads
`mods/darktidevr_stereo_probe/bin/darktidevr_native_capture.dll`, which had
silently fallen behind the matching DLL in `binaries`. The correct deployed
hash made the v3 mapping immediately readable. The startup path now calls
`tools/stereo/sync-darktide-vr-dev.ps1` before opening the launcher, copying the
source Lua and Release native DLL to both native destinations and verifying all
three hashes. This prevents future protocol tests from being invalidated by a
stale loaded bridge.

The following clean hub run directly reproduced the user's desktop symptom
and then verified the fix. The desktop mirror remained on the world while the
Quest capture showed SystemView on the spatial panel. Clicking desktop client
coordinate `(210,376)` was published as a source-space activation and opened
the `Mod Options` row selected by that source pixel. This proves that a menu
does not need to be displayed in the desktop mirror for desktop debugging to
activate its XR-visible engine widget.

The capture overlay now draws a compact black-outlined cyan reticle at the
same normalized source coordinate used by the hit test. A named
`Local\DarktideVR-menu-test-primary` event was added alongside the existing
Back and scroll events so unattended checks can produce a deterministic click
without depending on a controller being awake or a desktop mouse-down lasting
long enough to cross a compositor sample.

The first SystemView open with sleeping controllers exposed a separate input
edge: a short-lived OpenXR Back transition immediately closed the view, while
the second open remained stable. Back now stays disarmed on menu entry until
the action has reported released continuously for 100 ms. Automated coverage
confirms that an entry transient is suppressed and that a genuine Back press
after the settled release is delivered. This needs one live sleeping-controller
verification, but it is independent of the validated source-space hit-test
path.

A second deterministic-close cause was found in Lua itself. The consumed event
sequences were initially nil, so a freshly attached mapping with Back sequence
zero compared unequal and looked like an unconsumed Back press. Initializing all
three consumed sequences to zero made the first SystemView remain open in a
clean live run. The harness also no longer increments Back from a second raw
button-edge detector; only the debounced `MenuInputInjector` event advances the
shared sequence. Together these changes remove both false-entry paths rather
than adding another timing delay.

Nested widget passes are now enumerated instead of treating every widget as a
single `content.hotspot`. Their engine-authored visibility functions, pass
sizes, offsets and alignment are used for source-space hit testing. Hidden
dropdown options fail closed, and option hotspots are considered only while
the dropdown owns exclusive focus. The base Screen Mode row was reached in a
live OptionsView run; its expanded option selection still needs a clean live
acceptance run. Dropdown opening is now routed through OptionsView's own
exclusive-focus coordinator, which is the semantic path used to make its
option passes visible. Geometry logging is retained on an expanded-dropdown
click so the next run can confirm the exact option rectangle without guessing.

The clean follow-up reached the complete dropdown path. `Screen Mode` opened
through `widget_setting_83:hotspot`, and a named shared-primary edge reached
`widget_setting_84:option_hotspot_1` at source `(1482,515)/2112x2304`. This
proves nested option routing independently of Darktide's mis-scaled desktop
cursor. XR option activation now defers exclusive-focus closure until the next
completed OptionsView update, matching cursor-mode release semantics.

The same run identified the authored Video FOV slider geometry instead of
guessing it: `track_hotspot` spans source x `1364..1914`, is 550 pixels wide,
and the widget advertises 0.025 normalized steps. The Lua path now captures a
slider on trigger-down, derives and step-snaps its normalized value from that
track, preserves the last XR value across transient inactive samples, and
releases only on explicit fresh button-up. The harness gained independent
`Local\DarktideVR-menu-test-primary-down` and `-primary-up` events, and its
test mode deliberately lets desktop hover provide source position without a
native click. The final live gate began and ended the Video FOV drag at
normalized `0.5000`, and the visible value remained 65 degrees after release.
This accepts the slider path. An earlier held-input run had exposed and fixed
both premature inactive-frame release and engine resynchronization overwriting
the last XR-authored value.

The user's evening acceptance pass confirmed that focusing the DMF category
filter through the XR source pointer leaves the engine's ordinary PC text path
intact: typing on the physical keyboard inserted text into the field. A
controller-only text-entry surface remains outstanding.

The same pass found that Back worked from the controller, while selection and
scroll had no useful visible response, and no controller model or selection
laser was rendered. Logs showed live trigger and stick sequences reaching the
shared transport. They also exposed a test-mode ownership bug: enabling named
menu controls made desktop hover replace a valid controller ray, so a physical
trigger could operate the stale desktop position. Controller rays now remain
authoritative whenever they intersect the panel; desktop hover is only a
fallback, while an actual desktop button can still take temporary ownership.
An unmistakable spatial controller ray/reticle is the next acceptance gate.
The first implementation uses compositor-native geometry rather than drawing
into the game: two crossed 8 mm cyan quads run from the right-hand aim pose to
the panel hit, so one face remains visible across controller roll, and a 3.5 cm
marker sits just in front of the hit point. Both sample a reserved opaque pixel
from the already-submitted menu swapchain, avoiding another swapchain or GPU
synchronization path. The captured source reticle was also enlarged. This is a
functional selection affordance; controller models remain a later asset and
pose-presentation task.

The first worn controller pass accepted the laser, Back, ordinary buttons,
scrolling, sliders and physical-keyboard entry. It exposed one remaining
ordering bug: after a dropdown opened, the ray could still hit a control drawn
behind its option overlay. OptionsView now treats its `exclusive_focus`
dropdown as modal for XR hit testing. While that focus exists, only the focused
widget's visible option passes can own the ray; underlying widgets are excluded
instead of relying on iteration order. Live selection of an expanded option is
the current acceptance gate.

Initial world-space anchoring and the reset path now retain only the headset's
yaw in the recenter anchor. Anchor position remains unchanged, while headset
pitch and roll remain in the first live relative pose instead of redefining
gravity. This means initializing or recentering while leaned or looking up/down
must keep the virtual horizon level. Unit coverage includes a tilted/rolled
pose, yaw preservation, a world-up anchor and exact pose reconstruction.

All subsequent authenticated test launches use `start-darktide-vr.ps1` before
the launcher Play action. Its runner waits for the first responsive Darktide
window and attaches XR at the splash screen rather than waiting for character
select. The deployment and guarded-executable scripts now import
`Microsoft.PowerShell.Utility` explicitly so this workflow also works from a
fresh hidden PowerShell process where module autoload was previously absent.

The exact character-select particle substitution caused no other visible
particle changes, but the target motes are too small for a reliable worn
billboard judgement. Until the user requests otherwise, live validation pairs
the cylindrical vertex replacement with an interface-matched opaque-magenta
replacement for exact PS `6020f2548f29fd47`. The tracked build script exposes
this as `-DiagnosticMagenta`; only the confirmed particle pair is affected.

## Validation

Executed on the Windows/D3D12 development PC:

```powershell
& .\tools\stereo\build-particle-horizon-lock.ps1 -DiagnosticMagenta
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr_native_capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure -R 'native_capture_hooks|core_math|billboard'
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure
& .\tools\stereo\sync-darktide-vr-dev.ps1
npx --yes luaparse --quiet --file .\mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config RelWithDebInfo
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C RelWithDebInfo --output-on-failure
git diff --check
```

The shader build/interface smoke checks passed, the native DLL compiled with
the existing warning-as-error policy, and the final Release suite passed all
30 tests. Live XR
was stable; the bridge reported zero pair-pose mismatches. No validation is
Mac-only for this D3D12 checkpoint.

## Next actions

The earlier compositor-panel action list was superseded by the end-of-day
engine-world restart below. Preserve the completed pointer and billboard work,
but do not resume cached-stereo menu transition tuning. The authoritative
execution order is in **Tomorrow's first checkpoints**.

## End-of-day spatial-menu restart

The desktop/compositor menu path was deliberately abandoned after repeated
live failures. Across its iterations, opening or closing a menu could freeze
the world, blur one eye, alternate one eye between mono and stereo, prolong a
mono recovery interval, expose windows in front of Darktide, and leave vendor
views visible only on the desktop. Those behaviours were properties of the
wrong presentation boundary, not isolated transition delays, so further timing
patches on that design are not planned.

The new experiment keeps the bridge in ordinary stereo presentation mode and
places menu content inside the active Stingray world. Lua now:

- redirects eligible fullscreen UI passes to `darktidevr_menu_ui`;
- creates a `World.create_world_gui` surface in the gameplay world;
- removes the SystemView one-eye blur renderer;
- keeps live stereo rendering while Escape mode is active; and
- excludes active-gameplay-world renderers from capture so the HUD/world-marker
  path is not accidentally redirected.

The log recorded creation of a 2112x1188 target and a 2.000x1.125 m surface at
2 m. The user's final worn result is the important acceptance evidence:

- Escape no longer stops XR; its surface is visible in the stereo game world.
- The surface is black, so geometry exists but the expected UI texture is not
  reaching or being sampled by it.
- The surface is horizontal rather than vertical, so its world-GUI transform
  basis is wrong.
- NPC menus are unchanged from the old failure mode: they remain desktop-only,
  non-interactive, and disrupt XR presentation.
- World markers normally track correctly. They stopped only after entering the
  first broad menu-capture mode; the active-world exclusion is intended to fix
  that specific regression and needs a menu-open confirmation.

The opaque dark backing rectangle is intentionally still present as a geometry
diagnostic. Do not mistake the black panel for proof that the menu target is
empty: target population, material/resource binding, and pass ordering remain
separate hypotheses to test. Remove the backing only after the menu texture is
visible.

One apparent failure to attach XR at the splash screen came from launching a
test without `start-darktide-vr.ps1`. The wrapper restored the established
splash-time XR attachment, so repeated failures from the known wrapper are
required before applying the Virtual Desktop restart procedure.

### Tomorrow's first checkpoints

1. Present the complete transparent Escape capture on the corrected vertical,
   level world surface and validate pointer coordinates against its crop.
2. Add on-demand readback for repeatable submenu, dropdown, toggle, and vendor
   diagnostics without restarting XR.
3. Verify marker tracking during Escape mode and reconnect the already-developed
   XR pointer, scrolling, dropdown, toggle, and Back paths.
4. Trace NPC shop creation from the requested view through renderer creation
   and every presentation-mode publication. Remove the remaining desktop-only
   or mono transition and place the shop UI in world space while its 3D scene
   remains live.
5. Retire diagnostic backing geometry and the unused shared-menu bridge code
   only after both menu classes pass in-headset.

After the menu gate, return to the exact particle billboard acceptance pass,
per-eye LOD consistency, synthetic controller tracking limits, and the
Psykhanium first-person controls/IK plan. Hub gameplay remains third person.

### Final validation and shutdown

The latest code state retains the earlier successful checks:

```powershell
cmake --build build\windows-vs2022 --config Release
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure
pnpm dlx luaparse mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
git diff --check
```

The Release suite passed 30/30, the final Lua revisions parsed successfully,
and deployment synchronization completed before the worn menu test. The live
XR harness and Darktide were both stopped at end of session. The working tree
is intentionally left uncommitted for review; the unrelated untracked image
`Codex Image 25 Aug 2026, 08_53_34.jpg` remains untouched.

## 2026-08-28 unattended continuation

Static engine-source inspection resolved both known Escape-plane defects at a
bounded boundary. Darktide maps 2D GUI coordinates to a world GUI's transform
X/Z axes, with transform Y as the plane normal. The panel now uses camera-right
for X, world-up for Z, and horizontal camera-forward for its normal. The
render-target mask also derives UVs from screen position unless callers supply
local UVs; the panel now uses `Gui2.bitmap_3d` with explicit 0..1 UVs. An
opaque magenta-top/cyan-left L is drawn into the same menu target as a temporary
registration proof. Its next worn result separates target population/sampling
from remaining widget redirection without another combined workaround.

The NPC mono/flicker path was localized in native capture. Mod-authored eye
finals have stable left/right debug names, but the fallback learner continued
admitting every same-sized render target even after those two finals were
known. `contracts_background_view` creates a separate full-resolution UI world
with the same resource transition pattern, making it a false eye candidate.
Capture now permits anonymous learning only until both explicitly named eye
finals have appeared; after that, the named pair is the exclusive capture set.
Resize/rebuild clears the lock and safely relearns it. A live NPC acceptance
test is pending Quest reconnection.

A production-independent billboard reference now exists in the standalone XR
harness. It authors two otherwise identical quads side by side: magenta uses a
spherical camera-right/up basis, cyan projects the view direction onto the
horizontal plane and uses invariant world up. `--synthetic-billboard-sweep`
applies the same repeatable neutral/pitch/roll/combined synthetic head sequence
to located and submitted poses, so the expected movement can be confirmed
without relying on subtle Darktide particles.

The first comparison misread register 9 as irrelevant merely because the stock
spherical path consumes registers 8 and 10. Reflection identifies registers
8..11 as the column-major `view` matrix: 8 is right, 9 is forward, and 10 is
up. The corrected cylindrical replacement therefore flattens forward register
9 onto the XY ground plane, derives its perpendicular right axis, and forces
Darktide world-Z up. This matches the independently authored cylindrical
reference; flattening register 8 retains headset-roll contamination. The exact
magenta pixel diagnostic remains enabled as requested.

Validation completed while the Quest remained absent from `adb devices`:

```powershell
pnpm dlx luaparse --quiet --file mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr_native_capture darktidevr-xr-harness
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure -R 'native_capture|synthetic_head_path|xr_harness'
.\tools\stereo\build-particle-horizon-lock.ps1 -DiagnosticMagenta
.\tools\stereo\sync-darktide-vr-dev.ps1 -ParticleHorizonLock -ParticleDiagnosticMagenta
git diff --check
```

The Lua parse, both Release targets, and all three focused tests passed. The
Quest was still unavailable over ADB; Virtual Desktop Streamer remained active
on the PC. Live gates are therefore queued rather than inferred: Escape target
L/orientation/menu pixels, NPC shop stereo stability, standalone spherical vs
cylindrical sweep, and worn magenta particle horizon behavior.

### 2026-08-28 live additive-menu transport result

Quest/Virtual Desktop connectivity returned and the standalone billboard sweep
completed two 960-frame OpenXR runs at the runtime-recommended 2112x2304 per
eye. The magenta spherical and cyan cylindrical references used the same
synthetic neutral, pitch, roll, and combined pose sequence for both rendering
and submission. This validates the authored cylindrical basis independently of
Darktide; the exact native magenta particle replacement still needs a worn
acceptance pass because the production particles are very small.

The dormant shared-menu bridge was then converted into an additive layer. Mode
4 now keeps the ordinary stereo projection submitted and adds the shared
2112x1188 menu quad; it never replaces either eye with a desktop or mono
capture. MurmurHash64A(seed 0) identifies the engine target
`darktidevr_menu_ui` as `0xaf0f1409769cf92b`. Native capture observes its
RENDER_TARGET-to-shader-resource completion, copies it into the shared menu
surface, and publishes the ready fence. The source is
`DXGI_FORMAT_R8G8B8A8_TYPELESS`, not UNORM as the dormant consumer expected.
After correcting that format and four Lua state-machine paths which forced
interactive menus back to mode 1, a clean live run recorded:

- exact named left/right eye attachment with no pose mismatches;
- `DARKTIDEVR_PRESENTATION mode=4` on Escape;
- one expected initial shared-handle wait while the target was created; and
- `openxr.shared_menu=attached 2112x1188` while stereo continued.

This is the first end-to-end proof that an independent interactive UI texture
can be transported as a world-sized XR layer without freezing, blurring, or
making the stereo world mono. The visible target still contains only the
magenta/cyan registration mark and its dark clear/background. Redirecting
SystemView's outer `_ui_default_renderer`, invalidating retained widgets,
manually replaying its base/content widgets, and finally replacing the exact
`_draw_widgets(..., ui_renderer, ...)` argument all failed to populate native
menu pixels. The last test is an explicit negative: this is not a stale field
or late renderer-selection defect. Next work should trace SystemView's actual
`to_screen` D3D12 draw/target boundary (or isolate its overlay from the
completed back buffer), while retaining the proven additive transport and
removing the temporary focused resource logs after that trace.

The next paired four-frame native trace corrected the initial interpretation
of that boundary. The apparent UI-shaped draws on `darktidevr_menu_ui` occur in
an exact 2:1 menu/baseline ratio and are the resource renderer's own
background/registration diagnostics being issued twice, not stock
`SystemView` geometry. No `ExecuteBundle` or `BeginRenderPass` calls occur; the
RTV-zero phase-1 deltas are ordinary depth-only world passes explicitly bound
by `OMSetRenderTargets(0, ..., DSV)`, not hidden UI.

The alpha-contract hypothesis was also tested and disproved. A one-shot GPU
readback of the completed 2112x1188 target reported non-zero alpha for every
pixel that contained RGB (`rgb_nonzero_alpha_zero=0`), and presenting the quad
opaque did not expose stock widgets. The broad `UIRenderer`/`SystemView` replay
path is therefore disabled. The next step is to identify the stock UI's actual
completed target or exact compositing boundary and duplicate only that native
layer into the proven additive menu transport.

### 2026-08-28 stock-menu capture and billboard follow-up

A paired menu/hub D3D12 trace isolated a stable stock pause/options signature:
VS `4066249119808695432` with PS `160970739098383160`. It appears in 97--99%
of menu frames at roughly 8.8 draws/frame and is absent from the paired hub
trace. Native capture now detects that PSO and copies the completed swapchain
crop into the additive shared-menu mailbox. A clean live run attached the
result as `2112x1188` `R8G8B8A8_UNORM`; readback found 2,508,930 non-zero RGB
pixels and no RGB pixel with zero alpha.

The first harness version skipped its producer-pair wait while an interactive
menu was active. It therefore submitted at compositor rate while repeatedly
reusing approximately 24 fresh game pairs/sec. Removing that menu exception
keeps every submitted world frame tied to a newly completed stereo pair, with
zero pose mismatches. The producer copy is additionally gated by the
authoritative presentation mode because the same UI shader can occur in normal
HUD frames. Live logging confirms capture stops immediately on menu close.
Darktide's fresh-pair rate still falls while its menu renderer is active and
does not immediately recover after close; because capture has stopped, this is
now tracked as a separate game/menu or frame-generation-state issue.

For particle validation, `build-particle-horizon-lock.ps1` now supports a
bounded diagnostic geometry scale. A 10x magenta run made the exact
`42e436fb1ef1b392` / `6020f2548f29fd47` family unmistakable in character select
and the hub. The shader now uses the same forward-derived, Z-up basis as the
validated cyan authored reference. Natural-scale worn acceptance remains the
final visual gate; the 10x diagnostic is intentionally deployed for the next
easy-to-observe check.

### 2026-08-28 synthetic menu-input acceptance

The additive stock-menu board and XR pointer now share one coordinate contract.
At the current UI scale, Lua publishes a 2112x1188 source/crop, the native
producer transports a 2112x1188 texture, and the harness maps its panel ray
through that same crop before publishing source pixels. Focused
`panel_pointer`, `menu_pointer_state_transport`, `presentation_state_transport`,
and `synthetic_controller_path` tests pass.

A clean live run exercised the six-phase synthetic controller trajectory while
the hub menu remained spatial: left sweep, right sweep, crossed sweep,
off-panel, beyond the 1.5 m reach boundary, and tracking loss/reacquisition.
The bounded acceptance run recorded 1,221 controller samples, 441 eligible
rays, 366 panel hits, and 672 dispatched pointer updates. The laser was also
visibly observed moving from the right to the left side of the board.

That run exposed a separate D3D12 state defect. The theatre swapchain was put
in `COPY_DEST` whenever a producer object merely existed, even on frames where
no eye pair was copied and the diagnostic fallback was cleared into the image.
The transition now selects `COPY_DEST` only for a shared or cached eye copy and
otherwise selects `RENDER_TARGET`. A repeated 25-second bounded run covered all
six phases (675 samples, 240 rays, 200 hits) and exited with `result=pass` and
zero debug-layer errors.

The apparent menu and post-menu performance collapse was also resolved with a
controlled stationary-head run. The obsolete focused D3D12 menu trace armed a
four-frame phase inside `SystemView.update`, then armed a no-menu baseline from
`SystemView.on_exit`. Because the view no longer updates after exit, phase 2
could never consume its frame budget; command tracing remained enabled for the
rest of the process. The trace and its marker logging are now opt-in and exit
always disarms the native phase. With natural-size magenta particles and a
stationary pose, the clean rerun held roughly 44--49 fresh pairs/sec before,
during, and immediately after the menu. The former 22--24 pair/sec state did
not recur.

### 2026-08-28 LOD call-site evidence

A bounded hook of `World.update_lod_levels(world, camera)` recorded 32 gameplay
calls. Every call used the stock `player1`/primary camera; none used the added
right-eye camera. That agrees with the optimized render boundary: primary
`ScriptWorld.render` performs shading and LOD preparation once, while the right
eye reuses it through a direct `Application.render_world` submission. The
bounded probe was removed after collection.

This rules out two independent eye-specific Lua-visible LOD evaluations as the
cause of reported per-eye object differences. The remaining evidence-driven
targets are native per-camera visibility/draw selection, a resource/streaming
transition between sequential eye submissions, and per-eye temporal/post
state. The next probe should classify the differing draw at that boundary
rather than changing global LOD settings speculatively.

The same investigation must cover per-eye light visibility. Headset inspection
found lighting effects that switch off at the left and right edges of each eye,
consistent with a culling/frustum-bounds problem. Classify geometry LOD and
light culling together at the native visibility boundary, and test eye-union or
overscanned bounds before changing global quality settings.

### 2026-08-28 synthetic native billboard A/B

The standalone magenta-spherical/cyan-cylindrical reference was followed by a
native, repeatable A/B in character select. The exact particle family was
temporarily enlarged to 10x and its per-particle spin was disabled only in the
diagnostic compile. The live OpenXR bridge then drove the established
neutral/pitch/roll/combined synthetic head path while the desktop eye mirror
was recorded.

With the corrected forward-derived world-Z basis, particle rectangles rotated
with the rolled world. With the otherwise identical shader switched back to
the stock camera-right/up basis, rectangles stayed horizontal to the display
while the world rolled beneath them. An automated magenta connected-component
analysis provided a directional numeric cross-check: isolated-component mean
axis span was 15.5 degrees for cylindrical versus 13.7 degrees for spherical;
perspective, overlap, and particle motion make the contact-sheet A/B the clearer
acceptance artifact. The analysis tool is
`tools/stereo/analyze-billboard-frames.py`.

After the A/B, the deployed build was restored to natural 1x geometry, zero
local particle spin, cylindrical basis, and the user-requested magenta pixel
diagnostic. Preserving the stock local spin rotates a quad out of the world-Z
cylindrical plane and can visually recreate the rejected spherical behaviour;
that build is now an explicit comparison option rather than the default. The
remaining gate is a worn natural-size judgement, not shader ownership or basis
causality.

The standalone reference subsequently gained deterministic D3D12 readback at
four exact sweep phases.  The synthetic common pose is now independent of the
physical headset's unattended resting orientation while retaining the actual
runtime IPD.  Full-size central controls make the distinction explicit in the
captured eye: magenta stays display-aligned under roll (spherical), whereas cyan
tracks the rolled world horizon (cylindrical).  The 1,300-frame OpenXR run
submitted every frame at approximately 118 Hz and wrote
`%TEMP%\darktidevr-billboard-{neutral,pitch,roll,combined}.ppm`.  This is the
production-independent acceptance oracle for future native shader work.

### 2026-08-28 Psykhanium presentation clamp

The guarded one-shot Psykhanium workflow now has a clean unattended acceptance
run through the game's semantic training-view option. It selected Shooting
Range option 4, verified `game_mode=shooting_range` and
`mission=tg_shooting_range`, then armed the synthetic body/weapon presentation
only inside that private mission.

The previous 0.75 m weapon reach guard rejected an entire presentation write
when the synthetic grip crossed the boundary. That made the first-person
weapon snap back to its stock animated pose for the over-reach frames. The
guard now clamps only the rendered first-person rig to the continuous 0.75 m
boundary; it does not modify gameplay aim, attack origin, or reach. A live run
covered more than 1,600 consecutive writes and repeated requested distances
from roughly 0.2 m to 1.11 m. Every over-reach sample logged
`displacement_m=0.7500 clamped=true`; attachment error remained 0 and maximum
post-write hand error remained at or below 0.000001 m. No `over_reach`
rejection, script error, or device failure occurred. The body and weapon test
flags were disabled after collection.

Validation/artifact:

```powershell
pnpm dlx luaparse --quiet --file mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
git diff --check
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release -ParticleHorizonLock -ParticleDiagnosticMagenta
.\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 1200 -WaitForGameSeconds 1200 -EnableMenuInput -SyntheticControllerPath -SyntheticBodyPath
```

The desktop diagnostic recording is
`build/diagnostics/psykhanium-weapon-clamped-synthetic-20260828.mp4`; the game
log is the authoritative continuity/error measurement because Windows capture
of the hardware-rendered mirror can repeat a stale frame.

### 2026-08-28 production-shaped controller input delivery

The private-range gameplay adapter completed a clean synthetic action cycle
after a full producer/consumer restart. Lua now reports the exact ephemeral
action names delivered to Darktide as well as names missing from the active
input table. Repeated cycles delivered all currently mapped input families
with `missing=none`: primary and secondary attack press/release, weapon extra,
grenade ability, interact/reload, quick wield, jump/dodge, crouch, and sprint.
The mirror visibly showed the equipped sword reacting to the cycle. Smart tag
and menu remain intentionally routed outside `HumanInputHandler` and were not
claimed by this acceptance.

The clean XR epoch recovered to approximately 48--60 fresh stereo pairs/sec
with zero pose mismatches. Restarting only the XR consumer against an existing
game process was explicitly rejected as a test setup: it retained an old
shared-eye epoch, produced zero fresh pairs and one pose mismatch, while the
desktop mirror continued to look normal. Test flags were disabled after the
bounded run.

Quest `adb shell screenrecord` produced black compositor frames even during
the clean fresh-pair run with the device awake and proximity override active.
It is not a valid unattended visual oracle for the OpenXR projection on this
runtime; use in-headset judgement or a Quest recording initiated by the shell
UI for the pending world-menu appearance gate.

### 2026-08-28 native analog locomotion

The OpenXR gameplay frame now carries the left thumbstick as two analog axes.
The native mapper applies a 0.20 radial deadzone and rescales the remaining
range, and Lua writes the result into Darktide's existing `move_right`,
`move_left`, `move_forward`, and `move_backward` fixed-update caches. It does
not translate the camera or unit directly, so Darktide remains authoritative
for acceleration, deceleration, collision, slopes, and moving platforms.

A clean producer/consumer restart entered the private Shooting Range through
semantic option 4 and reported `DARKTIDEVR_PSYKHANIUM result=pass`. The
synthetic controller loop delivered all four cardinal stick phases at full
scale. Read-only downstream telemetry simultaneously showed the corresponding
stock cache values and metre-scale player-unit motion: for example right input
moved X from approximately 0.10 to 2.06, backward input moved Y from 2.79 to
-0.46, and the opposite phases moved those coordinates back across the range.
All production-shaped button actions continued to report `missing=none`.
The test flag was disabled after collection.

Validation:

```powershell
pnpm dlx luaparse --quiet --file mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture darktidevr-xr-harness darktidevr-gameplay-input-tests darktidevr-synthetic-controller-tests
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure -R "gameplay_input|synthetic_controller_path|native_capture"
git diff --check
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release -ParticleHorizonLock -ParticleDiagnosticMagenta
.\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 1200 -WaitForGameSeconds 1200 -EnableMenuInput -SyntheticControllerPath -SyntheticBodyPath -SyntheticGameplayInput
```

### 2026-08-28 collision-aware room-scale body follow

Head translation now has an explicit split between a bounded 0.25 m camera
lean and cumulative horizontal displacement assigned to the character body.
The native shared-head mapping exports that cumulative body-follow offset to
Lua. Its synthetic room-scale path covers X, Z, and combined 0.65 m
excursions, deliberately crossing the camera envelope. A core invariant test
proves `camera lean + body offset == physical pose` while the camera remains
bounded. An early diagnostic accidentally regenerated the synthetic pose from
the mutable sliding anchor and inflated the offset into tens of metres; the
harness now keeps an immutable synthetic origin and the strengthened test
guards this failure mode.

Inspection of the current Darktide locomotion source established the exact
movement boundary. `_update_script_driven_movement` reads
`steering_component.velocity_wanted`, applies push/minion constraints and
drag, then calls `Mover.move`. It does not read `target_translation`; the
first enabled probe confirmed that writing that field retained a value but did
not move the player. That dead path was removed.

The replacement adapter converts each new physical body delta to a one-tick
velocity contribution, adds it to the existing wanted velocity immediately
before the stock locomotion method, and restores the original steering value
immediately afterward. Thus physical motion is absolute per tick while
thumbstick acceleration/deceleration remains engine-owned. A clean private
Shooting Range run showed non-zero injected velocities and corresponding
player-position deltas with `target_translation` staying zero. A second run
combined the room-scale path with all four synthetic stick phases: logs showed
the ordinary stick velocity plus the physical contribution in the same mover
tick, then the correct stock velocity on frames without a physical delta. No
script errors or retained steering state occurred.

The guarded Psykhanium one-shot can now re-arm from `blocked` or `complete`,
and its startup wait is 1,200 seconds. This prevents Steam/launcher/login time
from consuming the old five-minute deadline before the hub is ready; the
later semantic UI stages keep their narrow deadlines.

Validation:

```powershell
pnpm dlx luaparse --quiet --file mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
cmake --build build\windows-vs2022 --config Release --target darktidevr-core-math-tests darktidevr-synthetic-head-tests darktidevr-xr-harness
.\build\windows-vs2022\tests\core_math\Release\darktidevr-core-math-tests.exe
.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-head-tests.exe
git diff --check
.\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 1200 -WaitForGameSeconds 1200 -EnableMenuInput -SyntheticRoomscalePath
.\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 600 -EnableMenuInput -SyntheticRoomscalePath -SyntheticControllerPath -SyntheticGameplayInput
```

### 2026-08-28 transparent stock-menu compositor

The earlier menu transport failure now has a concrete cause: the completed
swapchain image is opaque and already contains the mono/blurred world. Copying
it into an OpenXR quad cannot preserve the live stereo world, regardless of
transition timing. That path is disabled rather than patched further.

A focused D3D12 trace identified the stock Escape menu as a stable 28-draw,
seven-shader-pair batch targeting a 2112x2304 colour surface with blending on
and depth off. The native hook now redirects only those measured draws into a
shared transparent render target and immediately restores the game's original
RTV. The batch spans several command lists, so the surface is cleared once per
game frame, accumulated across every matching list, and published once from
the direct queue at Present. Publishing per command list was rejected by a
live diagnostic because it exposed only whichever fragment completed first.

The UI source is 2112x2304 while the current 16:9 panel crop is 2112x1188,
centred at source y=558. OpenXR opens the full physical resource, copies that
crop, and uses the identical transform for pointer input. A clean lobby run
produced a complete capture containing all menu labels, icons, button
backgrounds, arrows, and footer decoration. The stereo eye stream remained
fresh while the menu was active and resumed without a capture transition on
close. The diagnostic artifact is `%TEMP%\darktidevr-shared-menu.ppm` (or the
converted PNG); headset appearance and interaction remain the next user gate.

Validation:

```powershell
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture darktidevr-xr-harness
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 1200 -GameStartTimeoutSeconds 1200 -EnableMenuInput
```

### 2026-08-28 deterministic billboard reference and native zero-spin build

The XR harness now renders two authored controls side by side in front of its
diagnostic scene: a magenta spherical billboard and a cyan cylindrical
billboard. A deterministic neutral/pitch/roll/combined synthetic-head sweep
was submitted for 1,300/1,300 frames at approximately 118 Hz, with GPU
readbacks at each phase. Under roll, the spherical control remains
display-upright while the cylindrical control follows the world horizon. This
validates the cylindrical world-Z basis independently of Darktide's particle
data and renderer hooks.

Tracing that basis into the native replacement exposed the remaining native
difference: the stock per-particle local spin was applied after constructing
the cylindrical basis, rotating the completed quad back out of the world-up
plane. The production candidate now zeroes that local spin by default;
`-PreserveParticleSpin` remains available as an explicit A/B comparison. The
natural-scale magenta build is deployed, but the user's worn-headset
confirmation is still outstanding and must not be inferred from the harness.

### 2026-08-28 menu capture and bridge restart validation

A direct GPU readback of the accumulated stock-menu surface now contains the
complete Escape menu rather than a black or partial command-list fragment.
The seven measured shader pairs produced every menu entry and decoration in a
single 16:9 crop. Opening and closing `system_view` through the guarded flag
kept fresh stereo projection live, and the close completed in one frame with
no cached/mono transition. Synthetic semantic scroll events also reached Lua.
Vendor views remain a separate shader-family investigation; the Escape-menu
whitelist is not being generalized without a focused vendor trace.

Restarting only the XR bridge initially reproduced a separate failure. The
new pose writer reset correctly and Lua discarded stale capture tags, but the
shared D3D12 ready and consumed fences both reported `UINT64_MAX`. An abrupt
consumer-device exit permanently poisons that shared fence generation. The
producer now detects the sentinel and recreates its producer-owned eye
mailbox; the consumer rejects poisoned attachments and retries. Live
validation then terminated the bridge while Darktide remained at character
select and attached a new bridge three seconds later. The new generation
started at ready value 1 and immediately sustained approximately 64--66 fresh
stereo pairs per second without restarting Darktide.

Validation:

```powershell
pnpm dlx luaparse --quiet --file mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
cmake --build build\windows-vs2022 --config Release
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure
darktidevr-xr-harness.exe --frames 1300 --debug-layer --require-openxr --require-rendering --xr-frames 1300 --synthetic-billboard-sweep
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 3600 -EnableMenuInput -EnableMenuTestControls -SyntheticControllerPath
```

### 2026-08-28 final native cylindrical-billboard acceptance

The character-select particle fix is now accepted in-headset. The user watched
the enlarged magenta particles under the deterministic synthetic headset sweep
and confirmed that they cylindrically billboard. The corrected quads follow
the world horizon instead of remaining display-upright under headset roll.

The last instrumentation pass also resolved the native submission boundary.
Darktide submits the exact particle PSO through `ExecuteIndirect`; the correct
`ID3D12GraphicsCommandList::ExecuteIndirect` vtable slot is 59 (slot 58 is
`EndEvent`). Resolving the reflected vertex `b2` binding there yielded
2,048/2,048 clean 512-byte CBVs. Correlating each capture with the published XR
quaternion proved that `c_per_object` registers 8--10 carry the synthetic
pitch/roll sweep. No speculative pose channel is needed: the replacement
derives horizontal facing from native camera forward and fixes up to Darktide
world `+Z`. Stock per-particle spin remains disabled because it rotates the
quad out of that cylindrical plane.

The diagnostic was retired after acceptance. The deployed vertex shader is
natural 1x scale, cylindrical, and zero-spin (SHA-256
`D15F32E5E6EDB1F10AFBB09CDC975AB045FA5F44FA805C2925848D5E7C58E475`).
The magenta pixel replacement was moved aside as
`ps-6020f2548f29fd47.dxil.diagnostic-disabled`, restoring the game's original
particle colour. The pose-correlated capture remains at
`%TEMP%\darktidevr-billboard-target-cbv.tsv` for this workstation session.

Validation performed:

```powershell
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release -ParticleHorizonLock -ParticleDiagnosticMagenta
.\tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 300 -SyntheticHeadSweep
.\tools\stereo\build-particle-horizon-lock.ps1
.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release -ParticleHorizonLock
```

Next renderer/UI work resumes at the engine-world menu checkpoint. The Escape
menu is present in the replacement path but is black and oriented horizontally
instead of vertically. NPC/vendor views still use the old desktop-only path,
freeze or destabilize stereo, and do not accept pointer clicks. Keep those as
separate presentation families; do not reintroduce completed-swapchain capture
or its mono/blur transition sequence.

### 2026-08-28 first worn Psykhanium controller check

The semantic early-entry route passed with
`game_mode=shooting_range mission=tg_shooting_range`. A prior attempt from an
already populated hub reproduced the known base-game remote-husk
`parent_unit_id` teardown race; arming the request before hub population
avoided it.

Controller poses were healthy (`left_aim_flags=15`, `right_aim_flags=15`, fresh
ages), but no gameplay controls initially worked because the range-only aim
writer and general gameplay adapter retained their test-default disabled
flags. Both were enabled live for the controller mapping pass; the log then
reported `DARKTIDEVR_INPUT gameplay_adapter enabled=true` and
`DARKTIDEVR_AIM authoring=enabled`.

Worn inspection also confirmed that the stock first-person arms/weapon cannot
be the VR presentation. The next embodiment gate must hide the whole 1P visual
rig from both eyes, expose the local third-person body without its head, and
avoid duplicate 1P/3P weapons while preserving the hidden 1P unit as the
validated gameplay and animation driver.

The splash warning `Attempting to rehook active hook [draw]` was traced to two
registrations for `SystemView.draw`: one via the required class table and one
obsolete string-name diagnostic hook. DMF rejected the second registration,
so deleting that inactive diagnostic block removes the warning without
changing the live menu path. This Lua change requires the next game restart to
validate.

The worn controller pass found that buttons and right-controller aiming work,
but movement does not. Before the adapter was enabled, WASD worked. With it
enabled, neither WASD nor the left thumbstick moved the character. Logs provide
the direct cause at the Lua seam: every locomotion sample was
`move=0.000,0.000`, while `fixed_update` unconditionally replaced the four
existing movement cache values with zero. The adapter therefore owns and
erases movement even when it has no usable VR axis. Both gameplay and aim test
flags were restored to `disabled` at shutdown. The next fix must first trace
the physical left-stick value through OpenXR/shared state, then combine its
dead-zoned value with existing keyboard/gamepad cache values instead of
overwriting them.

Add two visual gates to the same range pass. First, the headless third-person
body must receive controller-driven arm IK and weapon aiming after the stock
first-person visuals are hidden. Second, enemies show distance-dependent
shadows in only one eye. Turning the head until the nearer physical eye swaps
does not swap the affected rendered eye, falsifying a purely eye-distance LOD
explanation; inspect submission identity, shadow-caster/cascade culling and
per-eye retained shadow state.

End-of-day validation:

```powershell
pnpm dlx luaparse --quiet --file mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure
git diff --check
```

The Release build passed and all 30 CTest tests passed.
