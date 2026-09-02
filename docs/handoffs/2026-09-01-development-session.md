# Development-session handoff — 2026-09-01

This is the next-session entry point. Read `AGENTS.md`, this file and
[`../phase1/todo-2026-09-02.md`](../phase1/todo-2026-09-02.md) before changing
or launching anything. The detailed chronological record through the afternoon
remains in
[`2026-09-01-fresh-session-handoff.md`](2026-09-01-fresh-session-handoff.md).

## Repository and live state

- Workspace: `D:\Projects\games-xr\Warhammer 40k Darktide VR`
- Branch: `phase0/feasibility-bootstrap`
- HEAD remains `3ce27e5` (`Add configurable VR movement reference`).
- The working tree is an intentional, uncommitted all-day development batch.
  Do not reset, checkout, clean or overwrite it. Preserve the unrelated
  user-owned `Codex Image 25 Aug 2026, 08_53_34.jpg`.
- The final worn verification run used VirtualDesktopXR's recommended
  `2496x2688` per-eye extent and reached true stereo with advancing
  `shared_ready`.
- The verified game was initially left running for the user. At final
  documentation verification, Darktide PID 114880 was no longer present; no
  desktop-control session was used to stop it. Begin the next launch from the
  normal closed-game preflight and wait at least ten seconds after any future
  exit before relaunching.
- No desktop-control session is held.

## Mandatory start of every development day

Before any other work:

1. check Virtual Desktop Streamer/VDXR is running and available;
2. check exactly one authorized Quest is connected through a working ADB
   client;
3. disable the Quest proximity/wear sensor automation with
   `tools\quest\set-proximity-override.ps1 -Action Disable`, then check status;
4. confirm the headset stays awake and a renderable OpenXR session is possible.

Quest passthrough normally suspends Virtual Desktop. Treat that as a recoverable
runtime state, not a fail-closed condition and not automatic justification for
restarting VD. The full checklist is in
[`../phase0/quest-test-control.md`](../phase0/quest-test-control.md).

## What was achieved today

The all-day implementation and audit work recorded in the chronological
handoff includes:

- independent controller-owned hand-proxy mechanics, source-hand/equipment
  synchronization and headless controller/weapon matrices;
- compositor reticle sizing/alpha work and broader Psyker controller-aim
  coverage;
- synchronized shared-eye readback and generation-safe eye/menu/controller/head
  transports with stale-packet rejection;
- fail-closed Lua/deployment improvements, same-ADB Quest watcher/proximity
  handoff and run-owned cleanup fixes;
- command-list/resource/fence lifetime fixes and reduction of production render
  hook overhead;
- a production performance profile that no longer silently installs the broad
  diagnostic hook set;
- repeated Release/Debug source and native validation, authenticated hub runs
  and offline dual-view evidence;
- a shared shadow-cull union and headless edge-light audit that narrowed the
  remaining worn lighting problem to per-submission light-volume or
  screen-space bounds.

The worn session then supplied direct product evidence:

- loading/character-select billboards recentered about once per second and the
  aim crosshair appeared in their bottom-right corner; both were fixed during
  the session but later reverted while reconstructing a known baseline and must
  be reimplemented narrowly;
- hands were invisible from the first worn frame, gloves stretched to bracers
  at the player's sides and the bracers were still attached to the 3P rig;
- hub performance remained subjectively poor/roughly unchanged;
- sharpening was reported as `0.5` in settings but behaved as disabled until
  the user changed it;
- settings rendered in a `1280x720` top-left region and submenu cursor targeting
  was offset;
- points of interest, HUD and world overlays were compressed toward the top of
  the VR image;
- one attempted resolution path could remain billboarded after loading instead
  of entering true stereo;
- loading screens, shops and character select may temporarily follow the
  desktop mirror, but their long-term resolution and behavior must be separate;
  world overlays must be high resolution and independent now.

Several resolution experiments and presentation fixes were deliberately
reverted after they worsened the view. Do not restore an experiment merely
because it exists in an old diff or reconstruction. Tomorrow's first task is to
reimplement only the behavior the user explicitly accepted, then address menus,
HUD/markers and hand/bracer presentation in that order.

## Confirmed transparent-layer root cause and fix

### Evidence

