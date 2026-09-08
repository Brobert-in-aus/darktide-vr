# Shared marker-plane geometry candidate

8 September 2026. This is an offline geometry foundation for the reported pickup
popup sizing defect. It is **not hooked into the game, deployed, or visually
accepted**. The live SoloPlay/accepted preview session is unchanged.

`darktidevr_marker_plane.lua` constructs one plane at a marker's finite world
anchor, facing the shared head center. Its coordinate scale comes from one
reference projection's central pixel slope and the head-to-anchor distance.
Stock widget coordinates retain their hover, distance, animation and layout
changes. Marker, popup and tag primitives must all use this same geometry.

The module maps arbitrary primitive points into world space and derives each
eye's full projective transform, retaining the homogeneous denominator.
Changing just a text origin or a bitmap's axis-aligned size is insufficient.
The geometry can represent glyphs, UV/rotated textures, rectangles, vector icons
and custom-logic vertices. That does not establish engine draw API support.

The intended invariant is one physical surface with stable size from the shared
head center. At finite eye spacing, the eyes can legitimately see slightly
different angular sizes because their distances to an off-center surface differ.
Forcing equal pixel or angular extents would erase some physical geometry.
Eye optical-axis rotations must not introduce additional geometry changes.

## Validation

The pinned LuaJIT fixture exercises 288 eye/projection configurations and 2,304
points, using independent inverse-ray/plane intersections. It covers 0.5, 1, 3
and 30 metre anchors, horizontal/vertical offsets, zero/64/75 mm eye spacing,
pitched and rotated optical axes, rigid head transforms and pole fallback.
It verifies stable shared-center angular dimensions, finite-depth disparity,
both plane axes, nonfinite/basis rejection and near-plane rejection.

Commands, Windows x64:

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-marker-plane.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_marker_plane.lua
tools/stereo/test-darktide-lua-source.ps1
cmake --preset windows-vs2022
ctest --test-dir build/windows-vs2022 -C Release -R '^(marker_plane|marker_gui|marker_metrics|projection_math)$' --output-on-failure
```

Results: geometry fixture passes; all 51 source Lua chunks compile; four focused
tests pass in 0.14 seconds. The first configure attempt mistakenly used the build
preset `windows-vs2022-release`; the corrected command above registered and ran
the new test. No headset experiment was used.

## Drawing-path investigation

Stock `UIHud` creates its renderer in `level_world`. Stock `UIRenderer` mixes
`Gui2.bitmap`, `Gui2.slug_text` and `Gui2.rect` with `Gui.slug_icon` and transformed
`_3d` calls. Material flags, render passes and retained identifiers must remain
coherent. Swapping only texture calls would omit text, icons and damage numbers.

The older [official engine GUI reference](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Gui.html)
describes world-GUI drawing planes and `Gui.move(gui, pose)`. A per-marker world
GUI could apply one transform around an entire widget draw. However, world GUIs
participate in scene occlusion; screen GUIs are overlays. These documents do not
establish Darktide's newer `Gui2` support, scaled-pose behavior, material
compatibility or correct stereo submission lifetime. Downloaded stock source
uses identity world GUIs for debug/zone geometry and provides no `Gui.move`
example. The existing HUD-panel world bitmap of a render target does not prove
that all direct widget primitives work unchanged.

There is also concrete prior evidence against a blind GUI swap: the 5 September
HUD-panel capture `hud-facing-20260905/left.png` showed the fixed textured symbol
only after reversing the plane basis. Colored rectangles had remained visible
on the opposite face. The accepted HUD panel reverses U while presenting its
render-target texture to preserve text reading direction. That workaround cannot
simply be applied to direct text glyphs and vector icons as one generic GUI pose.
See the [5 September handoff](handoffs/2026-09-05-development-session.md).

Before integration: validate the complete draw API path and transform scale,
preserve layers and marker-specific occlusion policy, bound/reuse GUI resources,
and keep the same pose/geometry through both eye submissions. Preserve shared
clamp/fade behavior and retained/immediate lifecycle. Actual popup primitive
measurements and the user's worn edge checks remain open in the
[sizing audit](STEREO-MARKER-SIZING.md).
