# Fresh-session handoff — 2026-09-01

This is the entry point for the next Codex session. Read `AGENTS.md`, this file,
and [`../phase1/todo-2026-09-01.md`](../phase1/todo-2026-09-01.md) before
changing or launching anything. The full evidence trail for the preceding day
is in
[`2026-08-31-development-session.md`](2026-08-31-development-session.md).

## Repository and process state

- Workspace: `D:\Projects\games-xr\Warhammer 40k Darktide VR`
- Branch: `phase0/feasibility-bootstrap`
- HEAD at handoff: `3ce27e5` (`Add configurable VR movement reference`)
- Darktide, its launcher and the XR harness were all closed at handoff.
- No commit was requested after the 2026-08-31 work. The modified files form
  one intentional, uncommitted development batch. **Do not reset, checkout,
  clean, stash over, or otherwise discard the working tree.**
- `git diff --check` passes; Git reports only the repository's existing
  LF-to-CRLF warnings.

Intentional modified files:

```text
docs/handoffs/2026-08-31-development-session.md
docs/phase1/README.md
mods/darktidevr_stereo_probe/darktidevr_stereo_probe.mod
mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_controller_aim.lua
mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_hud_panel.lua
mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_stereo_probe.lua
tests/xr_harness/main.cpp
tests/xr_harness/window_capture.cpp
tests/xr_harness/window_capture_tests.cpp
tools/stereo/advance-darktide-to-hub.ps1
tools/stereo/run-darktide-shared-eyes.ps1
tools/stereo/start-darktide-vr.ps1
tools/stereo/sync-darktide-vr-dev.ps1
tools/stereo/test-darktide-lua-source.ps1
```

Intentional project files not yet tracked:

```text
docs/phase1/todo-2026-09-01.md
tools/stereo/analyze-billboard-shaders.py
tools/stereo/set-full-body-experimental.ps1
```

`Codex Image 25 Aug 2026, 08_53_34.jpg` is an unrelated user-owned untracked
file. Preserve it and do not add it to a project commit without explicit user
direction.

## Non-negotiable product and development contracts

- True stereo is the target. AER remains only a fallback after proper stereo
  has been exhausted.
- The desktop is strictly a crop/scale of one submitted eye. It must never be
  an independently rendered menu, shop or gameplay surface.
- Normal mod operation must enter XR from the splash screen. An OpenXR session
  with a flat fallback is a failure, not a pass.
- Authenticated tests use Steam -> Fatshark launcher. The start script owns the
  guarded launcher Play click; direct executable launch is not the production
  path.
- Wait at least 10 seconds after Darktide closes before launching it again so
  Steam observes the terminated process.
- Tests remain private/offline and do not interact with other players.
- Virtual Desktop supplies the desired eye resolution. Do not reintroduce a
  hardcoded eye resolution merely to match the desktop window.
- The desktop window and its physical size must not control eye resolution.
- Menus/HUD eventually belong on spatial panels while stereo world rendering
  continues. Loading/splash panels use their source aspect ratio rather than a
  forced square.
- Right hand owns aiming, including attacks authored from the left hand or the
  staff tip. Those attacks keep their real origin but converge on the same
  right-hand-selected world point.
- Movement supports headset-relative and left-hand-relative modes; the release
  default remains headset-relative.
- Non-Ogryn IPD comes from the headset. Ogryn scaling and full avatar IK are
  post-launch work.

## Current launch embodiment decision

Full third-person body presentation is post-first-launch and is disabled by
default. The distorted perspective-authored first-person rig is also rejected.
The launch target is:

1. independent tracked left and right hand proxies;
2. gloves plus preferably bracers/short forearms;
3. the currently wielded item; and
4. no visible torso, upper arms or head.

The current intermediate implementation is not sufficient. It drives visible
3P wrist nodes on a hidden body skeleton. Consequently, the hands cannot travel
beyond the avatar arm chain's reach. The closing worn test showed only bare
hands plus weapons—no gloves, sleeves, bracers or forearms. A shape filter over
the current Psyker upper-body cosmetic was tested and reverted because the two
candidate children are indivisible shoulder-to-hand meshes and exposed whole
arms.

The next implementation must create controller-owned visual proxies rooted
directly at the OpenXR tracked poses after calibrated offsets. The hidden body
may supply gameplay state, but it must not constrain or own the visible wrist
transform. Preserve weapon attachment and common-target convergence. Validate
over-reach, cross-body travel, full hand roll, tracking loss and reacquisition
synthetically before asking for another worn test.

Relevant code ownership:

- main presentation/visibility and arm ownership:
  `darktidevr_stereo_probe.lua`;
- ranged convergence and depth ray:
  `darktidevr_controller_aim.lua`;
- experimental full body toggle:
  `tools/stereo/set-full-body-experimental.ps1` and
  `darktidevr_full_body_experimental.flag`.

## Current reticle and aiming state

- The old cyan square is now a 41x41 transparent-atlas, outlined white
  compositor crosshair in `window_capture.cpp`.
- The quad is submitted binocularly only on fresh `stereo_world` pairs and is
  enabled by default in both normal start/runner scripts.
- Its right-hand ray rejects the local root, first-person unit, all equipment
  roots and attachment units. It ignores broad dynamic character capsules and
  accepts static geometry or a damageable actor's actual hit-zone actor.
- Left-hand and staff-tip projectiles now recompute direction from their own
  origin to the shared right-hand-selected world point.
- The current size is an explicit 10x visibility trial:
  `distance * 0.07`, clamped to 0.15-1.2 m.
- The user's closing request is exactly 30 percent smaller and partly
  transparent. Tomorrow's planned values are `distance * 0.049`, clamps
  0.105-0.84 m, and approximately 67 percent alpha for both black outline and
  white fill while the atlas background remains fully transparent.
- The latest ray-filter change passed source/live transport validation but has
  not had its final worn matrix. Specifically recheck that the crosshair does
  not stick inside the right hand and does not stop on the enemy's outer
  capsule roughly 1 m before the visible target.

The generalized first-person-body idle suppression is also present. Its worn
acceptance is pending: no random idle arm drift, while attack, charge, reload
and weapon-switch animation ownership must continue to work.

## HUD, menu and rendering state to preserve

- The fixed-HUD experiment is not accepted. Current deployed HUD flag state is
  `consumed`; do not assume the large dirty `darktidevr_hud_panel.lua` diff is a
  working production path. The evidence proves HUD target population can be
  forced, but worn presentation has alternated between absent, world-fixed and
  broken camera behavior. Resume only from the ordered plan.
- Character-select and general menu interaction have a proven spatial laser
  path. Hadron became navigable, although a brief mono frame after exit remains
  logged as a tolerable refinement. Other shops, NPC-specific Penances and the
  Psykhanium entry UI remain unfinished.
- World-marker edge clamping and shop-prompt scaling must be binocular rather
  than per-eye.
- A verified particle family
  `42e436fb1ef1b392` / `6020f2548f29fd47` is cylindrical. The visibly spherical
  character-select smoke is a different, unidentified family.
- Lighting at each eye's extreme horizontal edge, some LOD/shadow parity and a
  broader quantitative performance pass remain open.

## Deployed runtime state at handoff

The game installation is
`D:\SteamLibrary\steamapps\common\Warhammer 40,000 DARKTIDE`. Important
deployed flags were:

```text
darktidevr_gameplay_input_test.flag=enabled
darktidevr_controller_aim_test.flag=enabled
darktidevr_full_body_experimental.flag=disabled
darktidevr_body_follow_test.flag=enabled
darktidevr_body_ik_presentation.flag=enabled
darktidevr_headless_body.flag=enabled
darktidevr_shared_shadow_cull.flag=enabled
darktidevr_hud_panel.flag=consumed
darktidevr_performance_profile.flag=disabled
darktidevr_performance_pass_trace.flag=disabled
darktidevr_weapon_presentation.flag=disabled
```

Normal deployment now reasserts gameplay input and controller aiming enabled,
and full-body experimental disabled, so temporary test cleanup cannot silently
remove production controls. The bootstrap `.mod` is now synced and registers
the existing DMF data/localization resources.

## Last validated baseline

- `tools\stereo\test-darktide-lua-source.ps1` passed.
- The main Lua chunk is at **198/198** allowed file-scope locals. Do not add a
  file-scope local; put state on an existing table or split work into a required
  module.
- Release `darktidevr-xr-harness` and
  `darktidevr-window-capture-tests` built successfully.
- `darktidevr-window-capture-tests.exe` passed with an opaque crosshair and
  transparent atlas background. Update this test when alpha changes.
- The last authenticated Psykhanium run had fresh stereo initialization,
  nonzero advancing `shared_ready`, approximately 60 synchronized pairs per
  second and no new Lua error.
- Closing worn state: stereo/6DoF mechanically worked; only bare hands plus
  weapons were visible; hand travel remained body-skeleton limited; cursor was
  judged 30 percent too large and should be partly transparent.

## Exact restart sequence

1. Run `git status --short` and preserve every file listed above.
2. Read the ordered work plan; start with independent hand proxies, then the
   small reticle presentation change.
3. Before deployment or launch, run:

   ```powershell
   & .\tools\stereo\test-darktide-lua-source.ps1
   ```

4. Build the changed Release targets and run the focused tests. For the current
   reticle path:

   ```powershell
   & 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr-xr-harness darktidevr-window-capture-tests
   & .\build\windows-vs2022\Release\darktidevr-window-capture-tests.exe
   ```

5. Confirm Darktide has been closed for at least 10 seconds. A normal
   authenticated Psykhanium run is:

   ```powershell
   & .\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 900 -GameStartTimeoutSeconds 300 -EnterPsykhanium
   ```

   `-EnterPsykhanium` must be armed while Darktide is closed. It owns the
   guarded hub advance and avoids the known public-hub remote-husk teardown
   race.

6. Do not accept the run merely because OpenXR exists. The fresh console log
   must contain stereo mod initialization and the harness must report nonzero,
   advancing `shared_ready`.
7. For unattended testing, verify authorized ADB and reapply the Quest
   proximity override with
   `tools\quest\set-proximity-override.ps1 -Action Disable`. Restore normal
   wear behavior with `-Action Enable` afterward.
8. If XR repeatedly fails after source validation and a known-good rollback,
   then restart Virtual Desktop on the PC, wait about 30 seconds, and restart
   it on the Quest. Do not blame Virtual Desktop or perform this reset on the
   first unrelated failure.

## First-session completion target

Do not spend the first fresh session rediscovering old rendering history. A
useful first completion is either:

- independent visible hand proxies that demonstrably exceed avatar arm reach
  without exposing whole arms; or
- a documented engine/asset blocker plus the completed 30%-smaller,
  semi-transparent reticle and its focused tests.

Update this handoff or create the next dated handoff before ending that session.

## 2026-09-01 06:00 validation update

