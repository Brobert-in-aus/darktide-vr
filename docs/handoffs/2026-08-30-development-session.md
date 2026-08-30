# 2026-08-30 development session

## Authenticated launcher automation

The installed Fatshark launcher was decompiled read-only to determine whether
it exposes a supported autoplay or direct authenticated-game option. It does
not. `Launcher.ArgumentHolder` parses `Environment.CommandLine` only to append
arguments to the game command line. `Launcher.App` always constructs the WPF
main window, and `Launcher.UI.OnLaunchButtonClick` owns settings persistence,
the protected/unprotected executable choice, game-argument construction and
process startup. Starting `Darktide.exe` directly therefore remains a rejected
route; no Steam ticket, backend authentication or EAC bypass was added.

`tools/stereo/invoke-darktide-launcher-play.ps1` now automates that normal Play
handler. It fails closed unless all of the following are true:

- Darktide is not already running;
- exactly one `Launcher.exe` resolves to the expected installed-game path;
- its main window exists and has the exact title `Launcher`;
- the current launcher client has the known 1.55--1.67 aspect range and is at
  least 1000 by 600 pixels; and
- a new `Darktide.exe` process appears before the startup deadline.

The current launcher does not publish an external accessibility tree. A
background `PostMessage` experiment was correctly rejected when WPF ignored
the queued click and no game process appeared. The retained helper foregrounds
the verified window, converts the stable normalized Play centre to client
coordinates, performs one real click and immediately restores the original
cursor position. It never uses a hardcoded desktop coordinate.

`start-darktide-vr.ps1` now invokes this helper by default after asking Steam to
run app 1361210. `-ManualLauncherPlay` restores the old manual step, while
`-DoNotOpenLauncher` retains its existing external-launch/testing meaning. The
desktop `launch-darktide-vr.ps1` entry therefore performs Steam launch,
Fatshark Play, game-start confirmation and XR attachment without user input.

Live validation used the installed 1400 by 870 launcher. The helper clicked
client position 1145,757, confirmed a new Darktide PID, and the fresh game log
entered `StateTitle` with `auth_platform = steam`. The launcher then exited.
`SendCrashReports = false` was reapplied only after all stale launcher
instances were closed; it persisted through this clean launch. Console logs
remain available. The non-XR validation game was closed cleanly and the normal
ten-second Steam cooldown was observed.

Validation commands:

```powershell
# Parse the three changed launch scripts with the PowerShell AST parser.
[System.Management.Automation.Language.Parser]::ParseFile(...)

Start-Process 'steam://rungameid/1361210'
.\tools\stereo\invoke-darktide-launcher-play.ps1 -TimeoutSeconds 120

git diff --check
```

Result: all three scripts parse, the native helper live test passed, and the
working-tree diff contains no whitespace errors.

The first complete wrapper run exposed one additional Windows foreground-lock
case: a background PowerShell process could not foreground the WPF launcher
with `SetForegroundWindow` alone. The helper now temporarily attaches its input
thread to the current foreground and launcher UI threads, restores and raises
the verified launcher window, then fails closed unless that exact window has
actually become foreground. It detaches both input queues before clicking.
This is the standard Win32 foreground-activation sequence and does not weaken
the launcher's path, title, geometry, single-instance, or PID guards.

The subsequent end-to-end wrapper test passed. Steam opened the authenticated
Fatshark launcher, the helper activated and clicked Play, Darktide entered
`StateTitle` and then `StateGameplay: hub_ship`, the stereo mod logged
`DARKTIDEVR_STEREO active` and `native_capture publishing`, and the XR harness
attached the shared-eye resources with increasing nonzero `shared_ready` and
fresh paired frames. This validates the self-service authenticated XR launch
path rather than only the isolated Play helper.

Additional validation commands:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 28800 `
    -EnableMenuInput -AutoEnterHub -DoNotOpenLauncher `
    -SkipDeploymentSync
