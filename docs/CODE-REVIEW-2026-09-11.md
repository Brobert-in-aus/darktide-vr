# Whole-project code review, 11 September 2026

Read-only review requested by the user as a fresh set of eyes. Eleven parallel
reviewers covered src/core and src/bridge, the producer in three slices plus
its helper sources, the viewer, the Lua mod in three slices, the PowerShell
tooling and the Python/packaging/CMake layer. Findings marked **verified** were
re-checked against the source or reproduced by me; the rest carry the
reviewer's stated confidence. No source was modified by this review; the one
defect fixed today (capture worker shutdown) is recorded in
[SIMULATOR-WINDOW-CAPTURE-2026-09-11.md](SIMULATOR-WINDOW-CAPTURE-2026-09-11.md).

## Highest-value findings

| # | Severity | Area | Defect | Status |
| --- | --- | --- | --- | --- |
| 1 | high (diagnostic builds) | `src/producer/native_capture.cpp:14016-14022` | PIX marker hooks use command-list vtable slots 55/56/57, which are SetPredication/SetMarker/BeginEvent; SetMarker, BeginEvent and EndEvent are 56/57/58. EndEvent is never hooked, `SetPredication` is routed into the marker logger (dereferences a buffer offset as a string pointer), and BeginEvent is forwarded through a one-argument trampoline. Only active with the diagnostic render hooks or the cluster-trace flag, so every cluster-trace capture to date was mis-hooked. | verified against `d3d12.h` 10.0.26100 |
| 2 | high (fixed today) | `src/xr/capture_worker.h` | Enabled capture worker ignored the stop request; viewer hung on join when the game window closed during flat capture. | fixed in `5b058cc` |
| 3 | medium | `src/xr/main.cpp:2465-2478, 3941-3959` | Shared-menu copy and gameplay-reticle quad use `flat_swapchain`/`flat_resource`, which exist only with `--capture-window-title`. A `--shared-eyes` run without a capture title that enters mode 3 or 4 (menus) with the menu texture attached submits a null resource barrier and a null swapchain. Today's simulator runs saw only modes 1, 2 and 5, so it is latent for the benchmark and unreachable for the physical launcher, which always passes a title. | verified (guard absent; not exercised) |
| 4 | medium | `darktidevr_stereo_probe.lua:3997-4067` with hooks at `:12730` and `:12782` | `apply_ui_eye_offsets` reads the unit pose as the clean base and writes the left-eye pose back. It runs after stock `_update_camera` (which resets the unit) and again in the `ScriptWorld.render` hook, so the second call composes head rotation and translation onto an already-offset pose. With no `_camera_animation_data` nothing resets the unit at all. Affects UI stereo worlds only (character select, vendor scenes). | plausible; needs a worn check of menu-world head rotation |
| 5 | medium | `darktidevr_stereo_probe.lua:10048` | `presentation.hub_first_person_requested` opens and reads a flag file on every call; it is the first term in the `_update_first_person_mode` hook, which stock calls from both fixed and per-frame update for every player unit. | verified |
| 6 | medium | `darktidevr_stereo_probe.lua:12508-12566, 12843-12856` | `world_marker_reprojecting` is set before the right-eye marker replay and cleared only on success; the caller's `pcall` disables reprojection but leaves the flag stuck, so marker scale easing stops and later normal draws take the replay path for the rest of the session. | verified |
| 7 | medium | `darktidevr_weapon_assist.lua:15-17` | `flag:read(32):match(...)` at module load throws on an empty `darktidevr_aim_assist_light.flag`, aborting the remainder of the main script (two-hand, grenade aim, marker GUI and later installs never run). | verified |
| 8 | medium | `darktidevr_calibration.lua:113-126` | Head samples are `{x, z, y}` of the raw OpenXR head pose while grip samples are already Darktide Z-up body-basis poses (`shared_controller_state.h:32`), so the forward axis sign differs between head and hands; reach and arm-length calibration inherit the error. | verified |
| 9 | medium | `native_capture.cpp:6868-6869, 7019` | `billboard_shadow_constant_cursor`/`descriptor_cursor` only ever increment; once the 131072 slots are consumed the horizon-lock basis patch silently fails. Feature-gated to the experimental horizon lock. | verified |
| 10 | medium | `native_capture.cpp:9224-9525` | `resource_barrier_hook` is installed unconditionally and, per transition of an eye-sized texture that is not a known final, calls `GetDesc` and an uncached `GetPrivateData` name lookup under a global mutex. Always-on per-frame cost on the production path. | verified install; cost plausible |
| 11 | medium | `tools/stereo/start-darktide-vr.ps1:974` and 15 sibling restores | `Get-Content -Raw` on an empty flag returns `$null` in PowerShell 5.1, so `.Trim()` throws under StrictMode and the flag stays `enabled`; restores are also not byte-exact. | reproduced in 5.1 |
| 12 | medium | `run-synthetic-framegen-benchmark.ps1:336` | `*> launch.log` writes UTF-16 under PowerShell 5.1; `analyze-synthetic-gpu-load.py:70` and `summarize-synthetic-gpu-stages.py:53` read it as UTF-8 and fail. Today's runs were driven from 5.1, so their launch logs are UTF-16; the frame-rate analyzer reads only `consumer.log` and is unaffected. | verified on today's artifacts |
| 13 | medium | `install-darktide-vr-shortcut.ps1:171,197` | A trailing backslash on `-GameRoot` produces `\"` in the shortcut command line, which powershell.exe parses as an escaped quote; the launcher then receives a corrupted root and loses the following switch. | reproduced by reviewer |
| 14 | medium | `set-skinner-assert-patch.ps1:315` | `[Convert]::ToHexString` does not exist in .NET Framework, so every action fails under 5.1, including the only restore path for a patched executable. | reproduced by reviewer |
| 15 | medium | `tests/tooling`, `tests/native_capture` | Seven Python test suites and `darktidevr-billboard-equivalence-tests` are built or present but never registered with CTest, so regressions in the GPU-stage and billboard analyzers pass a full test run. | verified by reviewer |