The launch presentation now uses a profile-matched, hands-only local proxy even
while full-body experimental mode is disabled. Once it becomes ready, the
authoritative player's `slot_body_arms` is hidden, while the proxy keeps only
`slot_body_arms` plus the invisible `slot_unarmed` spawner dependency. The
proxy no longer recopies either hand node from the stock animation each frame.

`apply_body_arm_ik` still uses the hidden two-bone chain to derive the tracked
hand orientation, then directly translates `j_lefthand` / `j_righthand` under
their forearm parent to the calibrated OpenXR target. The visible hands are
therefore controller-owned effectors rather than reach-clamped skeleton ends.
During the authenticated synthetic Psykhanium run, the first left-hand sample
was 0.3982 m beyond the solved arm chain. Subsequent logs sustained 0--1 micrometre
post-write position error and at most 0.000927 rad logged angular error across
16,801 presentation writes. The six synthetic phases all ran for approximately
4,260--4,320 frames, including crossed/full-roll, beyond-reach and
tracking-invalid/reacquisition coverage. No proxy failure, presentation Lua
error or stereo-mod error was logged. A worn visual check is still required;
the current profile's hand slot remains bare skin, and dedicated glove/bracer
geometry is still an asset gap.

The compositor reticle is now exactly 30 percent smaller than the 10x
visibility trial: `distance * 0.049`, clamped to 0.105--0.84 m. White fill and
black outline use alpha 171/255 (about 67 percent); the atlas background remains
zero alpha. The focused capture test asserts all three values. The synthetic
authenticated run published 5,868 reticle frames at the world-ray hit distance.

Validation commands run:

```powershell
& .\tools\stereo\test-darktide-lua-source.ps1
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr-xr-harness darktidevr-window-capture-tests
& .\build\windows-vs2022\tests\xr_harness\Release\darktidevr-window-capture-tests.exe
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' --build build\windows-vs2022 --config Release --target darktidevr-two-bone-ik-tests darktidevr-synthetic-controller-tests darktidevr-window-capture-tests
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' --test-dir build\windows-vs2022 -C Release --output-on-failure -R 'two_bone_ik|synthetic_controller_path|window_capture_recovery'
& .\tools\quest\set-proximity-override.ps1 -Action Disable
& .\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 360 -GameStartTimeoutSeconds 300 -EnterPsykhanium -SyntheticControllerPath -SyntheticBodyPath
& .\tools\quest\set-proximity-override.ps1 -Action Enable
git diff --check
```

Results: Lua source safety passed at 198/198 file-scope locals with all four
runtime modules parsed; focused CTest passed 3/3; authenticated Psykhanium entry
passed; the six-minute XR run ended `result=pass` with 17,423 fresh shared pairs,
zero reused shared frames, zero pair-pose mismatches and nonzero advancing
`shared_ready` (17,375 at the last live sample). Quest proximity automation was
restored and the owned Darktide process was closed after the run.

### 06:05 tracking-loss hold refinement

The hands-only proxy no longer merely avoids recopying stock hand nodes. Each
successfully authored hand now records its world pose. When grip tracking is
invalid, the next presentation pass reapplies that pose after the proxy has
inherited its hidden parent-chain baseline; on reacquisition, controller
authority replaces the held pose and logs the transition. This prevents stock
forearm animation from moving a supposedly held hand indirectly through its
parent while tracking is absent. Proxy respawn and body-IK gate transitions
clear the saved poses so stale unit/session state cannot leak forward.

`tools\stereo\test-darktide-lua-source.ps1` now fails closed unless the
world-pose hold path remains present. It passes at 198/198 locals, and
`git diff --check` passes. A second authenticated synthetic run was attempted,
but the Quest ADB target had gone offline after normal proximity behavior was
restored (`adb devices` reported no authorized device). No deployment or launch
was performed. Fresh runtime validation of the hold/reacquisition counters is
therefore still required when the headset is reachable; the preceding run
already validates the controller-owned effector itself and all six input
phases.

### 06:25 garment-resource diagnostic

The extracted game scripts confirm there is no current wearable
`slot_gear_gloves`; human cosmetics are rooted in `slot_gear_upperbody`, while
`slot_body_arms` is the body-skin slot. Runtime equipment data already exposes
an `item_name_by_unit_3p` map for every spawned cosmetic attachment. The
existing one-shot garment mesh diagnostic now logs that master-item/resource
name beside each attachment's bounds. On the next authenticated run this will
identify the two arm-shaped attachment units directly, avoiding a broad scan
or speculative spawn of the full backend item catalog. It does not change
visibility or presentation behavior.

Static validation after this diagnostic passed:

```powershell
& .\tools\stereo\test-darktide-lua-source.ps1
git diff --check
adb devices
```

The Lua check remains at 198/198 with four modules parsed and `git diff --check`
reports only the pre-existing line-ending warnings. ADB still listed no device,
so the diagnostic and tracking-loss hold counter remain queued for fresh live
validation; Darktide was not launched.

### 06:45 binocular-overlap marker clamp

The prior world-marker path moved stock left/right-clamped markers to one
shared angular edge, but it did not catch the earlier stereo failure boundary:
a marker can remain inside the primary eye while already outside the other
eye. `prepare_binocular_clamped_offsets` now converts every drawn marker's
primary-eye X coordinate back to a frustum tangent. If it lies outside the
intersection of the two runtime eye frusta, both eye draws switch to the same
overlap boundary with a two-percent inset. The normal and replay draws retain
the same marker object, distance and template scale, so this change only owns
pair clamping and does not introduce per-eye scale calculation. Existing stock
off-screen clamps keep their authored margin behavior.

The fail-closed source check now requires the left/right overlap tests and
inset. Validation run:

The adjacent shop-interaction prompt shares the marker scale without requiring
another per-eye scale hook. Darktide's `_update_target_interaction_size`
calculates prompt dimensions once from text and intro state;
`_update_interaction_hud_position` only copies the active marker widget offset
into the prompt pivot. The right-eye replay refreshes exactly that pivot after
reprojecting the same once-scaled marker widget, so it cannot produce a second
eye-specific prompt size. Treat this as mechanically complete pending the same
worn edge-approach acceptance pass as the marker clamp.

```powershell
& .\tools\stereo\test-darktide-lua-source.ps1
git diff --check
```

The Lua check passed at 198/198 file-scope locals with all four modules parsed;
`git diff --check` reports only the existing line-ending warnings. ADB remained
offline, so live edge-approach observation is still pending and no deployment
or Darktide launch was attempted.

### 07:05 tracked equipment attachment ownership

The hands-only profile proxy intentionally does not spawn player weapons;
Darktide's authoritative gameplay visual-loadout owns those units and their
attack, charge, reload and switch animation state. That left their 3P links
under the hidden source skeleton's hand nodes. A new post-animation sync now
copies the proxy hands' final tracked-or-held world transforms onto only those
two hidden source hand nodes. The source arms remain invisible, the proxy is
still the sole visible hand owner, and the linked gameplay item follows the
controller while retaining all item-local stock animation.

This runs after the visual-loadout update at the existing locomotion
`post_update` seam, for both launch hands-only and opt-in full-body proxy modes.
The source safety script now fails closed if the equipment-hand sync path is
removed. Validation run:

```powershell
& .\tools\stereo\test-darktide-lua-source.ps1
git diff --check
```

The Lua check passed at 198/198 locals with four modules parsed and the diff
check found no whitespace error. ADB still listed no device, so the required
fresh `equipment_hand_owner=tracked_proxy`, advancing `shared_ready`, synthetic
weapon-path and worn animation observations remain queued; no deployment or
launch was performed.

### 07:45 offline listener, facility coverage and visibility union

`tools\quest\watch-quest-online.ps1` is running as PID 27460 until 23:59:59
Brisbane. It polls ADB every ten seconds, applies the existing Quest proximity
override as soon as an authorized `Quest*` model appears, and rearms itself
after a disconnect. Its log is `%TEMP%\darktidevr-quest-online.log`; the device
has remained offline so far. The twenty-minute heartbeat also checks this
listener and is instructed to resume live validation on reconnect.

The controller-aim diagnostic now distinguishes `static`, `damage` and `miss`
ray outcomes in addition to the existing self/non-surface skips. The launcher
also owns performance-profile and pass-trace flags for one run and restores
their previous values in `finally`.

Penances and both Psykhanium UI stages are now explicit members of the proven
mode-5 captured-client facility family:
`penance_overview_view`, `training_grounds_view` and
`training_grounds_options_view`. This prevents the pod's landing-to-options
transition from falling through the generic world-menu route. Guarded menu-test
commands `penances` and `psykhanium` can open the corresponding landing views
once live testing resumes.

The prior shared visibility policy pointed both viewport `shadow_cull_camera`
fields at the tracked primary render camera. That made the decisions identical
but still used the left eye's frustum, so lights visible only at the opposite
outer edge could be absent. Both viewports now share a cull camera on a third,
standalone `core/units/camera` unit. Each tracked update places it at the
cyclopean pose and expands its vertical FOV enough to enclose the union of all
four horizontal and vertical runtime-frustum extrema. Do not reuse the stock
dedicated shadow component here: it shares the primary render-camera unit, and
an earlier live probe proved moving it perturbs rendering. The standalone unit
supplies one binocular candidate population without changing either eye's
optical projection; the next log must contain
`visibility_cull mode=binocular_union source=standalone_camera_unit`.

An offline performance fallback was added to the launcher as
`-OfflineDualViewBenchmark`. It uses the exact production sequential gameplay
viewports and prepared-second-eye path, enables profiling for the run, waits for
an authenticated `hub_ship`, and applies a deterministic twenty-second camera
revolution instead of moving an unattended character through a populated hub.
The first 360-second attempt did not reach the benchmark: Darktide remained
responsive but its console stopped at `STARTUP: pre update loop`, before DMF
loaded the stereo mod. The launcher timed out, restored all three run-scoped
flags and terminated only its owned Darktide process. Treat this as a clean
orchestration failure, not performance or lighting evidence; a lightweight
non-OpenXR shared-eye consumer or a second clean startup attempt remains needed.

Validation commands run:

```powershell
& .\tools\stereo\test-darktide-lua-source.ps1
git diff --check
& .\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 360 -GameStartTimeoutSeconds 300 -OfflineDualViewBenchmark -EnablePerformancePassTrace
```

The source gate passes at 198/198 locals with all four modules parsed, every
changed PowerShell script parses, and the failed run left neither Darktide nor
its temporary benchmark/performance flags active.

### 07:55 stock melee ownership and scene-scoped billboard evidence

The hands-only proxy now temporarily preserves Darktide's authoritative 3P
animation during primary-slot melee `windup`, `sweep` and `melee_explosive`
actions. `BodyProxy.update` has already copied the stock pose before the
post-locomotion IK seam, so the gate simply skips the tracked overwrite for
those frames. The weapon remains on the hidden gameplay visual-loadout hand;
idle and non-melee frames resume tracked proxy ownership automatically. Live
validation must observe both transition logs and confirm there is no one-frame
weapon/hand discontinuity:

