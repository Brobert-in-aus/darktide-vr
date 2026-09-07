# Development update recovery

`tools/stereo/sync-darktide-vr-dev.ps1` now stages its Lua, native libraries,
shader changes and runtime flags as one update. It retains the closed-game
requirement and pinned LuaJIT gate. All sources and existing destination bytes
are copied and SHA256-verified before the first installed file changes.

`Invoke-DarktideDeploymentTransaction` rejects duplicate destinations, paths
outside the selected installation, reparse points below that root, directory
destinations and missing parent directories. It checks that each destination
still matches its staged original before writing, then verifies the result.

On a caught failure, it restores touched files in reverse order, removes new
files and verifies the original hashes. A locked file whose failed write left
its original bytes intact does not need to be rewritten. Backup originals,
staged inputs and `manifest.json` remain under
`artifacts/deployment-backups/deployment-<random>/`, outside the game. These
machine-specific files are not committed.

The receipt distinguishes `committed`, `rolled_back`, `rollback_incomplete`
and `failed_before_write`. An incomplete rollback includes the affected paths;
keep the backup and resolve those failures before launching. This handles
caught update errors, not abrupt process termination or power loss. Recovery
from those interruptions still requires inspection of the saved manifest and
original files. A user-facing recovery command and clean installer remain work.

## Validation, 8 September 2026

Windows PowerShell fixtures exercise real temporary filesystem writes and the
actual sync orchestration. A locked final destination forces a late failure
after earlier Lua, native and flag writes; the installed file set and hashes
must return exactly to their originals. Success, diagnostic removal, newly
created file rollback, path/junction guards and Lua-gate rejection are covered.
Process discovery and compilation are fixtures in the orchestration test; the
real project Lua gate runs separately in CTest. Nothing from these checks is
deployed to the running accepted-baseline preview session.

Run `ctest --test-dir build/windows-vs2022 -C Release --output-on-failure` with
the configured Windows build. Evidence is recorded in the current workday
handoff.
