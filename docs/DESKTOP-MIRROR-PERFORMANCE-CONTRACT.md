# Desktop mirror performance controls

The user confirmed on 11 September that the game desktop mirror remained
visible during simulator runs, including when the simulator preview was black.
The simulator setting `desktop_window_capture=false` only disables the XR
viewer's capture of the game window. It does not disable game mirror rendering,
DXGI presentation, or Virtual Desktop encoding.

## Source audit

- `src/producer/native_capture.cpp` maintains a separate mirror surface and
  fence, copies the left eye into that surface, and can blit it to the desktop
  backbuffer. Packed submission takes a different path. Disabling only
  `present_desktop_eye_mirror` does not prove all mirror work is removed.
- `engine_flat_mirror_required` explicitly preserves flat menus and loading
  screens when the engine uses a private backbuffer. A gameplay-only suppression
  must retain these transitions.
- `src/core/output_layout.cpp` selects eye extent independently of mirror
  extent, but this helper alone does not establish live engine independence.
- The Lua HUD editor and menu pointer mapping use mirror dimensions. The XR
  viewer also reads window extent for flat interactive presentation, and a
  configured capture source's destruction currently ends the viewer session.
  Complete window independence is therefore not established.

## Controlled tests still required

The initial native control now reads `DTVR_DISABLE_GAMEPLAY_MIRROR=1` once
per process (unset/default preserves current behavior). It suppresses the
completed-left-eye mirror copy and desktop mirror blit only in `stereo_world`.
Flat and world-anchored menu modes retain their existing path. This does not
suppress engine rendering, DXGI Present, or packed FG presentation, so label
it **gameplay mirror-copy suppression**, not complete mirror removal.

Windows x64 Release native build and `stereo_color_resample` test pass using
`cmake --build build/xr-window-capture-demand --config Release --target
darktidevr_native_capture darktidevr-stereo-color-resample-tests` and
`ctest --test-dir build/xr-window-capture-demand -C Release -R
'^stereo_color_resample$' --output-on-failure`. Mode coverage includes all eight
presentation modes with suppression enabled and disabled. Live counters,
focused benchmark build, A/B measurements and menu recovery remain pending;
the accumulated development DLL has not been deployed.

1. Compare normal versus suppressed gameplay mirror copies with the same
   native binary and explicit logged switch. Retain actual Present, shared-eye
   publication, synchronization and flat-menu recovery in this first test.
2. Separately compare viewer capture enabled versus disabled/on-demand. This
   measures the viewer's capture work, not game mirror rendering or VD encoding.
3. Vary desktop client resolution with XR eye extent fixed at 2496x2688. Check
   published eye dimensions, projection/pose pairing and HUD target dimensions.
   Keep this separate from the mirror-copy comparison.
4. Test hidden/minimized and ultimately absent-window operation separately.
   Hiding or minimizing a window is not evidence of removing mirror rendering;
   closing the game window may terminate the process. An absent-window test
   needs an intentional engine/viewer path, not destruction of the live window.

Use matched mission, Quality DLSS, fixed foreground policy and repeated A/B/A
runs. Record distinct native/generated frames, GPU activity and VD encoder
state. Test FG off first, then verify FG on because packed presentation differs.
Counters establish data flow, not worn HUD visual acceptance. No mirror-off
performance result or complete desktop independence is claimed yet.