## Other findings by area

### src/core and src/bridge (all low)

- `pose_snapshot.cpp:34-47, 54-74`: the seqlock stores the odd epoch with release and then the fields relaxed; the compiler may hoist field stores above the epoch store, and the reader's second load does not fence the preceding relaxed loads. Needs release/acquire fences. No non-test producer today. Verified.
- `shared_head_pose.cpp:288-304`: the producer's process-wide reader is opened lazily from both the Lua and render threads without synchronization (leaked mapping on a race).
- `shared_head_pose.cpp:373-395`: `publish_rendered_pair` is reachable from two threads with a single-writer seqlock.
- Writer restarts reset every transport epoch to 1, allowing a narrow ABA window across writer sessions; the XR writer constructor also zeroes Darktide-owned generation counters, which can drop a concurrent Lua commit.
- `panel_pointer.cpp:36-39`: `math::inverse` throws on a zero-length orientation; callers rely on upstream finiteness checks, which do not check length. Verified.
- `pose_snapshot.cpp:29-30`: a source that restarts its sequence counter is rejected forever; `source_id` is never consulted.
- `menu_pointer_input.cpp:92-101`: a trigger pressed off-panel and swept onto a button emits a click.

### Producer (native_capture.cpp and helpers)

- Medium: every unique vertex shader is reflected through DXC at PSO creation under a global mutex in production (`4130-4184`), because `kStockMenuDirectRenderEnabled` forces the PSO hooks on; this serializes the engine's parallel PSO compilation.
- Medium: `reset_eye_surface_resources`/`reset_menu_surface_resources` (`14064-14117`) release allocators and surfaces that may still be executing when the eye extent or menu description changes; no fence wait precedes the reset.
- Medium: `menu_draw_scope_depth` (`748`) is `thread_local` but written from the Lua export and read in D3D12 draw hooks on the render thread.
- Medium: `install_hooks` (`13451-14045`) leaks partial MinHook state on failure so `dtvr_install` can never retry, skips window cleanup on early returns, and has an unsynchronized `hooks_installed` check-then-act.
- Low: `game_swapchain` is published before buffer enumeration is validated (`12597-12651`); the transport probe slot sticks forever after a `Signal` failure (`12247-12261`); a result-36 rejection of eye 1 pairs a stale eye 0 with the next eye 1 (`14857-14875`); `capture_present_halves` creates an allocator per Present (`15164-15189`); the GPU eye profiler starts and resolves timestamps on possibly different queues (`1761-1851`); several `Signal`-failure paths release allocators with GPU work in flight; the pipeline-stream parser stops at unknown subobject types (`4637-4833`); `pso_metadata` and friends are insert-only (ComPtr leak per world-UI alpha PSO); unconditional creation of resize/menu diagnostic logs in `%TEMP%`; execute-command-lists arming consumes only the first matching list per batch (`10787-10895`); the original ring signals `ready` before publishing metadata (`native_original_ring.cpp:191-194`), the reverse of the documented order that the generated path follows; `first_device` handoff into the init-once callback is unsynchronized (`d3d12_bootstrap.cpp:284-296`); `StreamlineContinuousSubmission::pose()/inputs()` divide by `count_` before initialization.