```

Result: Lua source guard passed at 198/198 file-scope locals; the revised
launcher helper parsed; the authenticated wrapper reached live stereo in the
hub with nonzero `shared_ready`.

## Upper-limb IK industry comparison

The current architecture follows the usual tracked-avatar layering: preserve
the authored animation pose, treat head and hands as independent tracked
effectors, solve each arm as a two-bone chain, apply exact wrist transforms,
distribute axial wrist rotation over the rig's authored forearm twist bones,
and add bounded shoulder-girdle/clavicle contribution only near full reach.
Equal bilateral reach requests oppose and cancel at the girdle, while either
arm can independently request yaw and a small amount of clavicle protraction.

This is close to production practice in structure, but the shoulder layer is
not yet equivalent to a production full-body IK solver. It currently derives a
reach scalar from a hardcoded 94% arm-length threshold, rotates `j_spine2`
directly, and caps independent clavicle translation at 2 cm. A mature solver
would distribute competing hand effectors through a calibrated constrained
spine/shoulder chain using per-bone stiffness, anatomical rotation limits and
preferred bend angles. Darktide's heterogeneous character proportions also
make the planned T-pose/arms-down calibration important rather than optional.

The next production-quality refinement is therefore not another arbitrary
offset pass. It is a rig-specific constrained distribution layer: retain the
existing exact hand and twist behavior, derive per-avatar limb lengths from
calibration, give spine/chest/clavicle bones explicit stiffness and limits, and
validate unilateral, bilateral, crossed, overhead and tracking-reacquisition
paths. The current solution is an appropriate staged approximation for the
engine-access constraints, provided worn validation confirms its cancellation
and reach behavior.

## Scaled constrained shoulder solver

Worn validation confirmed that the first independent-request shoulder layer
was directionally correct but visibly approximate. It has been replaced by a
constrained distribution over the live scaled rig:

- each calibrated wrist remains an independent exact effector;
- arm length and shoulder width are measured from the current world-space
  bones every frame, after Darktide has applied the profile scale;
- shoulder participation begins at 90% of that arm's measured reach and is
  capped at 12% of arm length;
- opposing left/right requests determine a maximum 20-degree girdle yaw;
- yaw is distributed across common ancestors `j_spine`, `j_spine1` and
  `j_spine2` using 15/30/55 percent inverse-stiffness weights and explicit
  3/6/11-degree per-joint limits;
- equal bilateral requests cancel at the girdle, while unilateral reach
  advances that shoulder and retracts the other;
- each clavicle retains independent protraction capped at 3% of the measured
  arm length; and
- time-based exponential convergence prevents controller reacquisition from
  snapping the upper body.

The old implementation cached one shoulder local position and wrote it every
frame, which could suppress authored positional animation. The new path starts
from the current animation pose and detects whether the previous post-animation
offset persisted before removing it, so offsets neither accumulate nor freeze
the underlying pose.

Telemetry now records both arm requests, smoothed contributions, distributed
yaw, contributing spine chain, live unit scale, arm lengths and shoulder width.
`tools/stereo/test-body-shoulder-runtime.ps1` validates scaled geometry, all
three spine contributors, opposing unilateral yaw, bilateral cancellation and
continued exact hand tracking. The synthetic body path now contains explicit
left-only, right-only and equal bilateral forward reaches while retaining its
crossed-arm, full wrist-roll, out-of-range and tracking-loss coverage.

## Darktide character-height model

Darktide does not treat the character-creation height control as a camera-only
offset. `profile.personal.character_height` is selected from the breed's
`size_variation_range` and becomes the third-person unit's uniform scale. The
game then multiplies every named first-person stance height by that same scale.

The reviewed source defines:

- human body baseline 1.65 m, selectable profile scale 0.95--1.08, midpoint
  1.015, yielding an effective standing-height range of approximately
  1.544--1.756 m; and
- Ogryn body baseline 2.20 m, selectable profile scale 0.90--0.925, midpoint
  0.9125, yielding approximately 2.170--2.230 m.

The algebra in `PlayerHeight.player_character_third_person_scale` reduces to
the stored profile scale for both player breeds. The different authored rigs
and stance-height tables provide the human/Ogryn baseline difference. This
means the existing VR class-only `1.61 / 1.21` multiplier happens to be close
to the midpoint breed ratio, but ignores the individual character's height
slider and the physical player's proportions.

The production calibration model should use:

1. Darktide's live scaled skeleton/profile as the target avatar;
2. a standing headset-height and arm-span/T-pose calibration as the physical
   source; and
3. native tracked translation/IPD plus client-only visual body scaling for
   humans, and a coherent target/source tracked-space ratio only for Ogryn;
   arm reach remains a separate final retarget stage.

Until physical calibration exists, the shoulder solver uses live bone lengths
directly and does not change the already validated camera/world scale during
this test pass.

Source files reviewed:

- `_downloads/Darktide-Source-Code/scripts/settings/breed/breed_settings.lua`
- `_downloads/Darktide-Source-Code/scripts/settings/breed/breeds/human_breed.lua`
- `_downloads/Darktide-Source-Code/scripts/settings/breed/breeds/ogryn_breed.lua`
- `_downloads/Darktide-Source-Code/scripts/utilities/player_height.lua`
- `_downloads/Darktide-Source-Code/scripts/utilities/character_create.lua`

### Standing calibration retarget implementation

Shared head-pose transport v9 now publishes centre-eye height relative to an
OpenXR `STAGE` floor space. VirtualDesktopXR 1.0.10 exposes that space; a live
probe returned 0.924 m with the headset on the desk and the worn calibration
returned 1.818 m. The calibration UI reports this floor-to-eye measurement and
the measured arm span as explicit sanity checks. It does not mislabel eye
height as crown height.

Retargeting follows a fixed order:

1. Human avatars retain headset-native tracked translation and runtime IPD.
   Standing floor-to-eye height is first clamped to the breed's official slider
   range and sent through the same `ProfilesService:set_character_height` path
   as the hub barber. The live profile changes only after backend acceptance.
   Any remaining short/tall difference is a local, client-only visual scale;
   it does not rewrite an out-of-range backend value, first-person height,
   collision mover, broadphase, or network data. A defensive residual visual
   range of 0.70--1.40 supports unusually short/tall players.
2. Ogryn are the intentional world-scale exception. The selected profile scale
   is applied to the authored `2.20 / 0.9125` eye-height baseline, then target
   height divided by physical standing eye height scales head translation and
   runtime IPD together. This preserves the larger-character world scale using
   the exact selected height instead of the retired fixed `1.61 / 1.21` ratio.
3. Only after body/world scale is known, the live arm chain and shoulder width
   are compared with physical T-pose reach. A separate residual stretches the
   authored forearm/hand bone translations while leaving exact controller
   targets, IPD, head translation, collision, and network profile untouched.

Seated calibration deliberately does not infer stature from seated eye height.
It retains the breed/profile relative fallback until a standing measurement
exists. The first live human result reported 1.539 m arm span and 1.818 m
standing eye height. Its original 0.849 height/IPD result was rejected by worn
testing because it made the hands move opposite the head. Human tracking/IPD
is now fixed at 1.0; the same sample requests the official maximum 1.080 profile
height, then an approximately 1.119 total local visual body scale followed by
independent arm-bone length calibration.

The calibration preview now moves its translucent live head and hand markers
through `BaseView:_set_scenegraph_position`; directly mutating the raw
scenegraph position arrays did not propagate to the renderer. Target hands
switch from T-pose to arms-at-sides when the second capture step begins.

## Remote visibility of VR IK

Darktide's native player replication exposes locomotion and one
`aim_direction`. `PlayerUnitAimExtension` writes that field and
`PlayerHuskAimExtension` reconstructs the remote procedural aim constraint.
Dominant-hand weapon aiming can therefore be made visible to unmodded players
through the normal game path. Independent head, left-hand and right-hand poses
cannot be represented by the stock replicated state, so full VR embodiment is
not achievable on unmodified clients without game/server protocol support.

Full IK between peers running the mod is technically feasible, but there is no
ready-made Darktide mod transport. The checked-in DMF `network.lua` still marks
its network dictionary and user discovery functions `TODO`, while Darktide's
RPC and game-object field schemas are predefined. Reusing an unrelated
string-bearing RPC would be fragile, potentially server-visible and unsafe.

The preferred future design is a versioned native pose channel carrying root,
head and two wrist transforms at a bounded rate, with timestamps,
quantization, interpolation, tracking-validity bits and automatic fallback to
the stock husk animation. It also needs authenticated peer discovery and a
relay/NAT strategy; Darktide's party broadcast accepts an integer and string
payload but appears backend-oriented and must not be assumed suitable for a
high-frequency pose stream without an explicit rate/latency probe. A staged
implementation should first use the stock `aim_direction` for universal weapon
aim, then prototype the mod-to-mod channel in a private two-client session.

## Character-select calibration UI investigation

DMF provides the two engine-native pieces needed for calibration without
capturing a desktop menu:

- `DMFMod:register_view` can register a custom `BaseView` with normal retained
  widgets, controller focus, localization and persistent mod settings; and
- `main_menu_view` exposes an ordinary 1920x1080 scenegraph with terminal/ready
  button templates. A small pre-construction definitions hook can add a
  **Calibrate VR** button beside the existing character controls and open the
  registered view.

The implementation must live in a required module rather than adding more
file-scope locals to the 198/200-local stereo chunk. The calibration view will
remain in the already-proven flat interactive character-select presentation,
so the existing XR laser-to-cursor mapping can operate on it directly.

The first workflow should offer three explicit modes:

1. **Standing, both arms:** establish floor/standing eye height, then sample a
   neutral T-pose/arm span and arms-down rest pose.
2. **Seated, both arms:** preserve the seated headset baseline, omit standing
   floor inference, and use the same bilateral span/rest samples.
3. **Single arm:** select left or right, measure shoulder-to-controller reach
   over a comfortable horizontal extension, mirror that limb length for the
   unavailable side, and mark the saved calibration as inferred/symmetric.

Each step needs a live tracking-validity indicator, a short stable-sample
window rather than a single frame, retry/back controls, and a final preview of
physical source dimensions versus the selected Darktide avatar's live target
dimensions. Persist physical calibration per VR user/device and avatar target
mapping per character profile; do not overwrite physical IPD or the character's
authored height slider.

Reference implementations reviewed:

- DMF `modules/gui/custom_views.lua` and its `register_view` path;
- DMF's retained options widgets and persistent `mod:get`/`mod:set` settings;
- the community SoloPlay custom view for buttons, dropdowns and view lifecycle;
  and
- Darktide's stock `main_menu_view` scenegraph and terminal button templates.

Validation performed after the solver change:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
cmake --build --preset windows-vs2022-debug
ctest --preset windows-vs2022-debug --output-on-failure
```

