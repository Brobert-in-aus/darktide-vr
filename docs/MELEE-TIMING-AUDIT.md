# Melee timing and charge audit

Inspected 6 September 2026 against local Darktide source revision `0f0cb45`.
These are source-derived thresholds, not stopwatch measurements of the user's
equipped weapon. All paths below are relative to that source's `scripts/`.

## Light attacks vary through the combo

`settings/equipment/weapon_templates/chain_swords/chainsword_p1_m1.lua`
has this ordinary light loop. Each next windup permits its light transition at
zero action time, so these are the unscaled action-to-next-action intervals:

| Sweep | Next windup | Interval (s) |
| --- | --- | --- |
| `action_left_down_light` | `action_melee_start_right_3` | 0.55 |
| `action_right_diagonal_light` | `action_melee_start_left_2` | 0.60 |
| `action_left_light` | `action_melee_start_right_2` | 0.45 |
| `action_right_down_light` | `action_melee_start_left` | 0.55 |

The four-step average is 0.5375 s, but using that average as every target's
cooldown would erase intentional per-action variation. The existing resolver
selects the observed windup's light action and follows its actual next windup.
The regression fixture now includes all four transitions. Attack-speed and
handling modifiers still come from the live action handler; these raw numbers
are not release defaults. Damage-window onset and full animation duration are
different quantities from the interval between chained attacks.

## Minimum heavy readiness is not full charge

`melee_action_input_setup_fast`, `_mid`, and `_slow` set the heavy hold threshold
to 0.30, 0.35 and 0.45 s respectively. These are input classification thresholds,
not light attack intervals. Their following release element has a 1 s window
and auto-completes if held past it. The base setup uses 0.25 s then 1.5 s.

The chainsword uses the mid input setup. Its heavy chain thresholds vary with
windup: 0.50, 0.40, 0.50, 0.45 and 0.40 s across left, right, left_2, right_2
and right_3. Fresh-hold minimum readiness is the maximum of the input hold
threshold and the effectively scaled heavy chain threshold. Already queued
input must be accounted for separately.

`extension_systems/action_input/action_input_parser.lua` advances the element
start timestamp when the hold completes, then auto-completes only *after* the
release window. Thus mid setup's fresh-hold automatic completion is later than
1.35 s, with fixed-step quantization; it is not the 0.35 s input minimum or a
0.45 s universal heavy timer. A slower chain gate can delay execution further.
The timing result now exposes `heavy_auto_complete_after` as a lower bound,
separate from `heavy_charge`. Missing or unbounded automatic release stays nil.
The opt-in diagnostic logs both without changing gameplay.

## Holding longer can increase damage through distinct mechanisms

`extension_systems/weapon/actions/action_sweep.lua` starts with `charge_level=1`
and reads the charge module only when the sweep sets `use_charge`. Ordinary
inspected chainsword sweeps do not enable it. This rules out a universal linear
damage ramp for ordinary heavy sweeps; it does **not** rule out extra damage
from holding longer:

- `utilities/attack/damage_calculation.lua` applies
  `melee_fully_charged_damage` to auto-completed heavy attacks. The Ogryn fully
  charged damage/stagger talent also listens for the sweep's
  `is_auto_completed` proc argument.
- `ActionWindup` emits `on_windup_trigger` beginning at its latest chain
  threshold, repeating at `proc_time_interval` or 0.25 s. The
  `windup_increases_power_parent` trait builds up to three power stacks from
  those events and clears them through stock sweep/action/wield lifetimes.
  A separate default windup-power buff is attached to the inspected crowbar.
  Longer holds can therefore grant stepped bonuses before automatic release.
- Actions explicitly using the charge module have their own delay, minimum,
  duration, maximum and charge-speed modifiers. Their charge value must come
  from that action context, not the minimum-heavy timer.

`heavy_damage_charge` now reports `constant_one` or `module` solely for the
argument supplied to stock damage. It is not a statement that final damage is
constant; buffs, profile selection, special state, armor and other stock inputs
still apply.