### Viewer (src/xr)

- Medium: original-ring attach (`main.cpp:2180-2197`) dereferences `cached_eye_resources[0]`, allocated only under `--shared-eyes`; a capture-only theatre run with a publishing producer crashes.
- Medium: the theatre loop never reacts to `STOPPING`/`EXITING`/`LOSS_PENDING`; a runtime-initiated exit ends as an exception without `lifecycle=stopped`, so the benchmark scores it unclean (`1972-2004, 4839-4864`).
- Medium: `--stereo-tb` with `--shared-eyes` is accepted and produces contradictory swapchain geometry and a halved aspect ratio (`692-718`).
- Medium: `tracked_cuff_renderer.cpp:147-148` culls back faces with clockwise front faces while the mesh test enforces counter-clockwise outward winding; hidden today only by disabled depth and two-sided shading. Its renderer test asserts only a bounded non-empty blob and cannot catch matrix errors.
- Medium: `menu_input_injector.cpp:42-49` requires exactly one substring title match with no exact-title fallback, unlike `WindowCapture`; any second window with "darktide" in its title silently disables menu input.
- Low: torn `std::cout` lines from the capture worker thread can abort the analyzer; `submitted_frames` counts frames without layers so `--require-rendering` cannot fail in stereo modes; the end-of-loop injector flush bypasses the `enable_menu_input` gate; `presentation_state.crop_*` is used unvalidated as a copy box; usage text omits options and several flags silently do nothing without an XR loop; `ui_projection_layer.cpp:73-76` leaves an acquired image unreleased on wait failure; crop and pointer atomics can disagree for a frame.

### Lua mod

- Medium: per-frame allocation in `reconcile_fullscreen_views`, `apply_head_tracking` (two frustum tables plus a closure per call), `calibrated_character_scale` (a `pcall` closure and `require` per call, four or more times per frame), and the body-IK path (dozens of tables and boxes per frame behind the IK flags).
- Medium: `if ui_native_capture.dtvr_x then` guards on an FFI namespace cannot be false; they throw on an older DLL (`:1171` and seven siblings).
- Medium: `refresh_xr_render_extent` (`:2566-2578`) lets NaN through its range check and into every projection.
- Medium: `scan_body_rig` is called with `nil` fixed frame from `apply_body_ik`, bypassing its 60-frame throttle (flag-gated).
- Medium: `darktidevr_hud_panel.lua:1010-1019` builds `Quaternion.look` from a head-tracked forward that can be parallel to up, and `follow_pose` has no finite guard, so the HUD can go NaN until rebuilt; the editor cursor math assumes a 16:9 canvas (`:332-344`); `panel_aspect` can be stored as `0` before the zero-width return (`:1031`).
- Low: `active` is set before projection activation succeeds (`:3832`); `ui_eye_separation` diagnostic override is reverted every frame (`:2958`); two head reads per `update_stereo` can straddle a write; stale LOD camera handles after teardown; a retired orientation extension held strongly; about fifteen flag-file opens per second across independent pollers; the main chunk sits near 175 active locals of the 200 limit; `Bindings.install` runs twice; the `UIManager.open_view` hook mutates shared view settings without restore; `begin_pass`/`end_pass` state leaks on a re-raised draw error; body heading and hand anatomy are not reset on unit or mission change; calibration event registration survives a mod reload.

