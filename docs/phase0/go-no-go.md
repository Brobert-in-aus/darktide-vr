# Phase 0 renderer hooks and anti-cheat compatibility memo

**Decision:** Go for continued private research; no-go for distribution or
ordinary matchmaking use.

This is an evidence log, not an anti-cheat evasion plan. A technically working
renderer hook is insufficient if EAC/session health changes or if clean removal
cannot be proven. The project will not disable, conceal, spoof, or bypass EAC.

## Evidence available

- The inspected build is fingerprinted reproducibly and defaults to safe mode.
- A standalone hardware D3D12 device, command queue, flip-model swapchain,
  explicit barriers/fence, and final `Present` loop run without loading the
  game.
- The synthetic path survives an automated mid-run swapchain resize and
  render-target recreation. Debug-layer corruption/errors and device removal
  now fail the run instead of relying on visual inspection.
- The official Khronos 1.1.61 loader is pinned, built as an application-local
  DLL, linked by the harness, and accompanied by its license.
- Loader-to-runtime negotiation is proven. VirtualDesktopXR `1.0.10` rejects
  an OpenXR 1.1 request but accepts the harness's explicit 1.0 fallback.
- With the HMD connected, Virtual Desktop exposed two stereo views, accepted a
  runtime-selected D3D12 session, created two three-image eye swapchains, paced
  300 frames, and completed requested-exit/`STOPPING` teardown. The headset was
  not compositor-visible, so `shouldRender` stayed false; actual projection
  submission remains an explicit gate rather than an inferred success.
- With the headset compositor-visible, the harness acquired, cleared, fenced,
  released, and submitted both eye images for 300/300 frames. A subsequent
  600/600-frame unattended run also passed after applying the reversible Quest
  proximity override and removing the headset. Both runs exited cleanly through
  `STOPPING`.
- The depth-tested stereo diagnostic now exercises asymmetric runtime FOV,
  checker and reflective surfaces, depth poles, alpha-tested geometry, rapid
  motion, strobing geometry, and a dense HUD proxy. A compositor capture shows
  the expected binocular difference.
- A 6,000-frame compositor-visible run completed at about 119.7 Hz without a
  debug-layer error. The desktop path completed 10,000 presents with one resize
  and no device removal (`p99 1.1364 ms` CPU wall time).
- Read-only PE inspection shows that this build imports D3D/DXGI creation entry
  points through `sl.interposer.dll` rather than directly from the system DLLs.
  Any renderer observation design must account for Streamline wrapping and
  cannot assume a direct-import `Present` seam.
- Darktide was launched normally through Steam for one bounded external ETW
  experiment. No Phase 0 executable attached to, injected into, hooked, or
  modified it.
- The current Steam launcher explicitly logged `Using EAC: False`, started
  `Darktide.exe` directly, and left `EasyAntiCheat_EOS` stopped. This is evidence
  for the inspected build and configuration, not a guarantee for future builds
  or backend policy.
- Signed Intel PresentMon 2.5.1 observed one unambiguous DXGI swapchain for all
  12,080 captured presents. The 3072x1728 output predominantly used hardware-
  composed independent flip and remained responsive through operative select.
- The observation policy and swapchain candidate selection are implemented as
  game-independent, unit-tested primitives. They reject unknown identities,
  unstaged execution, EAC-active sessions, mutation/bypass requests, insufficient
  samples, and ambiguous top candidates.
- A first Lua camera probe crashed because its frame callback accessed the local
  player before the network peer existed. That design was discarded. The
  repaired probe hooks `CameraManager._update_camera` after the original update
  and reads only the already-valid viewport's position, quaternion, and FOV.
- In a synchronized repaired run, 69 valid `player1` camera samples (17 unique
  positions) were recorded alongside 2,501 presents from one swapchain. A
  separate 180-second main-menu soak produced 20,875 presents, no crash, no Lua
  error, and a clean Alt+F4 shutdown; that screen did not exercise the hooked
  camera method.
- Mod-loader installation retained `bundle_database.data.bak`; its SHA-256
  exactly matches the pristine database, providing a verified unpatch source.

## Required evidence before a decision

1. Extend the passing D3D12 debug-layer resize gate to alt-tab, display change,
   and simulated device-loss recovery.
2. Correlate the now-validated semantic final camera with the native transform
   or render resource without changing camera state or replacement rendering.
3. Establish the staged, owner-approved environment for any native loader
   experiment and record EAC/session behavior. Do not proceed directly to
   ordinary matchmaking.
4. Prove clean disable/removal and a two-hour camera/stereo-disabled soak before
   enabling either feature.

## Decision rules

- **Go for continued private research:** final `Present` and the validated main
  camera can be observed stably, teardown is clean, and staged tests show no
  EAC/session degradation.
- **Redirect to external viewer:** native observation works technically but
  native loading is incompatible with EAC or cannot be made cleanly reversible.
- **Stop:** testing would require bypass/concealment, compromises account or
  service safety, or observation remains unstable.