```text
DARKTIDEVR_ARMS animation_owner=stock_melee ...
DARKTIDEVR_ARMS animation_owner=tracked_proxy ...
```

The character-select SBS capture visibly confirms the remaining smoke defect,
but it predates PSO identity logging and therefore cannot identify a shader
family. The launcher now accepts `-CaptureBillboardPsoIdentities`, records the
existing append-log byte offset, and emits only that run's new bytes after its
owned game has stopped. Use matched character-select and hub runs, then rank
scene-enriched `billboard=1` pairs with:

```powershell
py -3 .\tools\stereo\compare-billboard-pso-scenes.py `
  <hub.tsv> <character-select.tsv> `
  --families .\artifacts\unattended\billboard-shader-families-2026-08-31.csv `
  --output <comparison.csv>
```

This deliberately leaves the proven cylindrical
`42e436fb1ef1b392 / 6020f2548f29fd47` substitution unchanged until the scene
delta supplies an exact candidate.

Validation performed:

```powershell
tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

# PowerShell AST parse of tools\stereo\start-darktide-vr.ps1
# pass

py -3 tools\stereo\compare-billboard-pso-scenes.py `
  artifacts\unattended\billboard-pso-identity-aggregate-pre-clean-2026-08-31.tsv `
  artifacts\unattended\billboard-pso-identity-aggregate-pre-clean-2026-08-31.tsv `
  --families artifacts\unattended\billboard-shader-families-2026-08-31.csv `
  --output $env:TEMP\darktidevr-billboard-scene-self-test.csv
# pass: 5,162 rows versus itself, every reported share delta 0 and enrichment 1

git diff --check
# pass except existing line-ending warnings
```

Quest remained offline; hidden listener PID `27460` was healthy and no sleep
state was changed.

### 08:24 repeated offline startup boundary and menu resolution

Two further bounded offline-benchmark launches reproduced the same pre-mod
startup boundary. Each authenticated game process stopped after
`STARTUP: pre update loop`; neither `[Window] Window => active`, a boot-state
transition, DMF initialization nor stereo initialization followed. The process
remained responsive at roughly 2.6 GB working set with low GPU utilization.
Programmatic activation, thread-input attachment and an explicit focus-away /
focus-back cycle all succeeded at the Win32 boundary without advancing the
game, which falsifies window focus as the cause. The temporary focus
experiments were removed.

The named shared-eye handles are created only after Lua/viewport setup, so a
lightweight headless consumer could measure a running producer but cannot
unblock this earlier renderer/update-loop boundary. Do not repeat the same
blind launch; the next offline investigation should capture a bounded WPR/ETW
or debugger hang trace. Clean timeout handling preserved the three run-scoped
billboard slices under
`artifacts/unattended/billboard-scene-identities/`, stopped only launcher-owned
processes and restored the benchmark/performance flags. A manually interrupted
attempt was also cleaned explicitly. Darktide is closed and the offline flag is
absent.

The Escape/menu resolution audit found that the XR flat swapchain already uses
the runtime eye width, but the interactive window-capture source was fixed at
1280x720. It is now 1920x1080, preserving the exact 16:9 pointer mapping while
providing actual 1080p menu detail instead of upscaled 720p pixels. The proven
landscape panel to portrait semantic-canvas transform is unchanged: the prior
2496x2688 runtime evidence maps `(290,421)/1280x720` to `(566,1572)` exactly.
The remaining vertical-offset acceptance is therefore a worn laser/cursor
check, not justification for an unmeasured transform change.

WPR `GeneralProfile` could not start because the host policy rejected system
performance profiling (`0xc5585011`); it never entered a recording state.
`tools/stereo/get-process-wait-chain.ps1` was added as a read-only,
non-elevated fallback. On a final bounded reproduction, Darktide exposed the
expected titled responsive window and roughly 2.73 GB working set. Its initial
thread continued waking and accumulated CPU, while WCT reported 55 blocked and
25 running roots with no second node: no thread/process dependency, named
mutex, COM, socket, critical-section or SendMessage chain was present. Several
worker threads also accumulated CPU. This is an internal polling/renderer
update boundary rather than an ordinary wait-chain deadlock. The launcher then
timed out and restored its flags normally.

Historical upper-body mesh bounds also narrow the garment candidates:
attachments 2 and 4 are the two long arm-shaped pieces; attachments 1 and 3
have centered torso/head-scale bounds. The next-run inventory now logs both
`attachment_item_name` and the UnitSpawner `unit_name` resource for every
attachment so those two candidates can be identified without spawning a
catalog.

Additional validation:

```powershell
& .\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\tools\stereo\get-process-wait-chain.ps1 -ProcessId 27460
# pass: listener thread roots returned without elevation

git diff --check
# pass except existing line-ending warnings
```

### 09:00 offline dual-view benchmark unblocked

The pre-update stall was caused by installing the process-wide native D3D12
hooks eagerly from the proxy during the game's first device creation in a run
with no OpenXR consumer. `d3d12_bootstrap.cpp` now detects only the existing
run-scoped `darktidevr_offline_dual_view.flag` and defers that eager install.
The Lua mod later loads the same native DLL and calls `dtvr_install()` after the
engine update loop is active. The normal XR path does not take this branch and
continues to install eagerly. Development sync now deploys the built bootstrap
proxy and verifies its hash alongside the native capture DLL.

A 60-second authenticated `-OfflineDualViewBenchmark` reached `hub_ship`,
created the exact production sequential left/right gameplay viewports, and
completed the deterministic camera-spin workload. Warm samples were generally
6.0–6.7 ms for the left eye and 9.0–10.5 ms for the right eye, with a combined
interval around 15–17 ms. Transient bands occurred around the 20-second spin
boundaries; the initial loading/warm-up sample was excluded from that range.
The right-eye asymmetry is real enough to target with the existing pass trace.

The same run logged the shared visibility camera but revealed that no-HMD runs
used the unexpanded single-eye projection when runtime frusta were absent. The
fallback now derives the horizontal cone from the primary projection, adds the
translated-eye near-plane tangent padding, and expands the vertical FOV to
contain that width at the fixed eye aspect. Runtime-frustum launches retain the
four-extrema union plus the same translation padding. This gives offline runs a
meaningful edge-light/cull workload; worn visual confirmation remains pending.

Validation performed:

```powershell
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release `
  --target darktidevr_d3d12_bootstrap darktidevr_native_capture
# pass

.\tools\stereo\start-darktide-vr.ps1 -OfflineDualViewBenchmark `
  -DurationSeconds 60 -GameStartTimeoutSeconds 180
# pass: hub benchmark completed, owned game closed, temporary flags restored

.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4
```

Quest remained offline and listener PID `27460` remained healthy.

### 09:36 performance attribution and character-select smoke gate

The GPU stage profiler's intermediate timestamp used `slot * 3 + 1` even
though each slot reserves the three base queries plus pass-trace queries. It
now uses `slot * kGpuProfileQueriesPerSlot + 1`, eliminating cross-slot writes
and restoring valid world/post stage samples. Warm hub traces show roughly
equal world/internal work for both views. The second submitted viewport pays an
additional 3--4 ms of post-world/finalization work. Enabling the existing
reverse-eye-order diagnostic moves that cost from the physical right view to
the physical left view; disabling the full-second-eye preparation path does not
remove it. Treat this as render-order finalization and report the combined pair
interval rather than optimizing a fictitious right-eye-only world cost.

The shared binocular cull camera was also A/B tested in the offline hub-spin
workload. Disabling it did not materially change warmed combined GPU time, so
the translated-frustum union remains enabled. Its no-HMD fallback logged a
near-plane eye-origin tangent padding of `0.400000` and widened the shared
vertical FOV to approximately 94 degrees. The change therefore covers the
reported extreme-edge lighting failure without a measurable hub penalty;
headset visual acceptance is still required.

The character-select/title and three existing hub identity slices were
compared across every nonzero shader pair because the target did not match the
native `billboard=1` heuristic. Reflection ruled out the highest-count results
as skinned character and wrap-deformed cloth shaders. Only one scene-specific
pair was blended: `3744e7b93c3085b0 / 80a9194fe7024bdc`. Its vertex shader is a
47-instruction pretransformed mesh path with a 248-byte `c_per_object` buffer,
not a particle-system/c_billboard interface.

An exact run-scoped magenta pixel probe exposed and fixed a diagnostic omission:
pipeline-state streams previously supported vertex substitution but not pixel
substitution. Pixel replacement now has the same interface validation, cached
PSO clearing, fallback and result counters as legacy graphics descriptors.
The repeated clean-cache run reported `attempts=1 applied=1
validation_rejects=0 creation_rejects=0`, yet the settled character-select
capture contained no magenta contribution. This disproves that candidate as
the visible smoke. Do not broaden the production cylindrical
`42e436fb1ef1b392 / 6020f2548f29fd47` fix. The remaining owner is probably in
PSOs or pre-recorded command work created before the deferred no-headset hook;
resume from an eager headset-backed capture or the established cache-clean hue
search.

New retained evidence:

- `artifacts/unattended/billboard-scene-identities/character-select-all-shader-families-20260901.csv`
- `artifacts/unattended/billboard-scene-identities/character-select-80a9194fe7024bdc-magenta-stream-20260901.png`
- `artifacts/unattended/billboard-scene-identities/character-select-20260901-093342.tsv`

Validation performed:

```powershell
& .\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release `
  --target darktidevr_native_capture darktidevr_d3d12_bootstrap
# pass

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-debug `
  --target darktidevr_native_capture darktidevr_d3d12_bootstrap
# pass

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --preset windows-vs2022-debug `
  -R 'native_capture_hooks|shared_eye_surfaces|core_math' --output-on-failure
# pass: 3/3

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineCharacterSelectCapture -CaptureBillboardPsoIdentities `
  -BillboardPixelShaderProbeHash 80a9194fe7024bdc `
  -DurationSeconds 75 -GameStartTimeoutSeconds 240
# pass: exact probe applied, run-owned game closed, probe/offline flags restored
```

Quest remained offline. Hidden listener PID `27460` was still active and no
sleep override was changed.

### 14:24 production hot hooks and menu recording lifetime

The performance sweep found that compile-time direct-menu support was keeping
several expensive paths live during normal gameplay: every PSO bind updated a
mutex-protected command trace and participated in a broad first-bind census,
every draw updated a diagnostic atomic, and Close/Reset/Execute serialized on
an empty menu-resource map. Those paths are now runtime-gated. Normal gameplay
keeps the hooks available but performs menu trace work only while direct menu
capture is active; explicit `-CaptureBillboardPsoIdentities` runs opt into the
diagnostic hook set and retain their full census. Disabling menu capture clears
the last menu-only trace generation so a later enable cannot reuse stale PSO or
render-target state. Begin/end render-pass state is now symmetrical.

