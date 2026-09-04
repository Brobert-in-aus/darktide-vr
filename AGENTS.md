# Project working agreements

## Ownership and validation

- Use one branch or worktree per task that changes files. Read-only reviews may
  use the existing checkout. Never let two agents edit one working tree concurrently.
- Commit or stash before moving work between machines; use the pull request as
  the cross-device handoff. See [infrastructure](docs/PROJECT-INFRASTRUCTURE.md)
  for workstation responsibilities and access procedures.
- This project builds and runs on Windows x64. Record validation commands,
  results, and any required live checks in the handoff or pull request.
- Keep credentials, generated output, and machine-specific agent state out of Git.

## Live XR readiness

- Offline editing, documentation, builds, and isolated tests do not require a
  headset. Before deployment, Darktide interaction, or unattended XR work, run
  `tools/unattended/invoke-unattended-preflight.ps1` in its default Ready mode.
- Readiness requires Virtual Desktop Streamer, VDXR, exactly one authorized
  Quest, and a renderable OpenXR session. Do not commit device identifiers.
- Apply `tools/quest/set-proximity-override.ps1 -Action Disable`, then `-Action
  Status` at the start of a live development session. The preflight also applies
  the override and checks power state. Restore automation when development ends.
- Recheck readiness after a disconnect, runtime/streamer change, headset sleep,
  or before a new unattended session. An unchanged live session need not repeat
  the smoke test before every edit or sync.
- VD suspension during Quest passthrough is recoverable: resume streaming and
  retry. Do not restart VD solely because of suspension. Use `-Mode Inventory`
  for observation during an existing session; it does not certify readiness.

## Lua and visual acceptance

- Compile every Lua chunk with the pinned LuaJIT gate:
  `tools/stereo/test-darktide-lua-source.ps1`. Build its validator first with
  `tools/lua/build-luajit.ps1`. Sync, launch, and preflight must retain this gate.
- LuaJIT permits at most 200 simultaneously active locals. Prefer modules and
  existing state tables; compiler validation is authoritative, not indentation.
- Initialize state tables before using their members. After deploying Lua changes,
  verify fresh stereo initialization messages and nonzero harness `shared_ready`.
  An OpenXR session alone can be flat fallback after a mod-load failure.
- Prefer the user's worn, real-tracking check for hand alignment and visual
  acceptance. Ask for a specific observation before synthetic visual experiments.
  Automated tracking/rendering counters do not establish worn visual acceptance.
- Arm automated Psykhanium entry with `start-darktide-vr.ps1 -EnterPsykhanium`
  while Darktide is closed. Arming after a populated hub loads risks the known
  base-game remote-husk teardown race.
