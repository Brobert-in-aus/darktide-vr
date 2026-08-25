# Phase 0 - technical feasibility

**Status:** Exit criterion met for continued private research
**Started:** 23 August 2026
**Safety posture:** Unknown builds fail closed. No game process injection,
memory edits, file replacement, EAC bypass, or matchmaking test has been
performed.

## Exit criterion

Observe the active desktop camera and final `Present` without instability.
The repaired semantic camera probe and external ETW observer concurrently
recorded the `player1` camera and one unambiguous final DXGI swapchain. This
meets the Phase 0 research gate at the main-menu/operative boundary; gameplay,
camera-override, stereo integration, and long-duration validation remain later
gates.

## Deliverables

| Deliverable | State | Current evidence / next gate |
| --- | --- | --- |
| Build fingerprint tool | Implemented, initial validation complete | SHA-256, PE file/product version, game/content revisions, JSON schema; add a known-build capability catalog next |
| D3D12/OpenXR synthetic harness | Implemented, transport and scene gates passed | Pinned loader, per-eye projection from runtime poses/FOV, depth-tested diagnostic scene, stereo submission, and clean lifecycle pass; desktop `Present`, resize, debug-info-queue, device-health, and timing gates pass. Alt-tab/display-change and device-loss recovery remain |
| Desktop camera-source map and pass census | Semantic camera and final `Present` correlated | A DMF post-update hook recorded 69 valid `player1` camera samples while signed Intel PresentMon recorded 2,501 presents from one real swapchain. Read-only PE census proves creation routes through NVIDIA Streamline; native resource/pass census remains |
| Renderer-hook/EAC go/no-go memo | Go for continued private research only | EAC was explicitly disabled by the normal launcher; ordinary matchmaking, distribution, and any bypass/concealment remain no-go |

## Local baseline captured

- Game version: `1.12.0-b773907`
- Game revision/content revision: `135417`
- PE file version: `1.3.770.210`
- Executable SHA-256:
  `e0f581d2c63b692c7d9f328e3edeb39c0f484956905569d38ba27bbb3fcc0aae`
- D3D12 adapter used: NVIDIA GeForce RTX 4090, feature level 12.0
- Active OpenXR runtime: VirtualDesktopXR `1.0.10`
- OpenXR loader: official Khronos `1.1.61`, built from pinned commit
  `5267613edf3d937e3d77556a106a65c2f82b25c6` and copied app-locally
- Runtime compatibility: Virtual Desktop rejects an OpenXR 1.1 application API
  request with `XR_ERROR_API_VERSION_UNSUPPORTED`; the harness retries 1.0 and
  successfully creates an instance
- Headset status during validation: unavailable, so system/session/swapchain
  validation initially remained a headset gate
- Headset-connected validation on 24 August 2026: HMD system and D3D12 session
  created; two `2688x2880` per-eye swapchains created with three images each
  using `DXGI_FORMAT_R8G8B8A8_UNORM_SRGB`; 300 `xrWaitFrame`/begin/end cycles
  ran at about 115 Hz and exited through `STOPPING` cleanly
- Visibility status: the runtime reached `XR_SESSION_STATE_SYNCHRONIZED` but not
  `VISIBLE`/`FOCUSED`, so `shouldRender` remained false and zero projection
  layers were submitted. The new `--require-rendering` gate fails explicitly in
  this state; the headset must be awake/worn with Virtual Desktop foregrounded
- Compositor-visible validation: after correcting the frame-loop/event-pump
  ordering, Virtual Desktop reached `VISIBLE` then `FOCUSED`; 300/300 stereo
  projection frames passed at about 115.3 Hz, followed by an unattended
  600/600-frame run at about 117.5 Hz with the temporary Quest proximity
  override active and the headset confirmed unworn
- The stereo diagnostic now contains asymmetric projection, a checker floor,
  depth poles, near geometry, specular and reflective surfaces, alpha-tested
  foliage, rapid motion, strobing geometry, and a dense high-contrast HUD proxy
  (790 triangles). A compositor capture confirms distinct left/right views.
- Headset stress run: 6,000/6,000 rendered projection frames at about 119.7 Hz
  with the Quest proximity override active; requested-exit teardown completed
  without D3D12 debug errors.
