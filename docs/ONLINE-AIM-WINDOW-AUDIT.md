# Head aim between attacks: feasibility

7 September 2026. User asks whether online play can accept a different firing
origin, and whether reported aim can follow the headset except on firing frames.
Investigation only; the live session retains continuous hand aim.

The audited input history contains one yaw/pitch/roll per simulation frame.
The server reconstructs first-person position from locomotion, character height
and stock peeking. No independent client-authored hand-origin field was found in
that route. Projectile spawn-node/offset settings are server weapon data;
changing those only on the client does not change official-server settings.
Arbitrary origin acceptance through another route remains unestablished.
Cosmetic staff-origin effects would not relocate authoritative collision,
especially near cover and close targets.

Headset aim between attacks and hand aim during the relevant simulation frames
is plausible through the existing input stream. One recorded choice must serve
local prediction, sending and correction replay. Changing local action fields
or previously sent frames would not achieve that. Movement, ledge checks and
attacks still share one server orientation per frame. Attack frames retain
stock aim-relative penalties and may introduce speed or steering transients.

## Actual staff timing

Source snapshot: `0f0cb45991e9305ef4a7b925370792d7d6035f95`. Live inventory
identified `forcestaff_p4_m1`; the user confirms reticle-directed shots from
the face and the expected movement penalty.

- `rapid_left`: `spawn_projectile`, nominal `fire_time=0.1`.
- `action_shoot_charged`: `spawn_projectile`, nominal `fire_time=0.2`.
- `ActionSpawnProjectile.start` creates sleeping projectiles on the server.
- `fixed_update` fires later, dividing timing by action time scale. For remote
  players it first subtracts `lag_compensation_rewind_s`, clamped at zero.
  Additional projectiles receive 0.1-second offsets before scaling.
- `_fire_projectile` reads the first-person pose again at launch. `finish` also
  has a fallback that fires a paid-for projectile if none has fired yet.

A trigger-press-only switch is insufficient. The user's proposed **actual
firing-frame** switch remains feasible in principle; identifying all relevant
frames ahead of simulation is the difficult part. A conservative hand-aim
interval covering attack preparation through final release is simpler than
isolated pulses, but leaves less time using headset aim. Charge targeting,
burst/automatic fire, alternate actions, finish paths and replay need coverage.
Official-server acceptance is not established by Psykhanium.

## Isolated scheduling check

`tests/tooling/test-staff-aim-window-stock-contract.lua` executes the actual stock
`fixed_update` across 48 cases: two delays, two action time scales, three rewind
values, one/two projectiles and two input policies. All 72 dispatches occur.
Hand aim only on the trigger frame leaves 32 later dispatch samples with head
aim in this matrix. Holding hand aim throughout the action covers every dispatch.
These counts are not real-world failure rates.

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-staff-aim-window-stock-contract.lua _downloads/Darktide-Source-Code
```

PASS on Windows x64. Optional source fixture outside ordinary CTest. Hypothetical
60 Hz timestep; action start/finish are not executed, firing dispatch is
substituted, and transforms, encoding, server validation, collision and damage
are not verified. No mod change or deployment.

Sources: [input history](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/managers/player/player_game_states/human_input_handler.lua),
[server pose](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/extension_systems/first_person/player_unit_first_person_extension.lua),
[staff actions](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/settings/equipment/weapon_templates/force_staffs/forcestaff_p4_m1.lua),
[projectile timing and pose](https://github.com/Aussiemon/Darktide-Source-Code/blob/0f0cb45991e9305ef4a7b925370792d7d6035f95/scripts/extension_systems/weapon/actions/action_spawn_projectile.lua).