The Lua guard passed at 198/198 file-scope locals. All directly affected
synthetic-controller and two-bone IK tests passed. The complete 30-test suite
passed 29 tests on its first run; the unrelated timing-sensitive
`shared_head_pose` stale-timeout test passed immediately on its bounded rerun.
A fresh in-game synthetic shoulder run passed with 200 parsed samples. The
left-only and right-only paths produced opposing girdle yaw (-2.37 and +4.79
degrees), equal bilateral reach settled at 0.00 degrees, and maximum
post-solve hand error was 0.000017 m. Worn validation accepted the behavior as
good enough for the launch baseline. Further tuning of shoulder stiffness,
limits and extreme-pose appearance is explicitly post-launch work rather than
a blocker for the remaining embodiment/UI implementation.

## Hub idle and room-scale follow revision

The accepted shoulder run exposed a stock `idle_fullbody` variant in which the
avatar takes a small lateral step and returns while the physical HMD remains
stationary. The hub VR path now holds only that full-body idle blend at zero for
the local player. Darktide's subtle base breathing/stance animation and all
moving locomotion animations remain intact.

Hub HMD translation is now reconstructed from the native bridge's bounded
camera delta plus its cumulative excess, then radially constrained to 0.25 m
in the Lua presentation adapter. The same constrained horizontal offset drives
the existing planted-foot pelvis/leg solve, producing a lean toward the head
without a step. `refresh_body_follow_mode` explicitly disables collision-root
body-follow writes in the hub, preserving the public server's authoritative
root and capsule. Gameplay maps retain their existing larger moving envelope
and collision-aware body-follow policy.