- Headset-free soak: 10,000 serialized D3D12 presents with one mid-run resize,
  debug-layer error capture enabled, and no device removal or debug error
  (`p50 0.1590 ms`, `p95 0.6843 ms`, `p99 1.1364 ms` CPU wall time)
- Staged Darktide observation: the normal Steam launcher logged
  `Using EAC: False`, started the exact known `Darktide.exe` directly, and left
  `EasyAntiCheat_EOS` stopped. Signed
  Intel PresentMon 2.5.1 captured 12,080 DXGI presents from one swapchain over
  153.5 seconds at 3072x1728. Independent flip accounted for 12,078 presents;
  interval telemetry was p50 11.7654 ms, p95 19.5934 ms, p99 32.8036 ms.
- The first semantic camera probe crashed during boot because it queried
  `Managers.player:local_player(1)` before a network peer existed. The probe was
  redesigned as a post-update hook on `CameraManager._update_camera`, removing
  that lifecycle dependency. The repaired run produced 69 finite, unit-
  quaternion `player1` samples with 17 distinct positions while the external
  observer simultaneously recorded 2,501 presents from one swapchain; no
  second crash or invalid sample occurred.
- A separate 180-second repaired-probe soak remained responsive through
  operative selection and closed normally. It recorded 20,875 presents from
  one swapchain, all hardware-composed independent flip (`p50 8.4712 ms`,
  `p95 10.5913 ms`, `p99 12.4854 ms`). This screen did not call the hooked
  gameplay camera method, so the soak is stability evidence, not an additional
  camera-sample run.
- The mod-loader database patch is reversible: the saved backup SHA-256 exactly
  matches the pristine database SHA-256. Installation hashes and ignored raw
  logs are retained under `artifacts/phase0/`.

The synthetic timing numbers validate telemetry and provide a regression
baseline only. The current harness intentionally waits for its GPU fence every
frame and does not represent Darktide or VR performance.

The fingerprint is local research metadata. It does not whitelist hooks or
make the build safe for injection.

See the [static renderer observation map](renderer-observation-map.md) for the
current read-only creation-chain evidence and its limits.
See the [runtime observation protocol](runtime-observation-protocol.md) for the
implemented policy gate and the approval boundary before any game interaction.
See the [semantic camera probe](camera-probe.md) for its lifecycle fix, output
contract, synchronized evidence, and removal path.
See [Quest unattended test control](quest-test-control.md) for the reversible
presence-sensor override and restore procedure.

## Validation record

Run on the Windows PC from the repository root:

```powershell
cmake --preset windows-vs2022
cmake --build --preset windows-vs2022-debug
cmake --build --preset windows-vs2022-release
cmake --build build\windows-vs2022 --target RUN_TESTS --config Debug

# Opt in to the compositor-visible CTest gate when the headset is available.
cmake -S . -B build\windows-vs2022 `
  -DDARKTIDEVR_ENABLE_HEADSET_TESTS=ON

build\windows-vs2022\tools\fingerprint\Release\darktidevr-fingerprint.exe `
  --exe 'Warhammer 40,000 DARKTIDE\binaries\Darktide.exe' `
  --game-root 'Warhammer 40,000 DARKTIDE'

build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe `
  --frames 120 --resize-at 60 --debug-layer

# Run while the headset is connected; this fails closed otherwise.
build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe `
  --frames 120 --require-openxr

# Run while the headset is awake/worn and the session is compositor-visible.
build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe `
  --frames 300 --debug-layer --require-rendering --xr-frames 300

tools\present_observer\observe-present.ps1 `
  -GameExe 'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\binaries\Darktide.exe' `
  -PresentMonPath '_downloads\presentmon-2.5.1\PresentMon-2.5.1-x64.exe' `
  -DurationSeconds 180

tools\camera_probe\summarize-camera-log.ps1 `
  -LogPath 'artifacts\phase0\darktide-camera-probe.log' `
  -OutputJson 'artifacts\phase0\darktide-camera-probe-summary.json'

ctest --test-dir build\windows-vs2022 -C Release --output-on-failure
```

No Mac-only validation applies to this Windows PCVR phase.