### PowerShell tooling

- Medium: the benchmark sets `XR_RUNTIME_JSON` process-wide before a `steam://` launch; if Steam is not already running it inherits the simulator runtime for its lifetime (`run-synthetic-framegen-benchmark.ps1:237-240`).
- Low-medium: the simulator `settings.json` is written with a BOM but re-read without stripping it, so a run killed mid-way breaks every later run until hand-edited (`:225, 236`).
- Low: `set-darktide-windowed.ps1` and `set-eye-sized-resolution.ps1` rewrite CRLF lines as LF on every launch; `set-vr-render-settings.ps1 -Action Restore` copies a possibly months-old snapshot over the live config; positional `-Path` with bracketed library paths fails `Get-FileHash`; `watch-quest-online.ps1` turns adb stderr into terminating errors; the start-character flag is overwritten without backup.

### Python, packaging and tests

- Medium: test residue accumulates on disk (about 1 GB under `artifacts/unattended/pipeline-probe-tests`, 22 bootstrap-selection trees, 164 `ui-readback-test-*` directories under `build/`, long-path trees in `%TEMP%`).
- Low: `summarize-synthetic-gpu-stages.py` silently drops rows whose extent differs from the configuration; several negative-case test helpers accept any exception; `menu_pointer_state` and a few `src/xr` targets lack the shared warning and Windows definitions; SDK/LuaJIT/feature-level-12 dependent tests fail rather than skip; the package verifier takes its file list and gate scripts from inside the package; `-Filter '*.lua'` can match 8.3 short names; `Compress-Archive` under 5.1 writes backslash entry names and a BOM manifest.

## Areas reported clean

Writer/reader layout parity and seqlock protocol on all shared transports; the
OpenXR↔Darktide basis change and projection math; D3D12 barrier pairing and
cross-queue fence ordering in the eye, menu, mirror and ring paths; Streamline
2.7.30 and NGX ABI layouts against the SDK headers; every other command-list,
device and swapchain vtable index; log-line formats versus the Python parsers;
the deployment transaction's backup-before-write and hash-keyed rollback; the
Lua compile gate's propagation through sync, launch, preflight and packaging;
process ownership in the launcher and readiness scripts; hook signatures of all
Lua hooks against the vendored game source; cross-frame boxing of engine
temporaries; LuaJIT local counts inside individual functions.

## Code quality, structure and repository hygiene

Measured on the working tree at `f37b4be` with the untracked review document.

### Size and shape

| Measure | Value | Note |
| --- | ---: | --- |
| Tracked files | 912 | 206 md, 187 lua, 136 cpp, 130 ps1, 98 h, 77 py |
| `src/producer/native_capture.cpp` | 17,224 lines | one translation unit, 228 file-scope atomics/mutexes, 167 exported or extern "C" symbols, 364 comment lines (about 2%) |
| `src/xr/main.cpp` | 5,696 lines | `run_theatre_lifecycle` is one function spanning most of the file with about 30 parameters; `wmain` is 366 lines |
| `darktidevr_stereo_probe.lua` | 13,555 lines | 56 hooks, 69 sibling modules, main chunk near 175 of 200 active locals; largest functions 455 and 379 lines |
| `install_hooks` | 595 lines | one expression of chained `MH_CreateHook` calls; the slot defect above hid inside it |
| Longest PowerShell | 1,288 / 1,106 / 1,064 lines | `start-darktide-vr.ps1`, `read-streamline-probe.ps1`, `test-darktide-lua-invariants.ps1` |
| CMake | 34 lists, 102 targets, 223 CTest entries | plus seven unregistered Python suites |
| Flag files read at runtime | 63 distinct names | discovered by grep; no single registry or schema |
| Docs | 156 files in `docs/` root, 52 dated notes below it, 4.4 MB | 29 root files carry dates in their names; no index beyond README |
| Branches | 555 local, 543 remote | one branch per task with no pruning |