## Neck-pivot-aware crouch input

The headset is an eye/view tracker, not a direct torso-height sensor. Looking
up or down rotates the eyes through an arc around the upper neck, so feeding
raw HMD Y displacement into pelvis IK makes ordinary head pitch look like a
crouch or tiptoe. This is now handled as a source-skeleton problem rather than
a pitch dead zone:

1. estimate the neck point as `hmd_position - hmd_rotation * neck_to_hmd`;
2. compare it with the baseline captured for the current XR recenter
   generation; and
3. send only residual vertical neck travel to crouch IK.

This cancels the rigid eye arc through at least +/-45 degrees while preserving
a real simultaneous crouch. A pitch gate was deliberately rejected because it
would suppress real crouching whenever the user happened to look down. The Lua
adapter currently uses a conservative physical source model of 80.5 mm forward
and 75 mm upward until calibration records the user's proportions. It removes
that source-space eye arc in physical metres first and only then applies the
Darktide character scale to the remaining body translation. The live scaled
Darktide `j_neck` to eye-landmark vector remains a distinct target-rig
measurement; using it to explain physical HMD motion overcompensated the
synthetic 45-degree test by about 5-6 cm and was rejected.

Shared head-pose transport v8 adds an explicit recenter generation. Neck
calibration rebases on that generation, so resetting while tilted cannot create
a false height offset. Telemetry reports raw HMD vertical, compensated neck
vertical and removed arc separately. The future tiptoe channel must consume
this same compensated value; production currently authors only the existing
downward crouch solve.

Primary references:

- Khronos OpenXR view-space semantics:
  https://registry.khronos.org/OpenXR/specs/1.1/man/html/XR_REFERENCE_SPACE_TYPE_VIEW.html
- Meta Movement body calibration, distinct neck/head joints and source-to-
  target skeleton retargeting:
  https://developers.meta.com/horizon/documentation/unity/move-body-tracking/

Automated validation covers fixed-neck +/-45-degree pitch and verifies both
zero false height and exact preservation of a simultaneous 0.30 m crouch.

## Fixed-HUD renderer investigation

The retained fixed HUD did not migrate through resource-renderer draws,
retained-pass registration, source-renderer pass redirection, direct target
display, or a one-frame-lag display copy. An opaque diagnostic backing plane
proved that the VR panel itself rendered, while apparent text over it was a
separate spatial nameplate. The unsuccessful prototype is disabled by default.
Completion now requires rebuilding the retained HUD widgets for a VR-owned
renderer or locating their actual retained ownership boundary.

## Controller-authored ranged aim foundation

The shared controller state now retains the right body-relative aim position
and quaternion. Lua composes that pose with the immutable world/body anchor
without moving the HMD camera. A normal-off private-range module:

