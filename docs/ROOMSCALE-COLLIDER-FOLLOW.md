# Independent tracking and ordinary-input collider follow

Offline candidate, 7 September 2026. The user closed Virtual Desktop and asked
that work switch to ranged weapons when further validation needs the headset.
This candidate has not been deployed or accepted in-headset.

## Behavior

Horizontal tracking moves the camera and both tracked hand anchors immediately.
The collider follows through the normal four packed movement input columns,
with a 0.10 m horizontal deadzone. Existing manual stick/keyboard movement takes
priority; the chase waits for its braking tail to finish before taking over.
It runs only during grounded walking with the existing Psykhanium online-rules
and local-player input ownership gates. Remote mission admission is unchanged.

The controller evaluates candidate analog inputs using the game's actual
`AcceleratedLocalSpaceMovement.wanted_movement` calculation on scratch state.
Each candidate predicts one driven step followed by neutral-input braking.
The stopping endpoint determines which input to send. Current axis acceleration,
deceleration, backward penalty, crouch speed, movement settings, buffs, weapon
movement modifier, and stock drag participate. A 1.5 m/s preferred speed cap
keeps large separations from requesting full walking speed. This is not a hard
velocity clamp: the game still owns actual movement.

Only measured horizontal collider displacement repays the visual offset.
Blocked motion therefore cannot pull the camera toward an unmoved collider.
Frame history replaces an existing contribution during correction replay;
it does not consume it twice. The renderer uses the contribution represented
in the stock first-person anchor, which is sampled before locomotion, to avoid
a one-frame reverse view displacement. No collider position, velocity, action
origin, damage result, custom RPC, or server head position is written.

Vertical tracking remains visual and produces no movement/crouch input. Valid
STAGE floor height also restores vertical travel outside the bridge's existing
1.2 m sliding camera envelope. Missing STAGE data holds that extra offset.
Physical crouch detection is deferred; existing button crouch remains stock.

Tracking offsets rebase on unit replacement, bridge epoch, explicit recenter,
or backwards sequence. New chase input stops after 150 ms without a new head
sample, on manual input, outside walking, airborne, during pushes or forced
movement, and on moving parents. A large single automatic movement step resets
the tracking baseline. Inputs already simulated can still decelerate normally.

## Offline validation

From the Windows repository root:

```powershell
& tools/stereo/test-darktide-lua-source.ps1
& tools/stereo/test-darktide-lua-invariants.ps1
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-roomscale.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_roomscale.lua
& build/dependencies/luajit/src/luajit.exe tests/tooling/test-roomscale-stock-contract.lua mods/darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_roomscale.lua _downloads/Darktide-Source-Code
```

All 39 mod chunks compile and source invariants pass. The core fixture covers
tracking basis changes, vertical excess, recenter/unit/epoch reset, invalid
samples, correction replacement, history expiry and large movement. The
optional stock fixture passes 45 combinations of 30/60/90 Hz, five aim bases,
and three weapon speed modifiers, including blocked movement, camera update
phase, repeated correction steps, settling, manual priority and stale tracking.
The fixture uses an explicit 8-bit analog quantizer and stubbed collision
displacement; it does not establish native wire precision or collision behavior.

The existing broad online-rules stock contract also passes. Nine focused CTests
pass: roomscale, Lua compile/invariants, gameplay heading, aim state transport,
ranged aim, grenade aim, hand roles and UI ownership (0.92 seconds). CMake was
configured with headset tests disabled; no native code changed or build was
needed. No full 123-test run is claimed.

## Required live checks

7 September, 18:45 Brisbane: the combined roomscale/ranged candidate is deployed
after Ready passed 600/600 frames. Fresh stereo and nonzero `shared_ready` are
confirmed in Psykhanium. The user has been asked for the first step/stop/staff
check; worn acceptance remains pending. See the current development handoff.

After the user resumes VD, pass Ready and deploy with the normal Lua gates.
Check fresh stereo initialization and nonzero `shared_ready`, then ask the
user to lean within 10 cm, step 30–60 cm, stop, turn the staff away from their
head, and repeat. Confirm free head/hand motion and smooth collider settling
without a view tug or oscillation. Check a blocked direction, stick movement
and release, button crouch, a physical height change, recenter, and VD resume.
Native allocation cost, collision behavior, mixed input transitions, and worn
comfort remain unproven. Official online-server acceptance remains separate.
