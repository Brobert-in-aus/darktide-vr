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
a visible child. Hover visuals, scrolling, back routing, nested view elements,
other custom-grid view classes, and final controller-in-headset acceptance
remain outstanding.

## Validation

Executed on the Windows/D3D12 development PC:

```powershell
& .\tools\stereo\build-particle-horizon-lock.ps1
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr_native_capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure -R 'native_capture_hooks|core_math|billboard'
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure
git diff --check
```

The shader build/interface smoke check passed, the native DLL compiled with
the existing warning-as-error policy, and both selected tests passed. Live XR
was stable; the bridge reported zero pair-pose mismatches. No validation is
Mac-only for this D3D12 checkpoint.

## Next actions

1. On the next worn check, pitch and roll at character select and confirm the
   target motes rotate only in yaw. Also check for any subtle material that
   unexpectedly shares the exact hash.
2. If accepted, repeat in the Psykhanium against smoke, muzzle flashes, fire
   and explosion materials; add exact hashes only when ownership is proven.
3. Extend the proven source-coordinate menu path to hover, scroll, back,
   nested view elements and remaining custom grids. Then verify the fixed
   LOCAL-space 2 m panel in-headset and run the synthetic controller path
   through viewport departure, over-reach, tracking loss and reacquisition.
4. Continue the deterministic Psykhanium entry path and first-person input/IK
   gates. The third-person hub retains stock animation.