The same audit found a correctness defect in the direct-menu resource lifetime.
`ExecuteCommandLists` erased the command-list-to-surface reference before the
original D3D12 submission call, allowing a differently sized concurrent menu
to replace and release that surface in the pre-submit window. Releasing just
after submission was also insufficient for GPU lifetime. Entries now remain
until the command list successfully resets, matching the engine's recording
retirement boundary; failed Reset leaves the old references and traces intact.
The Lua/source gate asserts both ordering properties.

The first observed direct queue was also reacquired under `state_mutex` for
every submission. A release/acquire one-time publication removes that steady-
state lock after initialization. The latest measured hub run observed roughly
1,800 execute calls per second, so this is a material hot-path reduction.

Fresh validation:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

cmake --build build\windows-vs2022 --config Release
ctest --test-dir build\windows-vs2022 -C Release -I 1,30 `
  --output-on-failure
# pass: 30/30

cmake --build build\windows-vs2022 --config Debug
ctest --test-dir build\windows-vs2022 -C Debug -I 1,30 `
  --output-on-failure
# pass: 30/30 before the final lifetime ordering patch; rerun Debug after the
# next native edit batch

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 120 `
  -GameStartTimeoutSeconds 600
# pass: clean synchronized hub spin, nonzero ready, flags restored, owned PID
# terminated
```

The 24 performance windows averaged 0.0410 ms left callback, 0.0043 ms right,
0.2803 ms pair and 0.4115 ms reported pair p95. Fresh log:
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-04.20.27-9109c048-7464-4225-aab2-f1e6745b13c5.log`.
No targeted Lua, native, D3D12 device-removal or page-fault error was present.

Quest watcher PID `34624` remains active through 23:59:59 local time. ADB still
reported no attached Quest, so no sleep/proximity setting was changed and worn
edge-lighting validation remains pending.

### 13:50 controller freshness and fail-closed runner hardening

The gameplay export now rejects controller transport older than 100 ms, resets
held/movement state and exposes the mapper's one release edge before reporting
the sample unavailable. This prevents a stopped XR publisher from leaving a
trigger or stick latched in gameplay. The export regression covers an initially
stale mapping, a fresh held trigger and the stale transition that releases it.

The Lua source check and Quest listener also now tolerate successful native
tools writing progress to stderr. PowerShell temporarily uses `Continue` only
while capturing `luaparse`/ADB output, saves the native exit code, then restores
the fail-closed `Stop` preference. Syntax validation passes at 198/198 file-
scope locals. Release passed all 30 non-headset-capable tests; the three OpenXR
session smokes remain blocked by `hmd-unavailable`. Debug passed its 29 tests
outside the `headset` label plus the synthetic-head test separately (30 total).

The Quest is still offline. The corrected hidden listener is PID `34624`, polls
every 10 seconds until 23:59:59 local time, and currently selects SideQuest ADB
34.0.5 to match the live server. No device sleep/proximity setting has changed.

### 14:04 aim/calibration freshness and offline cleanup diagnostics

Gameplay aim transport is now v3 and includes a monotonic publish timestamp.
The XR compositor and standalone synthetic controller publisher both reject
reticle state older than 100 ms, preventing a stopped Lua aim publisher from
leaving the last hit/distance latched. Release and Debug tests 1-30 pass 30/30
serially, including current/expired transport coverage.

The calibration head callback now returns nil when the native 250 ms head-pose
freshness gate rejects its read. It can no longer reuse the previous FFI buffer
as a fresh calibration sample. The Lua preflight passes at 198/198 locals. A
fresh authenticated run logged clean synchronized initialization, and direct
readback advanced ready 1 -> 3 while saving two pairs at
`artifacts/unattended/calibration-head-freshness-smoke-20260901/`. Evidence log:
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-04.02.39-c4875728-e5a7-4a24-bab1-e2d4af727b59.log`.

Successful offline cleanup now reports that it terminated the run-owned game,
instead of the false `XR owner exited` warning. The active 20-minute heartbeat
was rechecked. Quest listener PID `34624` remains alive; no Quest is connected
and no sleep/proximity setting has changed.

The subsequent fence sweep closed a time-of-check/time-of-use gap: device
removal between the start-of-frame health check and the later ready-fence read
could pass `UINT64_MAX` into pair bookkeeping or a queue wait. Both shared-eye
and shared-menu generations now have a second poison check immediately before
copy submission. Release and Debug tests 1-30 still pass 30/30 serially.

### 13:24 launch ownership and bounded GPU teardown

The launch chain no longer treats a process name or window title as sufficient
ownership. `start-darktide-vr.ps1` snapshots pre-existing game PIDs and filters
offline readiness plus final cleanup by the exact configured executable.
`invoke-darktide-launcher-play.ps1`, `advance-darktide-to-hub.ps1` and
`run-darktide-shared-eyes.ps1` now apply the same executable-path check before
accepting a launch, sending input, or attaching XR. Existing game PIDs survive
the run, and the old unfiltered `Get-Process | Stop-Process` path is gone.

The XR harness also replaced its three infinite local D3D12 fence waits with a
shared 10-second wait. It fails with completed/target diagnostics when the
queue stalls and rejects the device-removed `UINT64_MAX` sentinel before and
after the wait, allowing wrapper cleanup to run instead of hanging forever.

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

cmake --build build/windows-vs2022 --config Release --parallel
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -I 1,30
# pass: 30/30

cmake --build build/windows-vs2022 --config Debug --parallel
ctest --test-dir build/windows-vs2022 -C Debug --output-on-failure -I 1,30
# pass: 30/30

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 15 `
  -GameStartTimeoutSeconds 300
# authenticated configured executable PID 106516; hub synchronized dual-view
# and synthetic spin active; flags restored; exact run-owned process closed
```

Fresh console evidence is
`console-2026-09-01-03.22.00-8be3c1b4-22a7-402c-822f-5e2915c13f23.log`.
It contains the DMF initialization, native-hook install and synchronized
sequential hub transition with no targeted Lua/native error. Quest listener
PID 2300 remains active; ADB still reports no headset, so the listener has not
changed proximity or sleep settings.

### 13:38 mailbox ownership and menu-writer restart recovery

Every producer path now obeys the one-slot mailbox contract. The previously
unguarded side-by-side/top-bottom/alternating path checks that the consumer has
acknowledged `ready` before recording another copy. Sequential eyes, copied
menus, direct-render menus and present-derived eyes share the same
poison-aware policy. Failed queue signals invalidate the affected mailbox
generation instead of leaving a staged eye or untracked allocator that blocks
all later capture. GPU profiler and desktop-mirror fence poison paths now fail
closed as well.

Menu-pointer transport moved from v3 to v4 with an explicit writer generation.
Lua receives it through `dtvr_read_menu_pointer_state_v2`, which keeps the old
11-element export ABI intact and returns generation atomically with the sample.
On a generation change Lua adopts the current click/back/scroll counters as
its baseline, preventing a restarted harness's counter reset from activating a
menu control.

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

cmake --build build/windows-vs2022 --config Release --parallel
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -I 1,30
# pass: 30/30

cmake --build build/windows-vs2022 --config Debug --parallel
ctest --test-dir build/windows-vs2022 -C Debug --output-on-failure -I 1,30
# pass: 30/30

.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 45 -GameStartTimeoutSeconds 300 -AutoEnterHub -SyntheticHeadSweep
# hardware blocked: VirtualDesktopXR hmd-unavailable; flags restored and
# exact run-owned PID 117244 removed

.\tools\stereo\start-darktide-vr.ps1 -OfflineDualViewBenchmark -DurationSeconds 45 -GameStartTimeoutSeconds 300

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe artifacts/unattended/menu-pointer-generation-source-smoke-20260901 2 2112 2304
# pass: initial_ready=1 final_ready=3
```

The substitute run's fresh console log is
`console-2026-09-01-03.32.07-c36ea5a3-4d3b-40b3-a63e-a1f04a8e4b95.log`.
It contains current DMF initialization, native-hook installation and
synchronized hub-spin activation with no targeted Lua/native error. A real XR
`shared_ready` gate and worn asymmetric-frustum lighting check remain pending
until the Quest is online.

### 12:58 bounded stale-pair recovery and command-kind trace

The XR harness previously treated an active projection event as sufficient to
reuse its last complete stereo pair forever. A producer that stalled without
poisoning or replacing its fences could therefore leave a frozen world in the
headset indefinitely. Cached-pair reuse now has a 5000 ms grace period; the
tested policy then returns to the existing flat spatial fallback until a fresh
pair becomes available.

The performance profiler audit found two diagnostic defects. GPU batch capture
read command-list generations from a map protected by a different mutex, and
its per-list draw/dispatch totals were populated only when an unrelated marker
log was open. Generation and command-kind counters now live in and are
snapshotted from the same mutex-protected command trace. The trace records
direct/indexed draws, compute dispatches, ExecuteIndirect calls, legacy and
enhanced barriers, and explicit D3D12 render-pass entries. The analyzer and its
regression fixture support the extended fields and still default missing fields
to zero for old captures.

The corrected authenticated hub-spin trace shows that dominant work is nearly
the same for both views:

- eye 0: 3.009 ms, 212 draws, 50 dispatches, 537 indirect submissions and 403
  barriers;
- eye 1: 2.846 ms, 229 draws, 59 dispatches, 570 indirect submissions and 392
  barriers.

Eye 1 used three additional queue batches, but together they cost only 0.531
ms. They consisted of a barrier-only batch, a 4-draw/two-barrier batch and one
batch with no intercepted graphics, compute or barrier work. The terminal eye
1 batch was faster than eye 0's (1.815 versus 2.420 ms). Combined with the
earlier order-reversal and PSO-overlap results, this localizes the variable tail
to frame-global queue/finalization traffic rather than a second expensive
lighting or world pass.

Evidence:

- `artifacts/unattended/gpu-batch-command-kind-analysis-20260901/report.md`
- `artifacts/unattended/gpu-batch-command-kind-analysis-20260901/report.json`
- `artifacts/unattended/gpu-batch-command-kind-analysis-20260901/darktidevr-focused-draws.log`
- `artifacts/unattended/gpu-batch-command-kind-analysis-20260901/console-2026-09-01-02.53.09-0fef7d4a-cebe-44bf-8d4e-a60a0bccf5d0.log`

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

cmake --build build\windows-vs2022 --config Release
ctest --test-dir build\windows-vs2022 -C Release `
  -R '^(native_capture_hooks|presentation_policy|xr_harness_help)$' `
  --output-on-failure
# pass: 3/3

python .\tools\stereo\test-analyze-gpu-batch-trace.py
# analyze_gpu_batch_trace_tests=pass

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -EnablePerformancePassTrace `
  -DurationSeconds 75 -GameStartTimeoutSeconds 300
