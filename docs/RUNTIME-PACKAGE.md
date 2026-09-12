# Release package

`tools/release/build-runtime-package.ps1` produces the archive that players
extract into the game folder. Since 12 September 2026 the archive is shaped
like the game folder: everything, the licence, notices, changelog, user
guide and a short README included, lives under
`mods/darktidevr_stereo_probe/`, so extraction adds nothing else. Extracting it
over the Darktide installation and running the mode switch inside the mod
folder is the whole installation; no PowerShell launcher, sync script or
readiness preflight ships with it.

What the package contains is listed in `tools/release/runtime-package-files.psd1`
as source/destination pairs plus every Lua module of the mod:

- the mod descriptor, all Lua chunks, and `Darktide VR Mode.bat` with
  `darktidevr-mode.ps1` and the executable patch tool under `tools/`;
- `bin/`: the `d3d12.dll` proxy (the mode switch copies it into
  `binaries`), `darktidevr_native_capture.dll`, the viewer
  `darktidevr-xr-harness.exe` with the OpenXR loader and its licence, the
  pinned DXC reflection runtime with its notices, the production billboard
  shader, and the two presence-gated bootstrap flags of the play
  configuration.

The packager runs the repository gates before staging (pinned DXC files, every
Lua chunk through the pinned LuaJIT, the production shader identity), records
the packaging checkout revision, writes `package-manifest.json` (schema 2,
`layout=game_folder`) with every file's size and SHA-256, verifies the staged
tree with `tools/release/test-runtime-package.ps1`, and zips the contents so
that extraction places `mods\darktidevr_stereo_probe` directly. Passing
`-ReleaseVersion 0.1.0-alpha.1` names the archive
`darktidevr-<version>-<head12>.zip` and marks it `release_candidate`;
without it the archive is a `development_candidate`.

## Component build records

The source revision identifies the packaging checkout, not the build source of
each copied binary. To bind the three project binaries to their build, pass
`-ComponentProvenancePath <json>` (and `-RequireComponentProvenance` to refuse
packaging without it). `tools/release/record-component-provenance.ps1` writes
that receipt from a clean checkout: per component a name, the full source
revision, `source_dirty=false`, the build command, toolchain, options and
dependencies, and the package-relative `path` and `sha256` of its outputs. The
verifier repeats the checks on the extracted package. The manifest labels this
`recorded_hash_matched_claims`: hashes bind the record to the files; they do
not prove that the commands produced them.

## Validation and acceptance

`tests/tooling/test-runtime-package.ps1` (CTest `runtime_package_integrity`)
exercises the verifier on a fixture: layout, provenance, changed, missing,
unlisted, stray and path-escape cases. Package validation does not establish
headset behaviour. The plain-launch acceptance of 12 September (Steam, Play,
viewer started by the game, stereo active in gameplay, generated frames
observed) was done on the development install; the clean-install rehearsal
from the package is recorded in the handoff for that date.

## Development install

Developers keep using `tools/stereo/sync-darktide-vr-dev.ps1`, which deploys
the same files from the build tree (including the mode switch and the viewer
into the mod folder) through a backed-up transaction, and the development
launcher for diagnostic runs. Neither is part of the package.