- replaces the local authoritative unit's stock replicated `aim_direction`;
- drives the local third-person aim constraint from the controller; and
- rebases Darktide's complete recoil, sway, aim-assist and randomized-spread
  delta from the first-person camera onto the controller rotation after
  `ActionShoot._prepare_shooting`.

The module loaded without Lua errors in a fresh authenticated run, automated
Psykhanium entry passed, stereo reached nonzero `shared_ready`, and synthetic
tracking remained valid. A melee probe followed the melee action class as
expected. The ranged weapon was equipped, but desktop input stopped before the
validating shot; ranged trajectory and worn alignment remain runtime gates.

## Tomorrow's priority queue

## Hybrid hub avatar ownership prototype

Live cadence and render-boundary traces ruled out a missed every-other-frame
IK solve: the body solver ran at 52.49 Hz while stereo published at 53.13 Hz,
and its solved transforms survived unchanged through both eye captures.  The
remaining flicker was instead visible ownership contention with the stock hub
animation graph.  A first isolation prototype now keeps Darktide's
authoritative lower body, gait, root and collision while hiding only the local
source avatar's arms/upper-body equipment.  A local `UIProfileSpawner` clone
loads the same profile's arms, torso and upper-body cosmetics, follows the
authoritative root, and receives the existing tracked torso/arm solve.

The initial stripped-profile attempt exposed two concrete engine invariants:
`slot_unarmed` must remain present so the profile spawner can establish a
wielded equipment record, and ignored hair must not request hair-state-machine
disablement.  The proxy now preserves the invisible unarmed plumbing, avoids
the absent hair access, and fails once per source unit rather than generating
an error every frame.  A fresh authenticated hub run then logged
`upper_body_proxy=active`, produced no subsequent Lua error, and reached
nonzero XR `shared_ready`.  Trace output confirmed that the proxy skeleton is
being solved continuously.  Worn validation is still required to confirm that
the stock legs remain visible, the original torso/arms are fully hidden, and
the proxy eliminates the torso/arm flicker without a seam at the waist.

Validation:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
git diff --check
.\tools\stereo\start-darktide-vr.ps1
```

The Lua guard remains at 198/198 file-scope locals; the new proxy module also
passes syntax validation.

### Worn hybrid result and ownership diagnosis

The worn gate failed: the user confirmed the entire visible avatar still
flickered while running, not merely the hands or the upper-body seam. A
frame-to-frame ownership probe then separated the two candidate authorities.
Across repeated 60-update windows the authoritative hub root changed by only
`0.000008--0.000022 m`, while `UIProfileSpawner.update` moved the proxy
`j_hips` by `0.214--0.251 m` between the previous tracked result and its own
animation result. The proxy was therefore running a second, incompatible
animation timeline; this is direct evidence, not a capture-cadence guess.

The next implementation stops advancing `UIProfileSpawner` after the profile
unit is ready. Each post-locomotion frame instead copies the authoritative hub
avatar's root and named hips/spine/shoulder/arm baseline into the proxy, then
applies the existing tracked upper-body solve. The hub skeleton remains the
sole gait authority and the proxy becomes a presentation retarget only. This
replacement passes the Lua source/syntax gate but still needs a fresh worn
flicker check.

## Native shop-panel source aspect and input

Hadron remained visibly compressed and controller interaction failed in a
diagnostic launch. The interaction trace showed no vendor callback because
that run omitted `-EnableMenuInput`; the supported release launcher already
sets this switch. A clean comparison run was therefore started with the
release-equivalent native controller-to-Windows input path rather than adding
another vendor-specific callback workaround.

New window-capture instrumentation measured Darktide's physical client at
`1280x768` during startup, but proved that it switches to `1280x720` once the
gameplay UI is initialized. The earlier 5:3 measurement was therefore a
startup-only red herring: live Hadron content and its 2.0 x 1.125 m quad are
both 16:9. `WindowCapture` still exposes the live client extent so panel fit
and pointer mapping remain correct across real window changes.

Hadron nevertheless remains visibly vertically compressed and native input
still misses. The remaining common upstream disagreement is that the stock UI
updates and hit-tests against the portrait per-eye `RESOLUTION_LOOKUP` before
that image is fitted into the 16:9 client. A pending mode-5 view-handler scope
temporarily presents the stock view update/draw with the authored 1920x1080
flat resolution, then immediately restores the eye globals for gameplay HUD
and stereo. Worn aspect and interaction validation remain open.

## Quantitative hub performance pass

The native D3D12 timestamp profiler now retains each eye interval and reports
median and p95 values as well as average/max.  Lua's render-wrapper timing does
the same for the actual paired wrapper samples.  Profiling remains opt-in and
was returned to `false` after the run; production therefore does not allocate
the timestamp sample vectors or issue GPU queries.

A fresh authenticated, stationary hub run with the hybrid proxy and body IK
active reached nonzero `shared_ready`.  Across the final twelve 240-frame
windows after warm-up, the median of the summed eye-interval averages was
26.998 ms (window range 26.075-28.414 ms).  The median sum of the per-eye p50s
was 26.390 ms and the median sum of the per-eye p95s was 34.873 ms.  Those two
summed quantiles are deliberately named `sum_of_p50`/`sum_of_p95`: they are not
claimed to be the quantile of a correlated pair distribution.  The Lua render
wrapper itself was small: median window average 0.273 ms, actual pair p50
0.242 ms and pair p95 0.564 ms.  Body/weapon IK averaged about 0.417 ms on the
CPU in the same run.

The per-eye attribution is not stable enough to call one eye intrinsically
more expensive.  Its split changes when presentation features are toggled
while the sum remains much steadier.  Likewise, the timestamp on the first
full-output-sized resource is only a structural resolution transition; it is
not a semantic boundary between world and post-processing.  Both eyes still
showed roughly 6-8 ms before that structural transition, evidence that the
prepared-frame path has not yet eliminated all duplicate scene setup/work, but
not evidence that those exact intervals are safe to pool.  The next
optimization step is therefore to identify resource/pass ownership around
that transition before attempting shared queues or parallel eye submission.

Validation:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture darktidevr-xr-harness darktidevr-core-math-tests darktidevr-synthetic-head-tests darktidevr-synthetic-controller-tests darktidevr-window-capture-tests
ctest --test-dir build\windows-vs2022 -C Release --output-on-failure -R 'core_math|synthetic_head|synthetic_controller|window_capture'
git diff --check
```