# pass: authenticated trace completed; flags restored; owned game closed
```

### 13:14 transport restart and copy-tail audit

Two low-frequency restart failures were closed. Presentation transport used
only a sequence counter, so a restarted producer that happened to republish the
same first sequence and a different mode could remain invisible to the harness.
The v3 mapping now exposes a transport-owned writer generation, and the harness
uses generation plus sequence as packet identity. Gameplay aim had the more
severe variant: the harness required a sequence at least as large as the old
process, which could suppress a restarted reticle producer until its counter
caught up. Aim transport v2 now uses the same writer-generation rule. Both
transport tests retain a reader across two sequential writers and deliberately
repeat or roll back the sequence.

Shared mailbox creation is now fail-atomic. The menu path previously retained
partial textures, heaps, named handles and fences after ready/consumed-fence
creation failed, and it reused a same-size resource even if its required RTV
format changed. It now validates the complete object/handle set, tracks the RTV
format, logs the exact failed construction stage and releases the entire partial
generation immediately. Eye creation now similarly validates both textures and
all named handles and clears every partial generation on any construction error.

The performance trace gained copy and resolve interception. The corrected live
capture again showed near-identical dominant eye work and reversed which eye had
the longer batch list. Eye 0 took 2.599 ms and eye 1 took 2.476 ms; unique PSO
overlap was 125/129 (0.969 Jaccard). Eye 0's three extra submissions totalled
0.318 ms: a 0.023 ms one-copy/two-barrier batch, a 0.105 ms four-draw batch and
a 0.190 ms long-lived generation-0 command list recorded before the focused
trace began. Neither view performed a resolve. The extra traffic changed total
cost by only +0.123 ms and does not resemble a duplicated world or lighting
pass.

A 45-second authenticated ABI smoke reached the hub, produced nonzero shared
ready state, ran the deterministic spin and logged no Lua failure. Shutdown
again emitted the base-game child-unit warning only after the remote peer
disconnected and the owned flat process was force-terminated; the active render
interval was clean. The ADB watcher remains active as PID 2300 and no Quest is
currently connected.

Evidence:

- `artifacts/unattended/gpu-batch-copy-analysis-20260901/report.md`
- `artifacts/unattended/gpu-batch-copy-analysis-20260901/report.json`
- `artifacts/unattended/gpu-batch-copy-analysis-20260901/darktidevr-focused-draws.log`
- `artifacts/unattended/gpu-batch-copy-analysis-20260901/console-2026-09-01-03.10.14-19ec16eb-a751-4e5d-8751-b3348baf7a5e.log`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-03.03.07-d561a955-3c6c-448a-af95-17048c28685e.log`

Focused validation performed:

```powershell
cmake --build build\windows-vs2022 --config Release
ctest --test-dir build\windows-vs2022 -C Release `
  -R '^(gameplay_aim_state_transport|presentation_state_transport|shared_eye_surfaces|native_capture_hooks|xr_harness_help)$' `
  --output-on-failure
# pass: 5/5

python .\tools\stereo\test-analyze-gpu-batch-trace.py
# analyze_gpu_batch_trace_tests=pass

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -EnablePerformancePassTrace `
  -DurationSeconds 75 -GameStartTimeoutSeconds 300
# pass: authenticated copy-aware trace completed; flags restored; owned game closed
```

### 12:32 healthy shared-eye generation recovery

The native lifetime sweep closed the remaining healthy-but-stale eye mailbox
case. A producer can replace the named eye surfaces while a consumer's old
fences still return ordinary, stalled values; poison-sentinel recovery cannot
detect that. Attempts to infer identity from reopened COM wrappers were invalid
because D3D12 creates distinct wrappers. Retaining a named NT handle was also
rejected because it can extend the old name's lifetime and obstruct producer
replacement.

The harness-owned head-pose mapping is now the generation authority. Its ABI is
versioned to `DarktideVR-head-pose-v11`; the producer atomically advances an
eye-surface generation only after both textures and fences have been created.
The harness records the generation at attachment and drops all cached eye,
readback and rendered-pose correlation state whenever it changes, then reopens
the ordinary names. This complements the per-frame poisoned-fence checks.

Validation performed:

```powershell
cmake --build build\windows-vs2022 --config Release --parallel
ctest --test-dir build\windows-vs2022 -C Release -I 1,30 `
  --output-on-failure
cmake --build build\windows-vs2022 --config Debug --parallel
ctest --test-dir build\windows-vs2022 -C Debug -I 1,30 `
  --output-on-failure
# pass: 30/30 in each configuration, run serially

.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 45 `
  -GameStartTimeoutSeconds 300

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe `
  artifacts\unattended\shared-eye-generation-smoke-20260901 3 2112 2304
# pass: initial_ready=1 final_ready=4

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-controller-publisher.exe `
  --seconds 80 --neutral-body-pose
# pass: eye_surface_generation=1
```

Evidence:

- `artifacts/unattended/shared-eye-generation-smoke-20260901/`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-02.25.23-2aca3a6e-d643-4ea5-8ae4-f71152df5c5e.log`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-02.29.28-edd4c366-eed9-4c5c-b533-e0b2bf538ca5.log`

The three headset-required CTest smokes remain unavailable because
VirtualDesktopXR reports `hmd-unavailable`. The active ADB listener still sees
no Quest, so no sleep override was changed. Next audit target is equivalent
generation recovery for the independent shared-menu mailbox.

### 12:40 menu recovery and projection-event lifetime

The independent menu mailbox had an analogous but more immediate fault:
`ensure_menu_surface` returned success on a matching texture without requiring
either synchronization fence to exist or remain healthy. A partial creation or
device-removed fence could therefore make every later caller accept a mailbox
that could never publish safely. Matching textures now require healthy ready
and consumed fences; otherwise the producer tears the mailbox down and rebuilds
it. Successful construction advances an independent menu-surface generation,
and the XR harness detaches cached menu resources on poison or generation
change before reopening them.

The same sweep found projection-event ownership drift. Three native exports
each kept a separate function-static handle to one named event, none was closed,
and the XR harness omitted its own normal-path close. A harness can also retain
the named event object across a producer restart, preserving the previous
process's signalled state. Native presentation now uses one atomic process
handle, explicitly resets a newly acquired producer generation to the
flat/fail-closed state, and closes it during detach. The harness closes its
opened event during ordinary teardown.

Release and Debug non-headset suites pass 30/30 serially. The shared-head-pose
transport test verifies independent eye and menu generations and restart reset.
An authenticated crafting-menu run correctly reported
`menu_surface_generation=0`: crafting is mode-5 native-window capture, not the
mode-3/4 shared-menu transport. That is a valid scope check, not a failed menu
mailbox test. Live generation acceptance remains pending until a genuine
retained-world menu is available without changing production classification.

Validation performed:

```powershell
ctest --test-dir build\windows-vs2022 -C Release -I 1,30 `
  --output-on-failure
cmake --build build\windows-vs2022 --config Debug --parallel
ctest --test-dir build\windows-vs2022 -C Debug -I 1,30 `
  --output-on-failure
# pass: 30/30 each, serial

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 50 `
  -GameStartTimeoutSeconds 300

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-controller-publisher.exe `
  --seconds 120 --neutral-body-pose
# eye_surface_generation=1 menu_surface_generation=0
```

Authenticated log:

- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-02.35.50-caf2bd0c-0db6-41b3-a545-8e401e605bdf.log`

### 11:27 Quest listener recovery

The original hidden listener exited at 11:22 without seeing a device. Its log
contained only the normal `finally` stop record, so the watcher now catches and
logs transient `adb devices` failures before continuing and records any outer
fault explicitly. A replacement hidden listener is active as PID `2300` through
23:59:59. The 20-minute heartbeat prompt independently requires checking and
recovering the listener, so a future process exit cannot silently remove the
Quest/sleep gate. `adb devices` remained empty and no sleep override changed.

### 11:06 headless controller matrix and hidden proxy surface

`darktidevr-synthetic-controller-publisher` now owns the controller/head shared
memory mappings when no XR harness is present. It publishes the same
near/far/crossed/full-roll/tracking-loss path and weapon-aim matrix as the XR
harness plus a stationary valid head sample. The valid head sample is required:
Lua deliberately does not poll controller input before a usable head pose.

A closed-game, pre-armed Psykhanium run reached `shooting_range`, delivered the
full matrix and captured 15 fresh `2112x2304` binocular pairs directly from the
producer surfaces. The first contact sheet exposed bare profile-proxy arms
stretched by unrestricted hand translation. `darktidevr_body_proxy.lua` now
hides the UI profile unit's render surface in tracked-hands mode while retaining
it as the pose-authoring skeleton. Source `/gear_hands/` attachments and the
game-owned wielded item remain visible and continue following the mirrored hand
nodes.

The repeat run passed with `DARKTIDEVR_IK hand_proxy_surface=hidden`, one
successful Psykhanium transition, 18 stock-melee owner transitions, 106
gameplay deliveries, 28 tracking transitions and continuing tracked-proxy
equipment ownership. All 15 direct eye pairs are free of the prior bare arm
surface. The synthetic path intentionally includes a 1.5 m beyond-reach phase,
so its authored glove cuffs can still elongate there; this is not representative
of a normal reachable controller pose and remains a worn refinement gate.

The publisher now also accepts `--neutral-body-pose`. It freezes the body-local
controller targets at a plausible reachable sample while leaving the weapon
matrix independent. A third closed-game range run captured 15 more binocular
pairs with that mode. Sword, force staff, charged/ability effects and gloves
remain visible, while glove/bracer geometry stays compact and no bare arm
surface appears. Use this mode for no-headset visual weapon acceptance and the
default moving body path for reach/roll/tracking-loss stress.

Evidence:

- `artifacts/unattended/psykhanium-offline-matrix-20260901/` (before surface hide)
- `artifacts/unattended/psykhanium-hidden-proxy-20260901/contact-left.png`
- `artifacts/unattended/psykhanium-neutral-matrix-20260901/contact-left.png`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-01.02.31-775558cd-fcb4-460a-b91d-029be83bc258.log`

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\tools\stereo\sync-darktide-vr-dev.ps1 -Configuration Release
# pass: module deployed with fail-closed source validation

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-controller-publisher.exe `
  --seconds 240 --weapon-aim-matrix

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -SyntheticWeaponAimMatrix `
  -DurationSeconds 120 -GameStartTimeoutSeconds 240
# pass: authenticated range, advancing producer-ready values, owned cleanup

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe `
  artifacts\unattended\psykhanium-hidden-proxy-20260901\s00 1 2112 2304
# repeated across 15 one-second matrix samples; every capture passed
```

Quest remained offline. Hidden listener PID `27460` remained active and no
sleep override was changed.

### 11:24 registered edge-light stability check

