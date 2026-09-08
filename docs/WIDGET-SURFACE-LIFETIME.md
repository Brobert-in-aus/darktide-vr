# Complete-widget surface lifetime

9 September: an offline engine resource backend now exists in
`darktidevr_widget_capture.lua`. It creates an owned UI world/overlay viewport,
two distinct RGBA8 targets and a stock viewport renderer. Handles are allocated
individually and retired on partial construction failure. Extents are bounded
to 4096 per axis and four million pixels per target. The backend is not loaded
by the mod and no widget is redirected yet.

`queue` clears the capture target and calls the supplied draw with its renderer.
The backend's `pass` helper opens/closes that independent renderer pass using an
owned scenegraph and a private top-level render-settings copy. It restores the
renderer fields and original scenegraph queue after begin/draw/end failures,
rejects nested capture passes, and preserves both errors if drawing and cleanup
fail. It does not clone nested settings or translate the source scenegraph; the
integration must supply an owned capture scenegraph and avoid shared nested
mutations. `observe_render(world)` must
run after successful rendering of the owned world; it returns a revision once,
for forwarding to the lifetime controller. `copy` rejects unsubmitted content.
Draw/copy failures retire the backend. Destruction removes the viewport before
targets, continues cleanup after errors, and cannot double-release on retry.

The engine calls follow the checked stock UI renderer and accepted HUD resource
path. Offline doubles verify ownership and submission sequencing, not actual
engine rendering. Complete bounds, retained widget/material migration, display
material/layer policy and live hook integration remain required. The historical
8 September description below predates this resource backend.

`darktidevr_widget_scenegraph.lua` now supplies a bounded draw-only snapshot for
stock UIWidget's `get_size` and `world_position` consumers. It resolves source
root/fit/aspect sizing at the source scale, owns its size/position arrays and
translates every node by one logical offset without changing depth. A capture
viewport therefore cannot re-resolve root sizes. It carries no engine cache or
child pointers and must never enter scenegraph update/cache APIs. The stock
draw getters pass 28 cached-source configurations across seven sizing modes and
four scales. This isolates geometry; it does not measure complete raster bounds,
copy retained widget state, or admit arbitrary custom logic into capture.

`darktidevr_widget_capture_state.lua` isolates GUI-owned pass caches for the
immediate texture, UV texture, rotated texture, text and rectangle paths. It
initializes capture-specific data through the stock pass initializer, reuses it
while the pass remains active, and restores source data even when drawing fails.
Removed/retyped passes release their cache through the capture renderer. Final
cleanup must precede capture renderer destruction. Unsupported/custom logic,
retained draws/IDs, foreign material handles and duplicate pass records are
rejected before redirection; no partial widget is silently accepted. This initial
admission policy is not coverage of all 20 marker families.

Offline tests include actual cached stock texture/UV/rotated material creation,
value replacement and destruction, verifying that source material handles never
reach capture submission or cleanup. Native GUI rendering, resource-fence behavior
and whole-widget raster bounds still require live validation.

8 September offline checkpoint. The pickup sizing investigation now has a
tested capture/display lifetime controller in `darktidevr_widget_surface.lua`.
It is not loaded by the mod, has no engine backend yet, and changes no installed
popup rendering. It completes the current bounded lifetime work; the visual
fix remains open in [the marker audit](STEREO-MARKER-SIZING.md).

## Behavior and backend contract

One controller owns one backend with separate capture and display resources.
The backend's `queue(draw, metadata, revision)` clears and authors the complete
widget once. It must unwind renderer/scenegraph mutations before propagating a
draw error. After its owned capture world renders successfully, the integration
calls `submitted(revision)`. Only a matching revision makes a later copy eligible.
Queueing is not submission, and submission here is not a claim that a GPU fence
has completed; the backend must use an engine-ordered resource copy, as the
accepted HUD path does.

On the next frame, `copy()` copies the previous submitted capture into the
distinct display resource before the next capture is queued. Successful backend
operations may return nil; failures must throw. The first frame is handled but
hidden (`warming`), avoiding duplicate stock animation/draw side effects. Both
eyes use the same identity, time and first-eye decision. The immutable metadata
snapshot travels with the copied image so that resized text does not use a
different frame's bounds or pivot.

The caller owns a stable identity combining HUD owner, level world, interaction
target and layout generation. It must latch that identity through an eye pair.
Identity changes within a frame are rejected, not silently recaptured. Target
change, hidden HUD, time rollback, missing capture submission and destruction
invalidate old content. A copy failure returns control before invoking a new
draw; a draw failure propagates without retrying an animation callback. Failures
latch until a new controller is created. Destruction retires ownership before
calling backend cleanup, preventing a second cleanup attempt.

## Engine integration still required

The existing HUD panel provides a proven starting point for whole-widget capture:
a dedicated UI world/viewport, a RGBA8 target and a separate completed-copy target.
It preserves all rasterized text, textures, rectangles and progress indicators.
Its textured world quad reverses the facing basis and UVs; direct GUI text cannot
be assumed to support that same transformation.

The popup's stock `_draw_widgets` runs inside an already-open renderer pass.
Redirecting it therefore needs an independent pass and exception-safe scenegraph
restoration. Its pivot follows the item's marker; a local capture must translate
the complete widget away from screen edges without changing stock updates.
Bounds must include description growth, extra-info and event panels, shadows,
hold-progress and animation. A guessed fixed rectangle is not a complete bounds
policy. Retained records and unsupported primitive/material paths need explicit
handling before routing real widget draws.

The image can then use the [shared marker plane](SHARED-MARKER-PLANE.md), retaining
finite depth and one central angular-size policy. Preserve stock visibility,
clamp/fade and overlay/occlusion behavior; do not silently replace those with
world-geometry occlusion. Resource extent limits, world/HUD replacement and
successful capture-world submission must be connected and tested. No generic
per-marker allocator or engine hook has been added before those decisions.

## Validation

The pinned LuaJIT fixture `test-widget-surface.lua` checks first-frame hiding,
one draw per eye pair, submitted-revision matching, image/bounds ownership,
missing submissions, target replacement, hide/show, time rollback, copy and draw
failures, and one-time cleanup. These are lifetime checks, not render or worn
acceptance. Run the `widget_surface` CTest and the full Lua source gate. Required
live work remains actual popup primitive measurements, complete engine draw
integration, and the user's center/edge checks in both eyes.

Final Windows validation: all 52 source chunks compile; `widget_surface`,
`marker_plane`, `marker_gui` and `marker_metrics` pass 4/4 in 0.15 seconds in
`build/xr-frame-stage-timing` Release. No engine runtime was rebuilt or deployed
for this checkpoint.
