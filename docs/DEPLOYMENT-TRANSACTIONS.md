# Development update recovery

`tools/stereo/sync-darktide-vr-dev.ps1` now stages its Lua, native libraries,
shader changes and runtime flags as one update. It retains the closed-game
requirement and pinned LuaJIT gate. All sources and existing destination bytes
are copied and SHA256-verified before the first installed file changes.

`Invoke-DarktideDeploymentTransaction` rejects duplicate destinations, paths
outside the selected installation, reparse points below that root, directory
destinations and, by default, missing parent directories. It checks that each destination
still matches its staged original before writing, then verifies the result.

Selective trial callers may also pin reviewed bytes on each entry:
`ExpectedSourceHash` requires a `Source` entry and a 64-digit SHA256 string.
`ExpectedDestinationHash` requires that existing destination hash; an explicit
null requires the destination to be absent. Omitting either key retains the
ordinary transaction behavior. Lowercase hashes are accepted and normalized.
Malformed preconditions are rejected before staging. Every supplied precondition
is checked before any installed write, so a later mismatch cannot partially
install an earlier candidate. The manifest preserves these preconditions
separately from observed originals and staged hashes.

Pin the candidate hash from its build receipt and each installed hash from the
reviewed baseline, not from freshly hashing an unexpected replacement at install
time. These checks protect reviewed file identity; they do not prove which
source built a binary. Fresh Ready and the closed-game gate remain necessary.
Native-only trials must cover both existing destinations (`binaries` and the
mod's `bin` directory) in one transaction, leaving the bootstrap, viewer, Lua
and settings untouched. Use the saved transaction manifest for verified rollback.

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
from those interruptions requires an intact staged manifest and original files.

## Restore a saved update

After the required default Ready preflight, with Darktide closed, run
`tools/stereo/restore-darktide-vr-deployment.ps1 -Manifest <backup/manifest.json>
-GameRoot <installation>`. The chosen installation must match the manifest.
The command validates every original backup hash and destination before it
restores files. It accepts mixed original/staged/missing files after an interrupted
write and also permits undoing a completed update.

Files changed since that update stop recovery before writes. Inspect those
changes first; explicit `-AllowChangedFiles` permits replacing them, including
partial bytes left by an interrupted write. Recovery always backs up the current
state in a new transaction, so those changed bytes remain available. A caught
failure during restoration rolls back to the state before recovery started.

Recovery also pins each original backup hash and the exact installed state it
validated, including missing files, through transaction staging. A destination
changed, removed or newly created in that interval rejects the complete recovery
before writes; a backup damaged after initial validation does too. Even explicit
`-AllowChangedFiles` permits the observed changed bytes, not a later concurrent
replacement. Five race fixtures reproduce these intervals using a temporary
installation. Transaction/sync/recovery/package checks pass 4/4 in 5.20 seconds
before the additional explicit-override race fixture, which also passes alone.

Newly deployed files are removed, and recorded new directories are removed only
when empty. Unrelated files in those folders are retained and reported as
`files_restored_directories_retained`. The new backup contains `recovery.json`
linking the original and recovery manifests. This command does not launch the
game or certify worn/runtime acceptance. A missing/damaged manifest or original
backup still requires manual investigation; interrupted operations cannot be
made atomic across machine failure.

## First installation from a built checkout

With the Darktide Mod Loader and Framework already installed, the explicit
`-InitializeInstall` switch permits creation of the VR mod directory tree and
appends its missing `darktidevr_stereo_probe` entry to `mods/mod_load_order.txt`.
It requires the game executable, loader, base manager, framework descriptor and
existing mod list. It does not install or activate the loader, install optional
Custom HUD, change other mod ordering, create a shortcut or launch the game.

From a built Windows checkout, use `tools/stereo/sync-darktide-vr-dev.ps1
-InitializeInstall -GameRoot <installation>` after the required default Ready
preflight and with Darktide closed. Source compilation, native build artifacts
and the ordinary shader build requirements still apply. This is a source-tree
installation path. The [standalone development package](RUNTIME-PACKAGE.md) now
stages the required built files and validation tools; public release and live
clean-install acceptance remain pending.

For a package prepared with precompiled production shader output, add
`-UsePrebuiltProductionShader` to sync or the ordinary start/launch scripts.
It requires `production-shader.json`, produced by the shader build, with the
production scale/spin/basis profile and matching shader/source SHA256 hashes.
Diagnostic, modified or stale outputs are rejected before installed writes.
The shader source remains in the package for identity validation. Ordinary
development sync continues to compile the production shader by default; the
prebuilt option avoids requiring DXC on the destination machine.
The app-local `dxcompiler.dll` reflection library is still required by native
shader-interface validation. The pinned runtime and its three notices are now
verified before writes and included in the same install/recovery transaction;
this is independent of the development compiler executable. Prepare source
checkouts with `tools/dependencies/get-dxc-runtime.ps1`. Runtime packages carry
the verified files and need no dependency download at the destination.

Readiness reports tolerate extracted source packages without Git. They mark
checkout identity unavailable, with unknown revision/dirty status, while still
requiring all normal Quest/VDXR/rendering checks. A package nested inside another
repository does not inherit that parent's revision. This removes a metadata-only
dependency; it does not supply a release package identity or relax readiness.

The existing list is retained byte-for-byte before its appended entry, including
comments and LF/CRLF style. Repeated installation does not duplicate the entry.
Ambiguous duplicates/capitalization and NUL or UTF-8 BOM files are rejected;
the stock loader reads byte lines and does not strip a BOM. New directories
are recorded in the backup manifest. On caught failure, only directories this
transaction created are removed, deepest first, and only if empty. Existing
directories and unrelated files are preserved. Ordinary sync retains its
existing-installation requirement.

## Validation, 8 September 2026

Windows PowerShell fixtures exercise real temporary filesystem writes and the
actual sync orchestration. A locked final destination forces a late failure
after earlier Lua, native and flag writes; the installed file set and hashes
must return exactly to their originals. Success, diagnostic removal, newly
created file/directory rollback, path/junction guards and Lua-gate rejection are covered.
Clean installation, missing prerequisites, final mod-list failure and repeated
installation are also exercised against an isolated fake installation.
Recovery fixtures cover mixed interrupted state, repeat restoration, changed
file rejection/explicit preservation, damaged backups, wrong-root rejection,
nonempty folder retention and rollback after a failed recovery write.
Process discovery and compilation are fixtures in the orchestration test; the
real project Lua gate runs separately in CTest. Nothing from these checks is
deployed to the running accepted-baseline preview session.

Run `ctest --test-dir build/windows-vs2022 -C Release --output-on-failure` with
the configured Windows build. Evidence is recorded in the current workday
handoff.