### Formatting

- **No formatter or linter configuration** is present: no `.clang-format`, `.editorconfig`, StyLua, luacheck, PSScriptAnalyzer settings or Python linter config. `.gitattributes` only marks PDFs binary.
- **Line endings are inconsistent.** 95 tracked text files mix CRLF and LF within one file (23 cpp, 12 h, 15 lua, 23 md, 10 ps1), including `native_capture.cpp` and `start-darktide-vr.ps1`. The working copy relies on `core.autocrlf=true`, so every edit tool that writes LF triggers "will be replaced" warnings and diff noise. A `* text=auto eol=crlf` (or `eol=lf`) attribute plus one normalising commit would settle it.
- **Indentation mixes two and four spaces** inside the same C++ files (`native_capture.cpp` has 4,163 two-space and 3,326 four-space indented lines) because deeply nested blocks were written at different times. No tabs, no trailing whitespace.
- Long lines are rare in C++ (under 1%) but common in the benchmark runner (82 of 534 lines exceed 100 characters) and the throwaway wrappers.

### Structure

- The producer is a single 17k-line file holding hooks, diagnostics, probes, logging, capture, mirror, Streamline integration and Lua exports together. The helper sources split out later (`native_original_ring.cpp`, `generated_stereo.cpp`, probes) show the workable pattern; most of the file has not followed. Global mutable state (228 atomics and mutexes) is what forces the thread-safety questions in the findings above.
- Diagnostic code is compiled into production and gated by runtime flags rather than separated. Nine `write_*_log` functions and six `GetPrivateProfileIntW` readers each parse their own flag; the 63 flag names have no shared registry, so the Lua side polls files at about fifteen opens per second across independent pollers.
- `run-synthetic-framegen-benchmark.ps1` repeats the `Offline dual-view benchmark started; log=` extraction five times; `start-darktide-vr.ps1` carries 52 `FlagOriginal` save/restore sites written by hand, which is where the empty-flag restore defect lives. A single flag save/restore helper would remove both the duplication and the defect class.
- The viewer's `run_theatre_lifecycle` accumulates every feature as another parameter and another block in the frame loop; today's capture change added two more parameters. An options struct and per-feature helpers would make the loop reviewable.
- Tests are numerous (223 entries) and mostly genuine, but the per-topic PowerShell tests write into `artifacts/unattended` and the build tree without cleanup (about 1 GB accumulated), and several negative tests accept any exception.
- Documentation is thorough but flat: 156 notes in one directory with dated and undated names mixed, several superseded documents still linked as current, and evidence-of-the-day notes alongside contracts. Handovers say what supersedes what, but a reader needs the README chain to find the current entry point.

### Repository hygiene

- `.git` is 11.55 GiB of loose objects against a 9.25 MiB pack. Forty-one loose blobs exceed 50 MB (largest 280 MB); a sampled one is unreachable from any ref, so these are staged-then-reset build or capture artifacts. `git gc --prune=now` after confirming no reflog entry is wanted would reclaim roughly 10 GB. A stray `.git/objects/73/tmp_obj_*` file is also present.
- `git worktree list` showed 21 entries at the start of the day whose directories no longer exist; git has since pruned them, but the branches remain.
- 555 local branches with no merges to `main` (which holds one bootstrap commit) mean the branch list is the only history of what was integrated. Tagging accepted revisions or merging closed tasks would give `main` meaning.
- No CI configuration exists; the build, CTest and Lua gate run only on this workstation by hand.

### Assessment

The engineering discipline around evidence, restoration and hashes is strong,
and the defensive style in the helper sources is good. The quality risk is
concentration: three files carry most of the logic and most of the global
state, diagnostics are interleaved with production paths, and there is no
mechanical formatting or line-ending enforcement. None of this blocks the
alpha, but each of the confirmed defects above sits in one of those three
files, and the review effort scaled with their size rather than with the
project's actual complexity.

## Status after the fix pass, 11 September