`tools/stereo/analyze-shared-eye-edge-stability.py` now analyzes adjacent
captures inside each full yaw revolution. It uses the known 20-second camera
rotation to perspective-warp the preceding frame into the current frame,
refines yaw by correlation, normalizes exposure from the central scene and
measures signed luminance residual at the surviving outer edge. The disabled
run supplies a temporal-noise control.

At a 0.55 alignment-correlation gate, 45 of 112 binocular comparisons passed.
The enabled mean was roughly one luma darker than disabled, but signed
frame-to-frame standard deviation was 6--9 luma and the medians reversed
direction (-0.07 enabled versus -2.20 disabled). The darker-than-20-luma pixel
fraction was also highly variable. This does not establish a repeatable
no-headset edge-light shutdown and is consistent with the earlier same-heading
A/B negative result. It still cannot reproduce the reported headset condition
because offline projection is symmetric rather than runtime-asymmetric.

Validation performed:

```powershell
python -m py_compile `
  .\tools\stereo\analyze-shared-eye-edge-stability.py

python .\tools\stereo\analyze-shared-eye-edge-stability.py `
  .\artifacts\unattended\shared-eye-cull-enabled-20260901\revolution `
  .\artifacts\unattended\shared-eye-cull-disabled-20260901\revolution `
  .\artifacts\unattended\shared-eye-edge-stability-20260901 `
  --minimum-correlation 0.55
# pass: metrics.json written; 45 accepted pairs
```

### 10:35 direct shared-eye capture and cull A/B

The invalid desktop-window lighting A/B has been replaced with direct D3D12
readback from the producer-owned eye surfaces. The new
`darktidevr-shared-eye-capture` executable finds the adapter that owns
`Local\\DarktideVR-eye-left/right`, participates in the producer's
ready/consumed fence protocol, copies a fresh binocular pair to readback heaps,
and writes full `2112x2304` PPM files. Every live attachment selected the RTX
4090 and advanced the shared-ready generation. The utility also has a tested
non-blocking `--help` path so ordinary CTest runs never wait for a game.

Two authenticated hub-spin legs captured the actual rotating eye output with
shared culling enabled and disabled. Four initial checkpoints plus dense
roughly one-second samples cover the full 20-second revolution in each run.
Evidence lives under:

- `artifacts/unattended/shared-eye-cull-enabled-20260901/`
- `artifacts/unattended/shared-eye-cull-disabled-20260901/`
- `artifacts/unattended/shared-eye-cull-ab-analysis-20260901/metrics.json`

The phase-aware analyzer uses PPM modification times and the logged benchmark
start to pair headings, refines the remaining pure-yaw offset in camera space,
fits exposure only from the center, and measures the outer 16% strips. Four
static-scene comparisons cleared the conservative 0.65 correlation gate: both
eyes at two adjacent door/candle headings. Outer disabled-cull pixels had a
mean signed residual of -0.46 luma after normalization, so they were slightly
brighter on average rather than systematically darker. Visual inspection also
kept the same warm candle and cool wall-light volumes in both eyes as they
approached the edges. This is a useful no-HMD negative result, not worn
acceptance: the fresh enabled log explicitly used
`projection=primary_projection_fallback`, not headset runtime frusta.

After four warm-up report windows, the Lua performance probe averaged 0.1848 ms
pair work with shared culling disabled and 0.2276 ms enabled, a roughly 0.043 ms
preparation difference. This agrees with the established full-GPU result that
the corrected shared camera is not a material performance regression. The
production flag was restored to `enabled` before the disabled run ended.

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\tools\stereo\set-shared-shadow-cull-probe.ps1 -Mode Disabled
.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 180 `
  -GameStartTimeoutSeconds 240
# pass: shared=false, full deterministic spin, owned game closed

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe `
  .\artifacts\unattended\shared-eye-cull-disabled-20260901\t05 1
# pass: adapter=NVIDIA GeForce RTX 4090, ready 1 -> 2

.\tools\stereo\set-shared-shadow-cull-probe.ps1 -Mode Enabled
.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 120 `
  -GameStartTimeoutSeconds 240
# pass: shared=true, full deterministic spin, owned game closed

python .\tools\stereo\analyze-shared-eye-cull-ab.py `
  .\artifacts\unattended\shared-eye-cull-enabled-20260901\revolution `
  .\artifacts\unattended\shared-eye-cull-disabled-20260901\revolution `
  .\artifacts\unattended\shared-eye-cull-ab-analysis-20260901 `
  --enabled-start 2026-09-01T10:29:17.575+10:00 `
  --disabled-start 2026-09-01T10:21:41.588+10:00
# pass: 42 analyzed, 4 accepted static pairs, mean correlation 0.7699

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-release `
  --target darktidevr-shared-eye-capture
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe' `
  --build --preset windows-vs2022-debug
# pass: Release capture target and complete Debug build

& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir .\build\windows-vs2022 -C Release -I 1,29 `
  --output-on-failure
& 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe' `
  --test-dir .\build\windows-vs2022 -C Debug -I 1,29 `
  --output-on-failure
# pass: 29/29 in both configurations; headset tests 30-32 not run
```

Quest remained offline. Listener PID `27460` was healthy, `adb devices` was
empty, and no sleep override was changed. The next headset-backed run still
must validate the runtime-frustum light edges, advancing `shared_ready`, the
new selective glove presentation, proxy/equipment poses, reticle cases, menu
pointer alignment and fixed-HUD depth.

### 09:50 remaining shop families and Escape landing coverage

A second authenticated offline dual-view hub run cycled every remaining vendor
family. Contracts, Armoury, Cosmetics, Barber and Hadron each selected mode 5
at a `2112x1188` source; the premium store selected mode 6 at `2112x1188` as
intended for its native-aspect layout. Each full 1920x1080 window capture was
complete and readable. Every close returned to mode-1 stereo world, with no
menu failure or timeout in the fresh log.

Hadron's widget inventory reported callable `option_button_1` and
`option_button_2` hotspots. Triggering `option_button_1` opened
`crafting_mechanicus_modify_view`; the final capture contained the complete
inventory, item-detail and action panels. The guarded close path then closed
the child and parent in order. The Escape/System landing page also rendered
completely in mode 5 and returned cleanly to stereo mode. A worn headset is
still required to accept laser alignment, the Options child pointer transform,
and perceived text scale.

Retained full-window captures are under:

- `artifacts/unattended/menu-contracts-20260901/full-window.png`
- `artifacts/unattended/menu-armoury-20260901/full-window.png`
- `artifacts/unattended/menu-cosmetics-20260901/full-window.png`
- `artifacts/unattended/menu-barber-20260901/full-window.png`
- `artifacts/unattended/menu-store-20260901/full-window.png`
- `artifacts/unattended/menu-crafting-20260901/full-window.png`
- `artifacts/unattended/menu-crafting-entreat-20260901/full-window.png`
- `artifacts/unattended/system-menu-20260901/full-window.png`

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 300 `
  -GameStartTimeoutSeconds 240
# pass: authenticated hub reached; owned game closed; run flags restored

# Runtime vendor commands, with `close` after each family:
contracts
armoury
cosmetics
barber
store
crafting
crafting_widgets
crafting_entreat

# Runtime system-menu commands:
open
close

rg -n 'DARKTIDEVR_(MENU_INPUT|PRESENTATION).*?(failed|timeout|error)' `
  $freshLog
# no matches
```

The run-owned game exited, hidden Quest listener PID `27460` remained healthy,
and no sleep override was changed.

### 09:56 fixed-HUD offline lifecycle revalidation

The default-off HUD panel was revalidated under the launcher's run-scoped gate
during an authenticated offline dual-view hub spin. The module created a
`2112x1188` render target, moved the one retained fixed record with zero
failures, and preserved the partition that keeps interaction, world markers
and nameplates in the spatial per-eye pass. Its world surface remained 2.0 by
1.125 m at one metre.

A mid-run `disable` consumed cleanly; `enable` then rebuilt generation 2 and
again logged `retained_transfer moved=1 failed=0`. No HUD error or Lua traceback
occurred. Typical warmed combined GPU medians remained around 15--17 ms, within
the established hub-spin band. The flat mirror cannot establish perceived
binocular depth or fully populated combat-HUD coverage, so this is a mechanical
lifecycle/performance pass only; keep the feature default-off until a worn
Psykhanium acceptance run.

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -EnableHudPanel `
  -DurationSeconds 180 -GameStartTimeoutSeconds 240
# pass: generation 1, runtime disable, generation 2 re-enable;
# owned game closed and HUD/performance/offline flags restored
```

Retained mirror evidence is
`artifacts/unattended/hud-panel-offline-20260901/full-window.png`; it is useful
only for confirming that the scoped panel did not replace the world with an
opaque target. It is not worn-HUD acceptance.

### 10:04 dedicated glove attachment enabled

The authenticated offline garment logs resolved the two previously anonymous
arm-shaped upper-body attachments. Attachment 2 is the full sleeve/arm item
`content/items/characters/player/human/gear_arms/astra_upperbody_career_02_arms`.
Attachment 4 is the dedicated glove item
`content/items/characters/player/human/gear_hands/astra_gloves_b`, backed by
`content/characters/player/human/attachments_gear/gloves/astra_gloves_b/astra_gloves_b`.

The launch partial-body visibility path now keeps only upper-body attachment
items whose resource path contains `/gear_hands/`. The torso, shoulder-to-wrist
sleeve and accessory attachments remain hidden. The authoritative source hand
nodes are already copied from the controller-owned proxy after its pose write,
so this glove unit follows the same hand/weapon transform without adding a
second animation timeline or spawning a speculative catalog item. The source
gate now fails closed if that selective glove rule is removed.

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

git diff --check -- `
  .\mods\darktidevr_stereo_probe\scripts\mods\darktidevr_stereo_probe\darktidevr_stereo_probe.lua `
  .\tools\stereo\test-darktide-lua-source.ps1
# no whitespace errors; existing LF-to-CRLF warnings only

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 150 `
  -GameStartTimeoutSeconds 240
