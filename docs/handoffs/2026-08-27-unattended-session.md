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

## Validation

Executed on the Windows/D3D12 development PC:

```powershell
& .\tools\stereo\build-particle-horizon-lock.ps1
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

The shader build/interface smoke check passed, the native DLL compiled with
the existing warning-as-error policy, and the final RelWithDebInfo suite passed
all 30 tests. Live XR
was stable; the bridge reported zero pair-pose mismatches. No validation is
Mac-only for this D3D12 checkpoint.

## Next actions

1. On the next worn check, pitch and roll at character select and confirm the
   target motes rotate only in yaw. Also check for any subtle material that
   unexpectedly shares the exact hash.
2. If accepted, repeat in the Psykhanium against smoke, muzzle flashes, fire
   and explosion materials; add exact hashes only when ownership is proven.
3. Extend the proven source-coordinate menu path to text input and remaining
   custom grids. Then verify the fixed
   LOCAL-space 2 m panel in-headset and run the synthetic controller path
   through viewport departure, over-reach, tracking loss and reacquisition.
4. Continue the deterministic Psykhanium entry path and first-person input/IK
   gates. The third-person hub retains stock animation.
