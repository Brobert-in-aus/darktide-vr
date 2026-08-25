# Semantic camera probe

The Phase 0 camera probe is a read-only Darktide Mod Framework mod. Once per
second, after `CameraManager._update_camera` has applied the active viewport's
properties and forced the script-camera update, it reads that viewport's final
position, rotation, and vertical FOV and writes one structured
`DARKTIDEVR_CAMERA` line through DMF logging.

It does not change camera state, input, rendering, matchmaking, or network
traffic. It does not allocate a native hook or inspect process memory. The mod
is intentionally inactive when there is no local player viewport.

The selected manager matches the game's own `NvidiaAIAgent`, which reads
`camera_position` and `camera_rotation` from the same manager before emitting a
renderer data marker. The probe adds quaternion components and vertical FOV so
the transform can be correlated with a later graphics capture.

## Lifecycle repair and runtime evidence

The first prototype sampled from `mod.update` and called
`Managers.player:local_player(1)`. During boot, DMF invoked that callback before
a network peer existed, causing an access violation. That prototype was
removed; the current hook runs only after a valid camera-manager viewport has
been updated and has no player-manager dependency.

The repaired synchronized run recorded 69 valid `player1` samples with 17
unique positions while external ETW recorded 2,501 presents from one DXGI
swapchain. Every parsed value was finite and every quaternion was unit length
within 0.01. The run produced no second crash or invalid sample.

A later 180-second main-menu/operative-selection soak recorded 20,875 presents,
remained responsive, and shut down cleanly with no access violation or Lua
error. That UI screen did not call the hooked gameplay camera update, so this is
probe-loaded stability evidence rather than a second camera data set.

## Output contract

```text
DARKTIDEVR_CAMERA schema=1 viewport=<name> position=<x>,<y>,<z> rotation=<x>,<y>,<z>,<w> vfov_rad=<radians>
```

All numeric fields must be finite. Sampling is limited to 1 Hz during Phase 0
to keep log volume low. Logs belong under ignored `artifacts/phase0/` when
copied into the research record.

## Installation boundary

The source is under `mods/darktidevr_camera_probe/`. Running it requires the
community Darktide Mod Loader and Darktide Mod Framework, which patch
`bundle/bundle_database.data` and load Lua code into the game. Installation
must preserve the original database as `bundle_database.data.bak`, record the
before/after hashes, and retain a tested unpatch path. Do not install or run the
probe when EAC is active.

For the tested install, the backup hash exactly matches the pristine database.
Restore the database with the locally built, audited patcher while Darktide is
closed:

```powershell
_downloads\dtkit-patch\target\release\dtkit-patch.exe --unpatch `
  'D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE\bundle'
```