# pass: glove_units=1 hidden_units=10, no Lua error, owned game closed
```

This no-headset run validates resource selection and visibility only. Per the
project safety agreement, do not accept the Lua launch change until a fresh
headset-backed log contains initialization messages, nonzero advancing
`shared_ready`, continuing `equipment_hand_owner=tracked_proxy` zero-error
samples, and a worn confirmation that both gloves follow the controllers
without revealing the sleeve/upper arm.

### 11:50 source-root-scale seam correction accepted offline

The residual source-equipment seam was not an IK or update-order error. Runtime
diagnostics found a uniform `1.08,1.08,1.08` scale on the gameplay source root,
while the hands-only profile proxy and both hand parents were `1.00`. The
world-to-parent-local attachment conversion omitted that source-root scale,
which produced the observed 8%-of-arm-length error. A second post-update write
was tested and rejected because it did not improve the residual.

`presentation.sync_equipment_hand_to_proxy` now divides the parent-space target
position by the guarded source-root scale before writing the source hand node.
The fresh authenticated private-range run logged `0.000000 m` for both hands on
the first sync and a maximum of `0.000001 m` over 7,200 syncs. There was no Lua
error, the proxy surface remained hidden, the dedicated gameplay gloves and
stock equipment remained visible, and direct shared-eye readback advanced from
ready 1 to 5 across four binocular pairs.

Evidence:

- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-01.47.22-14792231-a882-4867-b32f-f37acce07576.log`
- `artifacts/unattended/psykhanium-neutral-scale-corrected-20260901/`

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-synthetic-controller-publisher.exe `
  --seconds 420 --weapon-aim-matrix --neutral-body-pose

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -SyntheticWeaponAimMatrix `
  -DurationSeconds 150 -GameStartTimeoutSeconds 300

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe `
  artifacts\unattended\psykhanium-neutral-scale-corrected-20260901 4 2112 2304
# pass: pairs=4 initial_ready=1 final_ready=5
```

This closes the no-headset positional seam gate. Final acceptance still needs
the Quest: fresh initialization, advancing nonzero `shared_ready`, continuous
tracked-proxy ownership and a worn inspection of both gloves/equipment.

### 11:58 performance trace and first comprehensive-audit fix

The continuing heartbeat now treats quantitative performance and a broad bug
hunt as the two primary workstreams. A new 120-second authenticated offline
dual-view hub-spin run enabled native pass tracing and completed with owned game
cleanup plus restoration of all run-scoped flags.

The sampled pair contained both sequential render segments in one profiler
capture. Direct-queue timing was 2.947 ms for render eye 1 followed by 4.012 ms
for render eye 0 (+1.065 ms on the second segment). The second segment had fewer
recorded PSO binds (524 versus 746), while 144/154 unique PSOs overlapped
(Jaccard 0.935). This is new independent support for the earlier reversed-order
result: the excess follows second-in-frame finalization rather than physical
right-eye scene complexity.

The comprehensive sweep also found a diagnostic correctness bug. The analyzer
labelled this combined profiler record `Eye 0` and did not expose the segment
duration delta. `analyze-gpu-batch-trace.py` now labels mixed records as timing
captures and reports render order, duration delta, bind delta and PSO overlap.
`test-analyze-gpu-batch-trace.py` locks the combined-capture format down.

Evidence:

- `artifacts/unattended/performance-pass-trace-20260901-1155/darktidevr-focused-draws.log`
- `artifacts/unattended/performance-pass-trace-20260901-1155/gpu-batches.json`
- `artifacts/unattended/performance-pass-trace-20260901-1155/gpu-batches.md`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-01.54.36-ab04783b-45cd-4c38-bf5f-d32c63626dc6.log`

Validation performed:

```powershell
.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -EnablePerformancePassTrace `
  -DurationSeconds 120 -GameStartTimeoutSeconds 300

python .\tools\stereo\test-analyze-gpu-batch-trace.py
# analyze_gpu_batch_trace_tests=pass

python -m py_compile `
  .\tools\stereo\analyze-gpu-batch-trace.py `
  .\tools\stereo\test-analyze-gpu-batch-trace.py

git diff --check -- `
  .\tools\stereo\analyze-gpu-batch-trace.py `
  .\tools\stereo\test-analyze-gpu-batch-trace.py
# no whitespace errors; existing LF-to-CRLF warning only
```

### 12:09 native fence recovery and launch-cleanup audit

The native lifetime sweep found that the XR consumer rejected poisoned shared
fences only while initially opening them. If either attached D3D12 fence later
returned the device-removed sentinel `UINT64_MAX`, the frame loop treated it as
a newer ready value and could queue a permanently impossible cross-device wait.
The bridge now exposes one tested fence-health contract. Every XR frame checks
both eye fences, detaches a poisoned generation, clears readback and rendered-
pose correlation state, and immediately retries the producer's named resources.
The shared-menu and standalone direct-capture paths use the same fail-closed
check.

The launch sweep found a separate safety leak: `-EnterPsykhanium` armed its
one-shot file before protected launch work and never restored its prior state.
A failure before Darktide started could silently arm the next ordinary launch
for a private-range transition. The script now preserves and restores the exact
prior state. An isolated fake-game-root test deliberately failed on the missing
executable and confirmed `enter` returned to `consumed`.

Release and Debug bridge/harness builds pass. Both complete non-headset suites
pass 30/30 when run serially. Running the configurations concurrently is not a
valid shortcut: `shared_head_pose` and `window_capture_recovery` use global
named OS resources, and the parallel attempt produced one false collision in
each configuration; both tests immediately passed in isolation. A real
authenticated offline producer smoke using the rebuilt capture utility copied
three binocular pairs and advanced the ready fence from 1 to 4. The run restored
its flags and closed Darktide.

Evidence:

- `artifacts/unattended/shared-eye-fence-health-smoke-20260901/`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-02.07.32-80f0910e-e087-4a54-b003-53392c143773.log`

Validation performed:

```powershell
cmake --build build\windows-vs2022 --config Release --target `
  darktidevr-shared-eye-surfaces-tests `
  darktidevr-shared-eye-capture darktidevr-xr-harness
cmake --build build\windows-vs2022 --config Debug --target `
  darktidevr-shared-eye-surfaces-tests `
  darktidevr-shared-eye-capture darktidevr-xr-harness

ctest --test-dir build\windows-vs2022 -C Release -I 1,30 `
  --output-on-failure
ctest --test-dir build\windows-vs2022 -C Debug -I 1,30 `
  --output-on-failure
# pass: 30/30 in each configuration, run serially

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 45 `
  -GameStartTimeoutSeconds 300

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe `
  artifacts\unattended\shared-eye-fence-health-smoke-20260901 3 2112 2304
# pass: initial_ready=1 final_ready=4
```

The active Quest is still required to exercise actual in-session poison/reopen
recovery and worn presentation. The next offline audit target is Lua proxy/menu
teardown and reacquisition, followed by healthy-but-stalled mailbox recovery.

### 12:14 Lua proxy failure-generation reacquisition

The Lua teardown sweep found a same-mission lockout. A transient
`UIProfileSpawner.update` failure intentionally cached `failed_source_unit`
after destroying the partial spawner, preventing a faulting respawn on every
active frame. The disabled/invalid-owner path only called `safe_destroy` when
`profile_spawner` still existed, so toggling presentation off could not clear
that cached generation. Toggling back on for the same player unit remained
permanently rejected.

The invalid-owner boundary now tears down when any spawner, proxy unit or
cached failed source remains. This preserves active-frame fail-fast behavior
but lets an explicit disable or source invalidation establish a clean retry
generation. The fail-closed Lua source test asserts the reset contract.

A fresh authenticated hub run deployed module hash
`F0D99C19F4553F05BBDFE0517569FAECD89BE0BD75E8934991FE72C0BC033BC5`,
logged synchronized sequential stereo, hid the proxy surface, completed the
tracked-hands proxy ready transition and emitted no Lua error. Direct binocular
capture advanced the producer ready value from 1 to 3. The script restored its
flags and closed Darktide.

Evidence:

- `artifacts/unattended/proxy-reacquire-source-smoke-20260901/`
- `C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-02.12.49-7cc05633-ddb9-4523-b17e-fff2a1ce7327.log`

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
# pass: file_scope_locals=198 limit=198 syntax=luaparse modules=4

.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 30 `
  -GameStartTimeoutSeconds 300

.\build\windows-vs2022\tests\xr_harness\Release\darktidevr-shared-eye-capture.exe `
  artifacts\unattended\proxy-reacquire-source-smoke-20260901 2 2112 2304
# pass: initial_ready=1 final_ready=3
```

The exact injected streaming-failure toggle remains a headset/live diagnostic
case; the source reset contract and normal fresh proxy generation pass offline.

### 10:10 edge-lighting capture boundary

A controlled regression run started with `shared_shadow_cull=disabled` and
logged the deterministic offscreen eye workload through repeated 20-second
revolutions. Four fixed-delay captures were taken from Darktide's desktop
window. They retained the same stock world view while the offscreen angle logs
advanced; only the FPS overlay changed. That proves the no-HMD desktop window
is not a valid source for visual A/B of the production eye surfaces.

The incomplete screenshots are explicitly marked invalid in
`artifacts/unattended/lighting-cull-ab-20260901/README.md`. Do not compare their
edge luminance. The run remains useful as the disabled timing leg, matching the
previous conclusion that the shared cull union has no meaningful warmed pair
cost. `tools/stereo/set-shared-shadow-cull-probe.ps1 -Mode Enabled` restored the
production flag before the run ended, and the run-owned game closed normally.
The visual lighting gate still requires direct shared-eye readback or the Quest.

### 09:42 offline Penances and Psykhanium landing coverage

An authenticated 150-second offline dual-view hub run exercised the remaining
NPC-specific menu entry paths without requiring the Quest. `penance_overview_view`
opened in mode 5 at `2112x1188`, rendered a complete readable Penances page,
and closed cleanly. `training_grounds_view` then opened with the same mode and
source dimensions and rendered the complete Psykhanium mode-selection landing
page. There was no blank presentation or frozen previous frame in either
capture.

Retained screenshots:

- `artifacts/unattended/penance-offline-mode5-20260901.png`
- `artifacts/unattended/psykhanium-offline-mode5-20260901.png`

Validation performed:

```powershell
.\tools\stereo\start-darktide-vr.ps1 `
  -OfflineDualViewBenchmark -DurationSeconds 150 `
  -GameStartTimeoutSeconds 240
# pass: hub reached, Penances and Psykhanium landing views opened in mode 5;
# run-owned game closed and temporary flags restored

# Runtime commands written to darktidevr_open_vendor_menu.flag:
penances
close
psykhanium
```

Do not use the runtime command to enter the actual Psykhanium range after a
public hub has populated. Per the project safety agreement, use
`start-darktide-vr.ps1 -EnterPsykhanium` only while Darktide is closed. The
nested mode-button and laser/pointer alignment checks remain headset/worn
acceptance work.

Quest remained offline. Hidden listener PID `27460` was still active and no
sleep override was changed.

### 14:42 final native lifetime validation

The saturated desktop-eye mirror path previously registered a temporary Win32
event with a D3D12 fence and closed it even when its bounded wait timed out.
Because the fence retains that event registration, a later completion could
signal an unrelated handle that Windows had recycled. The mirror now uses a
persistent thread-local event, resets it before registration and validates the
completed fence value before slot reuse. Keeping the event thread-local also
avoids introducing a cross-thread lock-order cycle with the mirror state lock.

