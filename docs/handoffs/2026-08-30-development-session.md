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
3. target/source ratios for tracked translation, reach and intentional avatar
   world scale, while retaining the headset runtime's measured physical IPD as
   the source measurement.

Until physical calibration exists, the shoulder solver uses live bone lengths
directly and does not change the already validated camera/world scale during
this test pass.

Source files reviewed:

- `_downloads/Darktide-Source-Code/scripts/settings/breed/breed_settings.lua`
- `_downloads/Darktide-Source-Code/scripts/settings/breed/breeds/human_breed.lua`
- `_downloads/Darktide-Source-Code/scripts/settings/breed/breeds/ogryn_breed.lua`
- `_downloads/Darktide-Source-Code/scripts/utilities/player_height.lua`
- `_downloads/Darktide-Source-Code/scripts/utilities/character_create.lua`

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
