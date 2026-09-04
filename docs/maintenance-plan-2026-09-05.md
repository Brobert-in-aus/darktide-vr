# Repository review implementation

Baseline: `ff0fa83`. Work branch: `codex/repository-review-fixes`.

## Execution order

1. Isolate transport tests, bind billboard identity to object lifetime, handle
   one-pixel crops, and protect temporary launch state from setup failures.
2. Separate readiness inventory from enforced XR preflight. Compile every Lua
   chunk with a pinned LuaJIT; retain legacy source assertions as a separate
   regression check while behavior tests replace them incrementally.
3. Move the viewer implementation into `src/xr`, preserving executable paths
   for existing launchers. Extract focused native/Lua functionality, remove
   confirmed unreachable code, and make the unused winmm experiment opt-in.
4. Make `docs/CURRENT-STATUS.md` authoritative for current behavior and pending
   acceptance. Label chronological feasibility documents as historical and
   replace duplicated workstation rules with infrastructure links.
5. Build Release with warnings as errors; run isolated tests and script/compiler
   regressions. Record exact commands and results here. A source/build pass is
   not headset acceptance of hands, lighting, markers, or stereo deployment.

## Scope boundaries

Retain historical evidence and experimental sources with explicit labels.
Split monoliths along tested boundaries rather than rewrite their behavior.
Further extraction and replacement of legacy textual assertions can proceed
incrementally; existing visual acceptance gaps remain visible in current status.

## Validation

Initial readiness: one Quest, proximity Disable/Status, Virtual Desktop Streamer
and VDXR available; Debug harness rendered 120/120 synthetic projection frames.
Implemented:

- All six core shared-memory transports support private PID-scoped test names.
  Test executables opt in before any writer or native DLL loads. The native
  projection event is isolated too; CTest compositor fixtures opt in explicitly.
  A child-process regression verifies that another test cannot reset its parent.
- Billboard identity uses COM private data instead of a permanent address set.
  The extracted buffer registry removes records when GPU objects release their
  private lifetime observers. It holds no GPU-owner references.
- One-pixel pointer crops normalize to the panel centre. Psykhanium arming now
  happens inside cleanup protection, after fallible cache preparation.
- Ready preflight checks Streamer, the installed VDXR manifest, ADB power success,
  awake/display-held state, and actual rendering. Inventory is explicitly
  non-certifying. The smoke uses Release by default and handles the loader's
  expected API-version fallback on stderr under Windows PowerShell.
- Every mod chunk and descriptor compiles through the pinned LuaJIT validator;
  the executable hash and source revision are recorded locally. Legacy textual
  assertions are a separate CTest regression, no longer a deployment dependency.
- Runtime source moved to src/xr and generated-frame consumer to tools; output
  paths remain compatible. Projection math and native object lifetime/registry
  responsibilities have dedicated modules. Dead hands-only code and an unused
  Lua local were removed. The obsolete winmm bootstrap is opt-in.
- Working agreements and current documentation now separate offline work, live
  readiness, historical evidence, and pending worn acceptance.

Commands used (from the repository root, CMake/CTest from VS2022's bundled bin
when they are not on PATH):

```powershell
tools/lua/build-luajit.ps1
cmake --preset windows-vs2022 -DDARKTIDEVR_ENABLE_HEADSET_TESTS=OFF
cmake --build build/windows-vs2022 --config Release -- /m /p:TreatWarningsAsErrors=true
ctest --test-dir build/windows-vs2022 -C Release -j 4 --output-on-failure
powershell -NoProfile -ExecutionPolicy Bypass -File tools/unattended/invoke-unattended-preflight.ps1 -XrFrames 120 -OutputPath artifacts/unattended/review-fixes-preflight.json
git diff --check
```

Release build passed with project warnings as errors. All 44 CTests passed.
PowerShell parsing passed for 64 scripts; Python AST parsing passed for 17 files;
local Markdown target checks found no missing files. LuaJIT compiled all 11 mod
chunks/descriptors. Its negative fixture rejects 201 indented active locals.
Upstream LuaJIT's own build reports several MSVC warnings; it is built by its
upstream build script, separately from the warning-clean project build.

The first full suite exposed two Windows PowerShell hashing-wrapper failures;
using a scoped .NET SHA256 helper fixed them. A rendering-preflight attempt
that overlapped compositor smoke tests failed; the sequential retry passed
120/120 frames with no unrendered frames and no VD restart. Keep live preflight
separate from compositor tests. The successful report is ignored local evidence.

No Darktide deployment or game launch was performed for this maintenance change.
Fresh game initialization, shared_ready, and the worn checks in CURRENT-STATUS
remain the next deployment gate. No Mac-only validation applies. Further module
extraction and conversion of the remaining legacy assertions to behavior tests
are incremental maintenance, not claims of completed visual acceptance.

Final targeted checks after test-directory organization and the buffer-registry
regression also passed:

```powershell
cmake --build build/windows-vs2022 --config Release --target darktidevr-native-capture-tests -- /p:TreatWarningsAsErrors=true
ctest --test-dir build/windows-vs2022 -C Release -R '^native_capture_hooks$' --output-on-failure
ctest --test-dir build/windows-vs2022 -C Release -R '^(validate-xr-readiness|lua_source_compile|lua_source_invariants|luajit_compiler_contract|projection_math|gpu_trace_analysis)$' --output-on-failure
```

The buffer regression checks repeated registration and destruction without
retaining GPU allocations. Source moves were recognized by Git as renames.


## Continued offline review

Extracted menu widget geometry, hotspot enumeration and slider drag state into
`darktidevr_menu_widgets.lua`. Fixed hidden hotspots reappearing through fallback
enumeration (including dropdown options), cleared stale force flags even after
options become hidden, and rejected zero-sized pointer source extents before
normalization. Added executable Lua regressions covering visibility callbacks,
authored and fallback options, hidden-state cleanup, aligned geometry, slider
step rounding, missing samples and explicit release.

Reconfigured the Windows preset and ran the complete Release CTest suite:
45/45 passed. The pinned compiler accepted all 12 mod chunks/descriptors and
legacy source invariants passed. No native source changed in this continuation.

Live readiness was attempted twice sequentially. VDXR created an instance but
reported `openxr.system=hmd-unavailable`; no deployment or game launch followed.
Preflight now preserves full smoke output in its JSON report and writes
`readiness_verified: false` before returning a failure. The second attempt
verified this failure-reporting path against the actual unavailable runtime.
Evidence: ignored `artifacts/unattended/review-continuation-preflight.json` and
`.log`. Normal proximity automation was restored after the attempts.

The next actionable gate requires resuming the Quest Virtual Desktop connection,
then rerunning Ready preflight, starting with `-EnterPsykhanium`, and checking
fresh Lua initialization and nonzero `shared_ready`. Worn acceptance remains as
listed in CURRENT-STATUS. Additional broad renderer rewrites are deferred until
this maintained baseline has live validation; they are not prerequisites for
these concrete fixes.