Worked through on branch `codex/simulator-window-capture-policy-2026-09-11`.
Validation: Windows x64 Release build of every target in
`build/focused-simulator-window-capture`, then the full offline CTest suite
(headset smokes excluded): **234 of 234 pass**, including the seven newly
registered Python suites (one guarded on capstone). The Lua compile gate passes
(70 chunks). No installed game file, accepted binary or physical setting was
touched. Logs: ignored `artifacts/unattended/review-fixes-build*-20260911.log`.

Fixed:

- Top table: #1 marker slots, #2 (earlier today), #3 flat-swapchain guards plus
  the ring attach gate, #5 first-person flag throttle, #6 marker flag reset,
  #7 empty-flag guard, #8 calibration head basis, #9 shadow-slot rings, #11
  byte-exact flag restores through an overridable `Restore-FlagOriginal`
  helper, #12 UTF-8 launch log plus BOM-aware Python readers, #13 shortcut
  trailing separator, #14 hex helper for 5.1, #15 suites registered.
- Core: seqlock fences, panel-pointer orientation validation, reader open
  mutex. Producer: ring metadata before ready signal, continuous-submission
  accessors, bootstrap device handoff through the init-once parameter.
  Viewer: runtime-initiated session exit, `--stereo-tb`/`--shared-eyes`
  exclusion, cuff front-face winding, injector exact-title fallback, UI layer
  acquire ownership. Lua: FFI export guards, NaN extent check, rig-inventory
  throttle, HUD level rotation and aspect ordering. Tooling: simulator
  settings BOM, environment restored before the Steam launch, `-LiteralPath`
  in the runner, CRLF-safe settings regexes, Quest watcher stderr handling.
- Tests and hygiene: cleanup in the residue-producing tests, about 2 GB of
  residue removed, `.gitattributes` end-of-line rules with one normalising
  commit, `.editorconfig`, `.clang-format`, `docs/README.md` index, and the
  repository garbage-collected from 11.55 GiB of loose objects to a 6 MB pack.
- Three pre-existing test failures found and fixed on the way: the two
  launcher tests had drifted from the launcher (new `-XrDebugLayer` switch and
  the dot-sourced clean-launch restore), and the Lua invariant still required
  strings that `7dfa753` moved into `enhanced_barrier_interest.h`. The HUD
  test's vector stub gained `x/y/z` fields.

Not done, deliberately:

- #4 UI eye-offset double application needs a worn observation before any
  change; #10 barrier-hook name lookups need a cached-name design; the
  production DXC reflection, `thread_local` menu scope depth, resource reset
  without fence wait, and `install_hooks` failure cleanup are engine-facing
  changes that need their own focused trials rather than a review pass.
- Structural items (extracting diagnostics from `native_capture.cpp`, a viewer
  options struct) remain as listed; the formatter configuration applies to
  touched code and no wholesale reformat was made.

## Suggested order of work

1. Fix the marker hook slots (#1) and re-run any cluster-trace evidence that
   relied on marker labels.
2. Guard the viewer's flat-swapchain paths (#3) and the ring attach without
   shared eyes; both are one-line null checks with a log line.
3. Move the first-person flag read (#5) to the existing throttled pollers, clear
   the reprojection flag in the error path (#6), guard the empty flag read (#7)
   and convert the calibration head sample to the body basis (#8).
4. Obtain a worn observation of menu-world head rotation to settle #4.
5. Tooling: make flag restores byte-exact (#11), write `launch.log` as UTF-8 or
   read it BOM-aware (#12), and register the orphaned test suites (#15).
6. Hygiene, low effort and high return: add `.gitattributes` end-of-line rules
   and a `.clang-format`/`.editorconfig`, normalise the 95 mixed-ending files in
   one commit, reclaim the unreachable loose objects, add test cleanup, and
   start a `docs/README.md` index that names the current entry points.
7. Structure, incremental: extract diagnostics and flag parsing from
   `native_capture.cpp` into the helper pattern already used by the ring and
   probes; replace the viewer's parameter list with an options struct; give
   the launcher one flag save/restore helper.