The remaining failure was a partly transparent, zoomed duplicate/lighting-like
world layer that appeared one to two seconds after stereo began. Manually
resizing the desktop mirror removed it.

A controlled compact before/after trace proved that manual resize did **not**
resize or recreate the DXGI swapchain, eye surfaces or AMD FSR replacement
backbuffer. Resource pointers, `2496x2688` dimensions, format and capture state
remained unchanged. Only the physical client rectangle changed.

The follow-up window-message trace exposed the lifecycle error:

- startup nudged the client from `1280x768` to `1281x768`, then to
  `1920x1080`;
- `ensure_virtual_window_proc` had previously run only during swapchain metadata
  discovery, which occurred before Lua enabled virtual-size handling;
- therefore the startup nudge happened before the translating window procedure
  was installed;
- Stingray received physical `WM_SIZE` extents while the resize hook forced the
  swapchain to `2496x2688`, producing two mixed-size rebuilds and stale
  viewport-dependent state;
- the later manual resize occurred after metadata invalidation had finally
  installed the procedure. Its `WM_SIZE` messages were translated to the XR
  extent and the artifact disappeared.

Evidence is preserved under
`artifacts/diagnostics/resize-root-cause/`, especially:

- `true-before-resize-compact.log`;
- `true-after-resize-compact.log`;
- `window-message-before-after-compact.log`.

Files named `before-manual-resize-focused.log` and
`after-manual-resize-focused.log` are both post-resize and are explicitly not
valid before/after evidence.

### Fix

`dtvr_set_virtual_size_message(1)` now immediately installs the translating
game-window procedure on the already discovered output window. The existing
metadata-refresh installation remains a recovery fallback.

The fixed trace proved the required order:

1. `VIRTUAL_WNDPROC_INSTALLED` at frame 3364;
2. startup expand nudge at frame 3365 and restore at frame 3366;
3. both `WM_SIZE_WNDPROC` events observed with virtual handling active;
4. one `ResizeBuffers` call requested and applied `2496x2688`, instead of two
   conflicting physical-size requests;
5. the user waited without touching the mirror and confirmed the transparent
   layer stayed absent.

`tools/stereo/test-darktide-lua-source.ps1` now fails closed if the virtual-size
configuration export does not install the window procedure after enabling the
feature. Keep this regression contract.

The final verified DLL still contains the compact startup-resize diagnostic
recorder used to establish this proof. It is intentionally retained while the
working game stays open, but it performs periodic descriptor queries and file
I/O. Before tomorrow's performance measurements, remove it or put it behind an
explicit diagnostic opt-in, rebuild and rerun the lifecycle regression. Keep
the preserved logs and the immediate window-procedure installation itself.

Do not treat a delayed synthetic resize as the fix. Correct lifecycle ordering
is the fix. Do not use the broad 4 MB/eight-frame draw trace again; it deadlocked
Darktide. Use compact hypothesis-specific diagnostics and preserve a genuine
pre-intervention trace.

## Validation completed for the final fix

```powershell
.\tools\stereo\test-darktide-lua-source.ps1

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build build\windows-vs2022 --config Release

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir build\windows-vs2022 -C Release --output-on-failure
```

Results:

- Lua source/syntax gate: pass, `198/198` file-scope locals, four modules;
- Release build: pass;
- CTest: 33/33 pass, including OpenXR projection/theatre/stereo smoke tests;
- deployed native DLL SHA-256:
  `4E93E09C17AE5725B4C007567E61421E2E342913565FE7374ACEAE136C665067`;
- fresh authenticated worn hub launch: true stereo, nonzero advancing
  `shared_ready`, correct startup message order and no transparent layer without
  manual resize.

## Tomorrow's order

1. Run the mandatory VD/ADB/proximity preflight.
2. Reimplement and worn-verify the reverted billboard/crosshair and related
   accepted fixes without changing the confirmed resolution lifecycle.
3. Fix settings/menus and their pointer coordinate ownership.
4. Fix high-resolution, mirror-independent HUD and world markers.
5. Fix independent player hand/glove/bracer presentation.
6. Resume the comprehensive performance and bug hunt, including hub cadence,
   far-edge lighting, passthrough suspension and synthetic two-view movement.

The detailed gates are in
[`../phase1/todo-2026-09-02.md`](../phase1/todo-2026-09-02.md).
