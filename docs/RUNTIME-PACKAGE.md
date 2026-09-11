# Darktide VR development candidate

This package contains the current Lua modules, Windows x64 capture/bridge,
OpenXR loader, pinned Lua validator, production particle shader and ordinary
installation/launch/recovery tools. It is an offline-validated development
candidate, not a worn-accepted release. The manifest records every payload file's
hash and the source checkout revision/state. Hash checks detect changed files;
they are not a publisher signature or evidence of gameplay compatibility.

The source revision identifies the **packaging checkout**, not the build source
of every copied binary. Current manifests explicitly record
`source_revision_scope=packaging_checkout` and
`binary_source_provenance=not_recorded` by default. The packager copies existing native and
viewer artifacts; it does not rebuild them or establish which source produced
them. Legacy manifests without these fields have the same limitation. In
particular, the accepted mixed runtime uses separately based Lua, native and
viewer versions. Preserve their per-component handoff and hashes; a package's
checkout revision alone cannot reproduce or certify that accepted combination.

### Component build records

For an intentionally selected candidate, pass `-ComponentProvenancePath <json>`
and `-RequireComponentProvenance` to `build-runtime-package.ps1`. The JSON has
`schema_version: 1`, `kind: "component_build_records"` and a `components` array.
Each component contains a short `name`, full `source_revision`, boolean
`source_dirty: false`, and nonempty strings `build_command`, `toolchain`,
`build_options` and `dependencies`. Record exact tool/dependency versions and
build options, using portable commands without workstation paths or credentials.
Its `files` array lists package-relative `path` and `sha256` for each output.
Use separate components when source revisions differ.

The packager requires coverage of the native capture DLL, D3D12 bridge DLL and
viewer executable, rejects duplicates/unknown payloads or hash mismatches, and
embeds the receipt. Extracted-package validation repeats the checks. The manifest
labels this `recorded_hash_matched_claims`: hashes bind the supplied build records
to these files, but do not prove that the commands produced them. Capture records
during clean source builds; do not invent provenance for existing binaries.
Third-party binaries retain their separate pinned dependency checks. No receipt
changes the development-candidate status or substitutes for release acceptance.

Validation on 11 September: 12 isolated provenance cases and the package integrity
fixture pass in PowerShell 7 and Windows PowerShell 5.1. The latter exercises
legacy manifests, receipt validation, contradictory status and existing payload
and Lua/shader/dependency gates. No runtime archive was promoted or deployed.

## Prerequisites

- Windows x64 and the Microsoft Visual C++ x64 runtime. Windows Graphics Tools
  remains required for the current readiness validation and optional D3D12 debug
  layer; ordinary viewer launches now leave validation off. Use `-XrDebugLayer`
  on the launcher/start script (or `-DebugLayer` on the direct shared-eye runner)
  for an explicit validation run, separately from performance comparisons.
- Steam Darktide with the project's currently supported guarded executable
  preparation, plus the Darktide Mod Loader and Framework already installed.
  This package contains no game executable, loader patch or game content and
  does not prepare a different game version. The runner retains its exact hash guard.
- Virtual Desktop Streamer, VDXR, one authorized Quest and ADB available through
  the Android SDK platform-tools location or PATH.

Git, Visual Studio and the shader compiler are not needed on the destination.
Optional Custom HUD remains a separate dependency and is not included. Machine
settings, credentials, headset identifiers, logs and other development artifacts
are excluded. The package's `build/` folders are runtime payload paths, not a
requirement to compile the project on the destination.

The package includes a pinned x64 DXC reflection library and its upstream
notices. Native shader-interface validation needs this library even when the
production shader is prebuilt. Sync installs it beside the capture module in
the mod's `bin` directory through the same backup/rollback transaction. It does
not require a destination Windows SDK or compiler executable. Package and sync
checks reject a missing or modified pinned runtime file before deployment.

For source builds, prepare this dependency with
`tools/dependencies/get-dxc-runtime.ps1` before building the package or syncing.
The preparation tool checks Microsoft's published archive digest and extracts
only the runtime DLL and three notice files. Existing matching files are reused;
an existing damaged dependency is reported rather than silently overwritten.

## Validate, install and launch

Extract the complete folder to a writable location. In PowerShell, run
`tools/release/test-runtime-package.ps1` from that folder first. This verifies
file hashes, compiles all Lua chunks and checks the production shader identity;
it does not contact the headset or launch Darktide.

With Darktide and any previous VR bridge closed, run the default
`tools/unattended/invoke-unattended-preflight.ps1`. It must pass before deployment
or a new live session. Resume Virtual Desktop streaming and retry if passthrough
suspended it. Inventory mode does not certify readiness.
Inventory can report missing or ambiguous ADB devices without selecting one or
changing proximity behavior. Its device-selection status and query exit code
distinguish unavailable observation from Ready certification.
Multiple authorized connections are treated as one Quest only when all report
the same non-placeholder hardware identity and Quest model. The resolver prefers
the direct serial connection, without disconnecting network aliases. Different
devices or failed/conflicting identity queries still block Ready. Reports retain
the connection count and add physical Quest count and duplicate-resolution state;
hardware identifiers are not included. The proximity helper uses the same default
resolver, included in the runtime package.
Proximity apply/restore requires both a successful ADB exit and an explicit
`Broadcast completed: result=0` receipt. Missing/nonzero results are failures,
including during watcher cleanup. Status also rejects failed power queries.

Install with `tools/stereo/sync-darktide-vr-dev.ps1 -InitializeInstall
-UsePrebuiltProductionShader`. Launch with
`tools/stereo/launch-darktide-vr.ps1 -UsePrebuiltProductionShader`. Both discover
Steam's installation; add `-GameRoot <path>` if multiple copies require selection.
Use the prebuilt option on every package sync/launch. The package intentionally
does not include development shader compilation or synthetic experiment tools.

For a desktop shortcut, run `tools/stereo/install-darktide-vr-shortcut.ps1
-UsePrebuiltProductionShader`, with the same optional GameRoot. Normal launch
uses the authenticated Steam/Fatshark path. Restore normal proximity behavior
when the live development session ends with
`tools/quest/set-proximity-override.ps1 -Action Enable`, then `-Action Status`.

The updater stages and backs up installed files/flags before changing them. To
restore a saved update with the game closed, run
`tools/stereo/restore-darktide-vr-deployment.ps1 -Manifest <backup/manifest.json>`
after the required readiness preflight. Changed files are protected by default;
explicit `-AllowChangedFiles` preserves them in a new backup before restoration.
Keep backups and inspect any incomplete recovery report before another launch.

## Acceptance still required

Package validation does not establish fresh stereo initialization, nonzero
shared_ready, worn hand/preview alignment, authoritative damage, stable mission
transitions or sustained performance. The focused headset deployment is a
separate accepted-baseline candidate; this package does not replace it during
offline verification. Physical melee remains paused. Billboarding and the
reported pickup-popup edge-sizing disagreement remain active visual work.
