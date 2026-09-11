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

The native control reads `[probe] disabled=1` from
`darktidevr_gameplay_mirror.flag` alongside the loaded DLL (default preserves
current behavior). The benchmark saves and restores both flag paths. It suppresses the
completed-left-eye mirror copy and desktop mirror blit only in `stereo_world`.
Flat and world-anchored menu modes retain their existing path. This does not
suppress engine rendering, DXGI Present, or packed FG presentation, so label
it **gameplay mirror-copy suppression**, not complete mirror removal.

Windows x64 Release native build and `stereo_color_resample` test pass using
`cmake --build build/xr-window-capture-demand --config Release --target
darktidevr_native_capture darktidevr-stereo-color-resample-tests` and
`ctest --test-dir build/xr-window-capture-demand -C Release -R
'^stereo_color_resample$' --output-on-failure`. Mode coverage includes all eight
presentation modes with suppression enabled and disabled. Opt-in `[probe] metrics=1` emits cumulative mirror copy/blit counters every
600 Presents. An initial environment-only attempt did not activate metrics
through the Steam launch path and is excluded from the controlled comparison.
The corrected runner uses `-DisableGameplayMirror` and `-GameplayMirrorMetrics`.
The focused native build and A/B/A measurements below are complete. Menu
recovery and physical visual acceptance remain pending; the accumulated
development DLL has not been deployed.

## 11 September controlled result

Focused source `7a62226` adds mirror controls to stacked native `2f2bed3`.
DLL SHA-256: `2250B200F395C85FC508505329B4BC58F974AD53F9E483EA437AEC6DCA2EA012`.
Build directory: `build/focused-gameplay-mirror-control`; native Release build
and `stereo_color_resample` pass (1/1). The benchmark viewer is unchanged
`216E3F760D1CC9BE5489376EF5DDB0A473F49990F144F0227F8CF87178E429F5`.

Same DLL, 2496x2688 per eye, Quality DLSS, FG off, unlimited cap, 120 Hz,
13 configured workers, stationary `cm_archives` difficulty 3, HUD/menu enabled,
preview and viewer desktop capture disabled. Ninety seconds after workload
readiness, excluding ten seconds warmup:

| Run | Mirror copies | Distinct native FPS | Analysed seconds |
| --- | --- | ---: | ---: |
| mirror-a2 | normal | 89.09399 | 80.81353 |
| mirror-b | suppressed | 89.52077 | 80.42827 |
| mirror-a3 | normal | 89.05575 | 79.50077 |

Approximately 0.5% above the bracketing controls, with only one suppressed
run: a small local signal, not a substantial or established general gain.
At Present 9000, gameplay copy/blit counters were 4544/7570, 0/0 and
4621/7540 respectively. This confirms suppression of the instrumented paths;
it does not establish no desktop rendering or window independence.
All runs exited cleanly, restored every tracked file and had zero pose
mismatches. GPU sampled/unavailable records were 26/2, 27/1 and 27/0.
No Streamer activity was observed, but its engine-counter coverage was
incomplete; do not equate missing samples with proven absence of encoding.
Physical Ready failed before each launch; these are authorized simulator
fallback measurements, not headset results. Proximity automation was restored.

Ignored evidence: `artifacts/unattended/synthetic-descriptor-demand-mirror-{a2,b,a3}-20260911`
and `mirror-{a2,b,a3}-counters-20260911.log`. The earlier `mirror-a` run used
the ineffective environment control and is excluded. Accepted native SHA
`FCCDD0DE699F9D50D2BD316792829D4EE5700843D925D194BE4DF1F3EEB02369`
was rechecked at both installed locations after the final run. Default remains
normal mirror behavior. No FG, resize, hidden-window or absent-window result
is claimed.

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