All four selected tests passed.  The production-clean source and DLL were
resynchronized after the profiling process closed and the mandatory ten-second
Steam shutdown interval elapsed.

1. **Thorough quantitative performance pass (first task).** Use repeatable,
   fixed-pose character-select, hub and Psykhanium captures after excluding
   shader/asset-streaming warm-up. Establish flat and stereo baselines, then
   isolate body IK, prepared-frame reuse, bridge submission/copy, each eye's
   pre-full/world work, post-full work and output processing. Refine the GPU
   timestamp boundaries so async queue ownership is not incorrectly attributed
   to one eye, and report median and p95 CPU/GPU costs rather than a single
   headline frame time. Include resolution scaling and controlled on/off
   comparisons, rank the costs against the observed frame budget, and identify
   the first evidence-backed opportunity for shared work, pooling, multiview or
   safe queue parallelism. Preserve visual parity and the fail-closed XR launch
   invariant throughout.
2. **Fixed:** horizontal HMD translation was restored in the latest pass. Keep
   this accepted 6DoF behavior covered while changing body animation ownership.
3. **Accepted:** the reduced, uniformly distributed arm-length retarget and
   increased bounded clavicle/shoulder reach contribution produced accurate
   hands and a good apparent arm length. Preserve this calibration balance.
   **New regression to trace:** during running, the torso and lower body visibly
   alternate/flicker while the hands remain well tracked. Compare animation and
   post-animation ownership at the two eye capture boundaries; do not assume
   the cause is the same as the earlier stale wrist-anchor defect.
4. Resume the shop-menu renderer and input path, followed by fixed HUD/UI and
   controller-authored ranged aiming.

## Hadron input, heading and generation-synchronised resume

Hadron's flat-interactive panel now has working controller interaction and no
longer receives the menu-opening trigger as a delayed synthetic primary press.
The harness disarms primary input on every presentation generation, adopts all
entry levels, and logs the physical trigger/desktop/test source for accepted
presses.

Shop cameras were proven to overwrite Darktide's mutable gameplay orientation.
The VR seam now retains a gameplay heading in the engine's own coordinate
system, advances it only from physical HMD yaw while the shop is open, and
atomically restores yaw/pitch/roll on exit. Worn testing confirmed that movement
direction survives Hadron close and the interaction-facing state is no longer
left at the shop camera's arbitrary yaw.

The rejected eight-pair resume delay was a heuristic and caused a single-slot
producer deadlock when settling pairs were not acknowledged. It has been
replaced by an explicit transport generation: Lua commits the restored gameplay
generation, the native producer stamps completed eye pairs with it, and the XR
harness retains the last valid stereo pair until the first pose-synchronised
pair with that generation arrives. Live resumes occurred in 20--21 ms. A very
brief mono flash remains perceptible in-headset; it is accepted for the current
milestone and logged as a future transition-quality refinement rather than a
blocker for the next feature.

