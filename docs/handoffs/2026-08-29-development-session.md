# 2026-08-29 development session

## Implemented

- Made range locomotion additive. Neutral VR thumbstick state leaves the
  existing Darktide movement cache untouched; active VR movement combines with
  and clamps the signed game movement vector.
- Added raw per-hand thumbstick, existing-vector, combined-vector, and ownership
  telemetry for the next live range test.
- Added a normal-off, range-only headless third-person presentation seam using
  Darktide's own equipment visibility path. The visual swap shows the complete
  3P loadout, hides the 1P visual rig, then hides 3P face, facial hair, hair,
  and headgear slot units without changing gameplay/camera mode.
- Added `set-headless-body-presentation.ps1`.
- Added a runtime prepared-frame versus full-second-eye A/B and
  `set-full-second-eye-probe.ps1` for the enemy-shadow investigation.
- Built Release and synchronized the Lua/native binaries into the installed
  game. The installed range flags currently enable gameplay input, controller
  aim, body IK, and headless 3P presentation; the full-second-eye probe defaults
  disabled.

## Validation

```powershell
pnpm dlx luaparse --quiet --file mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua
git diff --check
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build/windows-vs2022 --config Release
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build/windows-vs2022 -C Release --output-on-failure -E '^xr_(projection|theatre|stereo_sbs)_smoke$'
```

Result: Release build passed and 27/27 non-HMD tests passed. The complete
30-test invocation produced the same 27 passes; the three strict OpenXR smoke
tests failed closed because VirtualDesktopXR returned `hmd-unavailable`.

## Next live gates

1. In the Psykhanium, verify WASD still works with VR input enabled, then move
   the left thumbstick and confirm both raw transport and player movement.
2. Check that the local 1P arms/weapon are absent and the 3P body is visible
   without face/headgear geometry intersecting the cameras. Exercise both
   controllers to validate the existing arm IK and note duplicate weapons.
3. At a repeatable enemy-shadow boundary, compare the default prepared-frame
   second eye with `darktidevr_full_second_eye.flag` enabled. Record whether
   the eye-specific shadow defect changes and the frame-time cost.

No Mac-only validation applies to this Windows PCVR work. The Quest is reachable
over ADB, awake, and had the temporary proximity override reapplied. Virtual
Desktop Streamer did not expose a usable Windows window or HMD during this
session, so no headset gate was claimed.