## Physical-melee integration requirements

Keep the user's per-enemy minimum-heavy cooldown and initial unavailable state.
Do not mark every eligible heavy contact auto-completed, continuously refill
fully-charged bonuses, or let one enemy's cooldown manufacture windup procs for
every other enemy. Charge progression and proc lifetimes belong to a deliberate
attack context, separately from per-target deadlines. Preserve actual combo
action identity when choosing its interval. The contact adapter still applies
no damage; contact calibration remains a worn check owned by the user.

Validation: Windows x64 CTest `melee_timing`, `melee_live_probe` and
`lua_source_compile` passed (27 pinned LuaJIT chunks). New coverage distinguishes
minimum versus automatic heavy thresholds, charge-module selection, slow chain
gates, missing/unbounded auto-completion and the varying four-step light loop.

## Combo graph and repeated windups

The timing module now exposes `light_combo`, starting from an explicitly
observed windup. It follows each ordinary light sweep and next windup, preserves
each step's action identity/effective interval, and reports the entry prefix
separately from the repeating loop. The default walk limit is 32 steps; a broken,
conditional, unavailable or over-limit route returns a reason and failure point
instead of a guessed common interval. This uses the existing conservative
windup validator, including its supported heavy-input requirement.

This is a current-context timing snapshot, not a new global attack clock or an
instruction to advance combo state once per contacted enemy. Future physical
damage integration must choose action lifetimes separately from per-enemy
cooldowns and resolve scales again when its live context changes.

The opt-in live probe previously refreshed only when the windup name changed.
It now also recognizes a changed stock `start_t`, so a repeated same-named
windup refreshes effective speed instead of retaining the previous entry's
diagnostic timing. Duplicate ticks within one entry do not rerun the resolver.
The combo diagnostic lists `action:interval`, entry duration, cycle start and
cycle duration; an unchanged report is suppressed. It remains non-damaging.

Validation: `melee_timing`, `melee_live_probe` and the 31-chunk LuaJIT gate pass.
Cases cover the four-step loop, a separate opener, action-specific scale
changes, exact traversal limit, missing/conditional transitions, and same-name
windup reentry. No equipped-weapon timing or physical contact was simulated.

Deployment hashes match for both timing and live-probe modules. Fresh range
initialization reached `shared_ready=667`, 44.2 fresh pairs/s, zero interval
fallback and zero pose mismatches, without matching mod errors. Evidence:
`artifacts/unattended/melee-combo-live-20260906.log`. The ordinary launch also
confirms menu stabilization is off; the earlier opt-in trial did not change
the default. Live combo reports still require an observed weapon windup.

## Actual stock timing contract, 7 September

`tests/tooling/test-melee-timing-stock-contract.lua` executes stock
`ActionHandler._calculate_time_scale` and `_validate_single_chain_action`, using
the stock gameplay cap settings and the VR timing resolver. Sixteen boundary
cases confirm rejection immediately before, and admission at, resolved sweep
and windup thresholds with several handling scales and inverted-kind fixtures.
Listed speed buffs add before multiplication by weapon handling; absent buffs
and unrelated buffs do not alter that calculation. The actual sweep cap applies.
Early alternative windows, running-state requirements and unavailable targets
retain stock admission behavior; the resolver conservatively rejects conditional
timing instead of presenting it as an ordinary interval.

```powershell
build/dependencies/luajit/src/luajit.exe tests/tooling/test-melee-timing-stock-contract.lua _downloads/Darktide-Source-Code mods/darktidevr/scripts/mods/darktidevr/darktidevr_melee_timing.lua
```

PASS on snapshot `0f0cb45991e9305ef4a7b925370792d7d6035f95`. Network min/max
values normally come from engine `Network.type_info`; this fixture supplies
distinct bounds to exercise the clamps, not to assert live wire bounds. Action
routes, inverted-kind membership, buffs and target availability are also supplied.
The contract does not load the user's weapon, simulate damage or replace worn
verification. No production change or deployment accompanies this check.