Validation:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
cmake --build build\windows-vs2022 --config Release --target darktidevr_native_capture darktidevr-xr-harness darktidevr-shared-head-pose-tests darktidevr-panel-pointer-tests darktidevr-menu-input-tests
build\windows-vs2022\tests\shared_head_pose\Release\darktidevr-shared-head-pose-tests.exe
build\windows-vs2022\tests\panel_pointer\Release\darktidevr-panel-pointer-tests.exe
build\windows-vs2022\tests\xr_harness\Release\darktidevr-menu-input-tests.exe
```

## Next-session shop and Escape-menu preparation

Hadron's accepted presentation is now treated as a policy rather than a
Hadron-specific renderer exception: capture the physical client once, present
it on the 16:9 mode-5 panel, and map the XR ray through the same source crop.
Darktide's interaction templates and registered view transitions identify the
following explicit families:

- Hadron: `crafting_view` and every `crafting_*` child;
- armoury: `credits_vendor_background_view`, `credits_vendor_view` and
  `credits_goods_vendor_view`;
- contracts/marks: `contracts_background_view`, `contracts_view`,
  `marks_vendor_view` and `marks_goods_vendor_view`;
- cosmetics: `cosmetics_vendor_background_view` and `cosmetics_vendor_view`;
- barber: `barber_vendor_background_view` and `character_appearance_view`;
- premium store: `store_view` and `store_item_detail_view`.

These identities now enter mode 5 before the older world-anchor/menu
classifiers can claim them. Historical live logs confirm `store_view` and
`credits_vendor_background_view` are current runtime names; the latter had
previously been forced into the rejected mode-4 world-menu route.

The Escape-menu review found the same split-policy defect directly:
`SystemView.on_enter` published mode 4 while the active-view classifier
published mode 5 for `system_view`. The class lifecycle now publishes only the
captured-client mode 5, matching the temporary character-select-style fallback
the user accepted. It retains the generation-synchronised gameplay resume on
exit. Both changes pass the 198-local Lua source gate but still require a fresh
worn launch.

Tomorrow's live order is deliberately narrow: armoury landing and one child;
contracts landing and one child; cosmetics landing and one child; barber;
premium store plus item details; then repeated Escape open/input/close. For
each, check aspect, pointer alignment, trigger/scroll/back, absence of delayed
opening input, heading after exit, and stereo-resume latency. Stop on the first
family-specific failure and use its exact view stack from the console log;
do not broaden the native shader classifier.

### Fixed-HUD immediate replay candidate

The retained-HUD failure now has a concrete ownership explanation. A retained
widget's ID is created against the stock `gui_retained` and its original render
pass; changing `UIRenderer.base_render_pass` later cannot migrate that record.
The disabled prototype was therefore asking valid retained IDs to populate a
target they never owned.

The prepared replacement keeps the stock HUD as the only update/event owner.
For a once-per-pair fixed-HUD replay it temporarily marks only the fixed
elements as non-retained, draws their existing live content through the source
immediate GUI into the VR-owned resource pass, then restores every retained
flag and renderer field even on failure. Spatial elements continue through the
normal per-eye pass. This avoids duplicate event registration, duplicate input
consumption and a bespoke recreation of every Darktide HUD widget. It remains
disabled until the higher-priority shop, Escape and hybrid-body worn gates are
complete.

The fail-closed Lua preflight now parses all four modules loaded directly by
the stereo chunk (`body_proxy`, `calibration`, `controller_aim`, and
`hud_panel`) rather than checking only the main chunk and body proxy.

### Ranged-aim audit

The private-range controller-aim path now mirrors Darktide 1.12.5's
`ActionShoot._prepare_shooting` ownership rule for simultaneous projectile
groups. Darktide computes recoil, sway, aim assist and spread only for the
first projectile and deliberately reuses that prepared rotation for the rest
of the group. The earlier safe hook rebased every invocation, which could
compound the controller transform on reused projectiles. Later members of the
group are now left untouched and counted as `reused` in the diagnostic.

Shot telemetry also reports the distance between the tracked controller aim
origin and Darktide's still-stock `shooting_position`. This deliberately does
not move the gameplay origin yet: the next Psykhanium test can now distinguish
a correct controller-authored ray from a remaining head-origin/muzzle-origin
discrepancy before choosing a weapon-specific muzzle policy. The fail-closed
Lua source check asserts that the simultaneous-fire gate remains present.

### Production draw-hook cleanup

The accepted cylindrical particle behavior is supplied by the independently
selected PSO-time vertex-shader replacements. The retired
`billboard_selector_probe` was nevertheless still enabled. Its mode-2 path
cannot write descriptors, but it installed the full diagnostic renderer hook
set and performed command-list, PSO, root-signature, descriptor and census work
under several locks for every direct, indexed and indirect draw. Production now
keeps shader substitution enabled while leaving that per-draw selector census
disabled.

The stock-menu draw hook is still required for interactive flat panels, but
ordinary gameplay no longer looks up and copies command-list/PSO metadata when
direct menu capture is inactive. Menu capture takes the same locked classifier
path only while a captured client is actually open. This change needs one worn
regression check that the already-accepted particles remain cylindrical, plus a
repeatable lobby/Psykhanium frame-time comparison; the source ownership makes
it an expected CPU-side win without changing either eye render.

Validation after the cleanup: Release native capture and harness builds passed,
the Lua fail-closed check remained at 198/198 file-scope locals, and all 30
CTest cases passed, including the three OpenXR smoke paths.

### Bootstrap ownership and contracts-family live gate

The first production-clean launch exposed a bootstrap/Lua ownership mismatch,
not an OpenXR failure. A stale installed
`darktidevr_diagnostic_render_hooks.flag` made the D3D12 proxy install the full
diagnostic hook set before Lua loaded; production Lua then correctly requested
diagnostics off and failed closed because installed hook topology cannot be
changed safely. `sync-darktide-vr-dev.ps1` now normalizes all three bootstrap
flags on every deployment: diagnostics and shader dumping default off, while
the independently required billboard shader substitution defaults on. A clean
launch then logged native hooks installed, applied the known cylindrical
replacement, attached shared eyes at ready value 1 and advanced fresh stereo
pairs with zero pose mismatches.

The guarded `contracts_background_view` run is the first non-Hadron family to
pass the generic mode-5 transport gate. It published a 2496x1404 (16:9) source
on the 2x1.125 m panel, opened and closed without script errors, kept the eye
producer advancing, and resumed fresh gameplay stereo in 28 ms with a
three-ready-value generation advance. The guarded family harness now also
addresses armoury, cosmetics, barber, marks and premium-store landing views so
they can be tested one at a time without avatar navigation or controller
tracking. This expands evidence collection only; it does not broaden the
native draw classifier.

Armoury (`credits_vendor_background_view`), cosmetics
(`cosmetics_vendor_background_view`) and barber
(`barber_vendor_background_view`) subsequently passed the same landing-page
gate: each produced the complete stock UI at the 2496x1404 source extent on the
unchanged 16:9 panel. Their stock desktop visuals were neither cropped nor
vertically compressed, and their open/close lifecycle stayed on mode 5.
Controller-ray interaction and child pages still need a worn check.

Marks is not directly constructible. Opening `marks_vendor_view` without the
parent-generated context failed in `item_grid_view_base.lua:23` (`context` was
nil), followed by a nil view instance in `ui_view_handler.lua:102`; the damaged
UI state later ended the run. The crash-prone `marks` shortcut was removed.
Future coverage must enter through `contracts_background_view` and select the
marks branch so the stock parent supplies its context. Premium store was not
reached before that run ended.

### Premium-store native-aspect split

The premium-store landing page rendered completely through the generic shop
capture, but the worn check found its cursor offset. This was a coordinate-
contract error rather than a family-specific hotspot problem. Mode 5 assumed
that every gameplay shop's landscape desktop capture encoded a portrait eye
surface; that assumption is true for Hadron but false for `store_view`, which
already authors a native 16:9 client. The panel therefore used portrait eye
geometry while the laser and Windows cursor used landscape source pixels.

The shared presentation protocol now distinguishes mode 5 eye-aspect
interactive panels from mode 6 native-aspect interactive panels. Both retain
the same input, capture, lifecycle and non-immersive projection policy. Only
mode 5 with attached eye surfaces uses the portrait eye extent; mode 6 always
fits the actual native client. `store_view` and `store_item_detail_view` select
mode 6, while Hadron and the other currently accepted families remain mode 5.
The XR laser, Windows cursor, Store scenegraph and semantic hotspot must all
stay in native landscape crop coordinates. The first mode-6 implementation
corrected panel aspect but then reapplied the mode-5 portrait-eye transform to
semantic hover. The worn symptom reproduced the earlier crop/full-eye failure:
laser and visible cursor agreed, while the highlighted target lagged to roughly
two-thirds of cursor X and one-quarter of cursor Y. That is a deterministic
coordinate-space error, not controller tracking drift.

Mode 6 now remains crop-local end to end. Only mode-5 gameplay shops retain the
portrait-eye transform. Store item cards are not owned by BaseView:
`StoreView._draw_grid` draws private `_grid_widgets` before the conventional
list. Its class-specific hook resolves the native-landscape ray against those
real cards and, while an XR ray is active, passes a null input service to the
stock grid draw so Darktide's mis-normalized Windows cursor cannot remain a
second hover owner. The BaseView full-grid catcher remains inert in mode 6.

The corrected source passes the 198/198 Lua fail-closed gate, both Release
native targets build, and all 30 CTest cases pass. It has not received a worn
test after the final correction. Tomorrow's first gate is premium-store card
hover at panel corners, trigger activation into item detail, scroll and Back;
then repeat Escape-menu open/input/close. Do not add empirical axis constants:
if the next hover is wrong, log the native card scenegraph rectangle and shared
pointer pixel in the same frame.