Both configurations were rebuilt after all hot-hook, command-list lifetime and
mirror lifetime changes. Debug and Release tests 1-30 pass 30/30. The Lua/source
gate still passes at 198/198 file-scope locals. OpenXR runtime tests 31-33 remain
deferred while no Quest is connected. Hidden Quest listener PID `34624` remains
active through 23:59:59 local time and has not changed the sleep override.

Validation performed:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1

cmake --build build\windows-vs2022 --config Debug
ctest --test-dir build\windows-vs2022 -C Debug --output-on-failure -I 1,30

cmake --build build\windows-vs2022 --config Release
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure -I 1,30
# pass: 30/30 in each configuration
```

The rebuilt Release DLL (`98462CEA87E6BB745C60EA907F5CC9CFD0093595E3DD194AC2DFC37B6C0F24DE`)
then completed a fresh 45-second authenticated offline dual-view hub spin.
Synchronized sequential stereo initialized with `ready=1`, the boundary path
completed 2,104/2,104 captures, and the log contained no mod/Lua error, DRED,
device-removal or page-fault signature. Nine warmed callback windows averaged
0.0434 ms left, 0.0043 ms right, 0.1944 ms per pair and 0.3182 ms reported pair
p95. Evidence log:
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-04.33.48-9306989c-14f3-4f39-aae5-656fe5e3c7ac.log`.

### 14:48 swapchain caching and presentation liveness

The native `Present` hook was repeating `GetDevice`, `QueryInterface`,
`GetDesc`, every back-buffer `GetBuffer` and two map rebuilds on every frame.
It now caches the complete buffer metadata by swapchain identity, invalidates
it around resize after releasing any retained back-buffer COM references, and
rejects partial enumeration. Release and Debug tests 1-30 pass. A live smoke
crossed six startup resizes, reached `ready=1` and 1,292/1,292 captures without
failure; evidence is
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-04.40.51-519c9c82-6616-492c-9385-89359006e6a0.log`.

The remaining presentation transport had writer generations but no liveness.
If Lua stopped while Darktide stayed alive, the compositor could preserve a
stale stereo/menu mode indefinitely and eventually trust the legacy projection
event. Transport v4 now timestamps each packet. Lua republishes unchanged modes
every 0.5 seconds, including ordinary stereo world; the compositor reuses a
cached packet only for 1.5 seconds and then fails flat. Heartbeats do not emit
mode-change log spam. Five direct read-only mapping samples during a live hub
run advanced sequence 168 -> 173 and publication time 334267046 -> 334269625
while mode stayed 1. The run reached 1,453/1,453 captures without a Lua, native,
DRED, device-removal or page-fault error. Evidence log:
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-04.46.03-2d11c739-0266-4cd4-9ede-43b8e3727235.log`.

### 14:55 diagnostic polling and remaining transport restart safety

The focused-trace request poll was still performing one temp-path query and
three filesystem probes on every `Present`, even in production mode. It now
runs on the first frame and every 30th Present, preserving sub-second operator
response at normal refresh rates without hundreds of filesystem calls per
second.

Two validation findings were also closed. Presentation crop containment now
checks crop width/height against the source before unsigned subtraction, so an
oversized extent cannot wrap and pass validation. Controller state v3 now has
an explicit writer generation and a compatible `dtvr_read_controller_state_v2`
export. Lua prefers the versioned path, clears old body-yaw/grip ownership on a
generation change, and blocks the first packet before resuming; this covers the
case where a restarted XR writer's first sequence equals the last old sequence.
Transport and native export regressions pass. A fresh live run loaded the v2
FFI path without its compatibility warning, reached `ready=1` and 1,639/1,639
captures, and emitted no Lua/native/device failure. Evidence log:
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-04.53.11-9a80e4ac-91b3-41fa-8a39-8e0d9765c45a.log`.

### 15:05 render-hook contention and edge-light audit

Production render-target binding no longer resolves every first RTV and takes
the shared capture mutex after both mod-authored eye finals have been learned.
The readiness hint is invalidated on either swapchain resize path, so output
discovery resumes after resource recreation. The legacy resource-barrier hook
now prefilters batches and skips the capture mutex for UAV/aliasing-only work;
the enhanced hook likewise skips it when a batch contains no texture barriers.
Those barrier kinds cannot contribute an eye-output completion or a swapchain
present transition.

Release and Debug were rebuilt serially after both reductions; tests 1-30 pass
30/30 in each configuration. The Lua/source gate passes at 198/198 file-scope
locals. Quest listener PID `34624` remains alive, still reports no headset and
has not changed the sleep override.

The far-edge lighting path was re-audited against the direct shared-eye A/B.
The standalone shadow/visibility camera already builds a conservative union of
both runtime asymmetric frusta and pads that cone for both translated eye
origins at the near plane. Headset-off direct-eye revolutions did not show a
repeatable enabled/disabled cull shutdown. The remaining high-probability paths
are therefore per-submission light-volume bounds derived from the asymmetric
render eye or a screen-space bounds test outside `shadow_cull_camera`; a worn
runtime-frustum direct-eye capture remains the decisive discriminator.

### 15:18 queue identity and restart-safe input transports

The first direct game command queue is now also retained as an atomic raw
identity backed by the existing `ComPtr`. Ordinary direct submissions bypass
`ID3D12CommandQueue::GetDesc` after discovery, removing roughly 1,400 virtual
calls per second at the observed 60 Hz / 23 submissions-per-Present workload.
An unread `swapchain_write_resources` map was removed. Barrier filtering,
queue caching and the preceding RTV hint pass Release and Debug tests 1-30.

Head-pose mapping v12 adds a monotonically incremented writer generation and
the DLL exposes `dtvr_read_head_pose_v2` while retaining the v1 wrapper. Lua
stores generation state on its existing presentation table and resets queued
eye tags when either the generation changes or the sequence regresses. The
regression destroys and recreates the writer, republishes the same sequence,
and observes generation N+1. A fresh authenticated hub run loaded v2 without
its compatibility warning, reached `ready=1` and 1,308/1,308 final captures,
and logged no targeted error. Evidence:
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-05.10.44-c0aeebf0-6542-45ad-8877-cb308b2ce420.log`.

The gameplay-input mapper had a separate epoch hole: a restarted controller
writer could arrive with a held trigger and generate a new attack press. It
now baselines the first packet of each nonzero transport generation. Held state
and necessary releases remain visible, while a new press is emitted only for a
subsequent physical transition. Release and Debug tests 1-30 pass after the
new held-trigger/release/repress regression. Lua remains at 198/198 locals.

### 15:30 fail-atomic head epoch and production telemetry gate

The head-pose writer constructor now enters an odd seqlock epoch before it
increments the shared writer generation. This closes the narrow startup window
in which a concurrent reader could otherwise accept a new generation attached
to the previous writer's payload. The source preflight fixes the ordering as a
contract and the destroy/recreate transport regression still proves equal
sequences from consecutive writers are distinguishable.

Two diagnostic counters were also still executing in normal production: one
atomic read-modify-write for every command-queue submission and another for
every tracked transition barrier. Neither counter participates in capture
correctness. They now run only when the immutable diagnostic-render-hook mode
is selected, so performance and observer launches retain their measurements
while ordinary play avoids roughly 1,400 queue counter operations per second
at the measured hub cadence plus its tracked-transition counter traffic.

After these changes, Release and Debug were built and tested serially; tests
1-30 pass 30/30 in both configurations. The fail-closed Lua/source check passes
with 198/198 file-scope locals and `git diff --check` reports no whitespace
errors. OpenXR runtime tests 31-33 remain deferred while Quest listener PID
`34624` is healthy but has not reported a connected headset.

### 15:50 real production-hook benchmark path

The offline two-view performance profile was not measuring the production hook
set: `performance_profile_requested` was included in the selector for the
entire diagnostic draw/root/descriptor detour group. Consequently even basic
callback/GPU timing installed thousands of diagnostic detours per stereo pair,
kept the queue/transition telemetry atomics active and prevented the newest
production fast paths from being exercised. The selector now reserves broad
render diagnostics for `performance_pass_trace_requested`; ordinary timing
still initializes native capture and GPU timestamp profiling through the
always-installed boundary path.

The hook installation audit found a second unnecessary production detour.
Stock menu capture installed both direct and indexed draw hooks, but the indexed
hook has no menu classification or redirect code at all. It is now installed
only for the diagnostic hook set. The source preflight pins both contracts.
Release and Debug tests 1-30 pass 30/30 after the native gate change, and the
Lua/source check passes at 198/198 after the profile-selector change.

An immediate diagnostic-versus-production pair proved the selector difference:
the first run reached `ready=1` with nonzero execute/transition diagnostics;
the corrected run reached `ready=1` and 1,137/1,137 captures while both stayed
zero. A longer exact-production run then completed more than three full 20 s
synthetic hub revolutions, reached 3,805/3,805 captures after six startup
resizes, and emitted no targeted Lua/native/DRED/device error or head-transport
fallback. Fourteen warmed callback windows averaged 0.0519 ms left, 0.0043 ms
right, 0.2031 ms per pair and 0.3094 ms reported pair p95. The immediately
preceding diagnostic run averaged 0.2346 ms per pair and 0.3621 ms reported p95
across seven warmed windows, so removing the broad diagnostics was directionally
worth about 0.032 ms mean pair callback work in this paired sample. Evidence:
`C:\Users\rober\AppData\Roaming\Fatshark\Darktide\console_logs\console-2026-09-01-05.31.44-e0fef612-2502-4efc-b6c9-036dabf9a68b.log`.

### 16:00 Quest wake-to-sleep-override handoff

The Quest listener selected whichever installed ADB client was currently
healthy, but the proximity helper independently hardcoded the Android SDK ADB.
That could detect a newly online headset through SideQuest ADB and then fail
the actual sleep-disable command through a different broken daemon. The helper
now accepts an optional explicit `AdbPath`, validates it, and the listener
passes its active client through to `-Action Disable` with the detected serial.

The PowerShell parser accepts both scripts and the Lua/source preflight pins the
same-client handoff while remaining at 198/198 file-scope locals. The previous
listener process was verified by command line before replacement. Hidden PID
`65692` is now polling every 10 seconds through 23:59:59 local time; its first
healthy selection was SideQuest ADB. No Quest has appeared and no proximity
override has been changed yet.

### 16:10 discarded menu command-list lifetime

The successful command-list Reset path retired camera-output and swapchain-
present state but omitted the equivalent named-menu completion maps. A command
list can be reset without its previous recording being submitted, so an old
menu resource could then be mistaken for output from a later unrelated
recording. Its retained COM reference could also obstruct subsequent resource
lifetime transitions. Both the menu resource and its source-state entry are
now erased only after `original_reset` succeeds, preserving the existing rule
that a failed Reset leaves the old recording owned by D3D12.

The fail-closed source check pins that ordering. Release and Debug builds
succeed and tests 1-30 pass 30/30 in each configuration. OpenXR tests 31-33
remain deferred until the Quest listener reports a runtime device.
