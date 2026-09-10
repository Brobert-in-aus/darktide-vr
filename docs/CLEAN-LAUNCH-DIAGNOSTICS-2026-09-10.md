# Clean launch and debug-layer repeat

The corrected repeat **does not show a material debug-layer FPS penalty**.
The earlier attribution of the physical gap to debug validation is withdrawn.
Keep validation opt-in to make workloads explicit, not because this repeat proves
a speedup from disabling it.

## Matched controls

Same stationary cm_archives difficulty 3, 2496x2688 per eye, Quality DLSS, FG,
120 Hz/cap, world-space HUD and menu input enabled, preview off, precise polling,
FB244186 native, 216E3F76 viewer and CB8B5202 simulator. Each measurement follows
mission readiness for 60 seconds with ten seconds excluded as warm-up.

| Run | Distinct FPS | Foreground samples in measurement window | Interpretation |
|---|---:|---|---|
| Validation off A | 87.13 | 43 game, 3 Explorer, 3 viewer | Excluded: focus contamination |
| Validation on | 89.11 | 50 game | Accepted control |
| Validation off B | 88.43 | 50 game | Accepted control |
| Optional diagnostics cleaned, validation off | 88.55 | 49 game | No demonstrated FPS gain |

Foreground ownership was sampled approximately once per second. This excludes
observed alt-tabbing but does not prove absence of input or sub-second focus
changes. One valid pair cannot establish a precise sub-percent effect. All four
runs closed cleanly, report zero pose mismatches and restored files. The 112.68 FPS
older control omitted the accepted HUD/menu configuration; it is not the correct
baseline for attributing the debug-layer difference.

## Implemented cleanup

Normal `start-darktide-vr.ps1` launches now suppress these optional diagnostics
before the game starts, even when deployment sync is skipped:

| Diagnostic | Treatment |
|---|---|
| Resource handle allocation/release trace | Remove presence flag for the run; no allocation/release trace hooks or sparse stack/file samples |
| Streamline standalone copy probe | Remove stale flag unless explicitly requested |
| Streamline standalone transport probe | Remove stale flag unless explicitly requested |
| Body IK and weapon-pose traces | Write disabled for the run |
| GPU performance profile and pass trace | Disable unless explicitly requested by launch switches |

Five existing files were suppressed in the tested installation. The run's unique
resource-handle log was absent, confirming that trace did not start. Missing flags
are not created. Existing bytes are saved before mutation and restored in the
launcher's independent cleanup steps. `-PreserveDiagnosticFlags` on start or the
synthetic runner permits deliberate legacy diagnostic controls; it is not the
normal play path. Synthetic receipts record the requested cleanup policy.

The new helper is included in the runtime package file list. Explicit GPU profiling
still works through its existing launch switch; cleanup does not remove the
benchmark's presentation-thread or render-API profiler controls.

## Functional paths retained

- Stereo input capture, per-eye targets, target-token association, stereo
  swapchain/staging, continuous submission and NGX output publication. Despite
  their historical "probe" names, the current framegen path depends on them.
- World-space HUD, controller aim/gameplay input, body presentation, shared-shadow
  handling, the production billboard substitution and cluster-light visibility
  fix. These are functional behavior, not disposable diagnostic switches.
- Lua compilation, executable/build identity checks, readiness and failure logs.
  A clean launch must still fail visibly and preserve restoration evidence.

Inventory found the expensive diagnostic render-hook, vertex-shader dump and
cluster-trace flags absent; only the functional billboard and light-fix flags
were present in the native bin directory. They were not switched off.

## Remaining opportunities

The physical viewer's desktop fallback capture still runs every 33 ms during
stereo, and native/Lua/viewer status logging remains. These need narrowly scoped
on-demand capture and logging controls; deleting the capture option would also
remove startup/error fallback and window-lifetime handling. Their FPS cost is
unmeasured here. A dedicated HUD/menu GPU comparison is now more relevant than
blaming debug validation: adding the accepted configuration coincides with the
lower baseline, but HUD and menu contributions have not been isolated.

This is a cleaner launch configuration, not a claim that all development code
has been removed or that the mod is release-ready.

## Validation and evidence

`tools/stereo/test-clean-launch-diagnostics.ps1` passes: presence-gated removal,
text-gated disabling, exact-byte restoration, explicit diagnostic preservation and
unchanged functional HUD/FG flags. `ctest --test-dir build/xr-frame-stage-timing
-C Release --output-on-failure -R '^installed_lua_gates$'` passes 1/1. PowerShell
parser checks and `git diff --check` pass. No Lua code changed; normal installed
Lua compilation and runtime HUD/stereo gates passed in the live simulator trial.

Ignored evidence directories: `resolution-cause-clean-off-a-20260910`,
`resolution-cause-clean-debug-20260910`, `resolution-cause-clean-off-b-20260910`,
`resolution-cause-diagnostics-clean-20260910`; focus log `clean-debug-focus.csv`.
Both installed native DLL hashes are restored to FCCDD0DE; simulator runtime
restoration is owned by each completed matrix wrapper. No game/viewer remains.
