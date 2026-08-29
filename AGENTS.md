# Project working agreements

## Ownership and isolation

- Use one branch or worktree per agent task.
- Do not allow two agents to modify the same working tree concurrently.
- Commit or stash work before moving a task between the PC and Mac.
- Treat the pull request as the authoritative cross-device handoff.

## Platform responsibilities

- Treat the PC and Mac as co-equal trusted administrative workstations.
- Run general implementation, large tests, containers, and GPU work on the PC.
- Run Xcode builds, Simulator tests, signing, and Apple-platform validation on
  the Mac.
- Use the N150 for Git coordination and lightweight automation only.
- These responsibilities describe available capabilities, not authority or
  trust.

## Completion

- Record the commands used to validate the change.
- Call out validation that can run only on another platform.
- Do not commit credentials, signing material, generated build directories, or
  machine-specific agent state such as `.codex` or `.claude`.

## Darktide Lua safety

- Treat `darktidevr_stereo_probe.lua` as a single LuaJIT chunk with a hard
  200-local compiler ceiling. Do not add new file-scope locals; put new state
  on an existing state table or split implementation into a required module.
- Run `tools\stereo\test-darktide-lua-source.ps1` before deploying or launching
  Darktide. The sync, launch, and unattended-preflight scripts must retain this
  fail-closed check.
- Keep state-table initialization below its `local ... = {}` declaration. A
  mod-load error can leave OpenXR alive in flat fallback mode, so an XR session
  existing is not evidence that stereo hooks loaded.
- After each Lua change, verify a fresh console log contains the stereo mod's
  initialization messages and that the XR harness reports nonzero
  `shared_ready` before considering the launch valid.
- For automated Psykhanium testing, use
  `start-darktide-vr.ps1 -EnterPsykhanium` while Darktide is closed. Arming
  after a populated public hub has loaded can hit the known base-game remote
  husk `parent_unit_id` teardown race during the range transition.
