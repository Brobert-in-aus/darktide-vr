# Item radial: built, reviewed, withdrawn, rebuilt (16 September 2026)

**Later the same evening: rebuilt on the generalised claim and re-wired.**
Every item under "What it would take" below is done; the sections after it
describe the first attempt and are kept as the record of why. The rebuilt
module takes the carried-items button through the bindings' contextual claim
with the `unbound` action, so for that press the control does nothing of its
own; the pick is delivered on release through the forced-action channel, and a
release with nothing picked delivers the control's own stock cycle, so a plain
tap still does what it did. The claim's own edges (`support_grip`) drive the
state, which closes without delivering on cancel; a pick only counts after the
stick has passed through neutral once; it is excluded from the hub; the button
is found by whichever of the item actions it carries; and it draws only while
the off hand tracks. A holster, two-hand or reach claim always takes the slot
first, and the two-hand grip is told a radial claim is not the support hand.
Worn check: checklist item 21.

The backlog item (todo-2026-09-14): "Holding the carried-items button shows a
radial at the hand; flick the stick to pick scanner, stim or carried item."

Built on 16 September as `darktidevr_item_radial.lua` with the test
`item_radial`, then **withdrawn before the worn session**: a review found that
the design cannot work against that control without a change to the bindings
that is too invasive to make untested. The module and its tests stay in the
tree; nothing installs or calls it, and it has no option, because an option
that does nothing is worse than none.

## Why it cannot work as written

1. **The carried-items control wields on press.** Its action
   (`pocketable_device`, mask 786432) is `device | cycle_pocketables`, both of
   which have `pressed` entries, and `presentation.device_wield_precedence`
   turns that press into a cycle step. So the moment the player holds the
   control to *open* the radial, an item is already wielded. Picking a sector
   then wields a second time: two swaps back to back, the first unasked for.
   The premise that "releasing without a pick falls through to the stock cycle"
   only appeared to hold because the cycle had already happened.
2. **The Device sector can never fire.** Its mask (262144) is a subset of the
   control's own 786432, which is in `api.held` for the whole hold, so
   `pressed = next_held & ~api.held` is zero for it. The one sector a player
   would reach for the scanner delivers nothing. Sectors 1 and 2 are outside
   the mask and do work, which would have made this look like a random fault.

Both have the same root: the control's own press is never suppressed.

## What it would take

- ~~**Generalise the contextual claim beyond the grips.**~~ Done the same
  evening: `Bindings.control_bit(id)` replaces the two-way grip conditional, so
  a claim may name any button. The grips resolve to exactly the bits that were
  hardcoded (512 and 4, asserted in `test-controller-bindings.lua`), and the
  grip-layer test block proves the holsters' and two-hand grip's behaviour is
  unchanged. Nothing uses the wider mapping yet, so it is inert in play. This
  is the change that fixes both faults above: with the control's own mask
  blocked, `api.held` no longer contains it, so the Device sector produces an
  edge again. What remains is to have the radial issue a claim for the
  carried-items control with the `unbound` action while open, then the state
  and hub fixes below.
- (done) **Cancel rather than freeze.** `sample` returns before `Radial.step` when
  gameplay input is inactive or the option is off, leaving `{open, index}` set
  for ever. `api.destroy` has no call site, and the radial is in none of the
  cancel paths the communication wheel uses. A pick made before the escape menu,
  a downed state, a cutscene or a mission change fires on the first later frame
  where input is active and the control is not held — a wield out of nowhere,
  long after the cause. The comms gesture's rule is the one to copy:
  ineligibility cancels.
- (done) **Require a fresh press and a neutral stick.** `Radial.step` opens on the
  first held frame wherever the stick already is, and the first pick latches.
  Tap the control mid snap-turn, with the stick hard over, and a sector is
  chosen before the player has seen the radial. The comms gesture's
  rearm/idle/holding phases exist for this.
- (done) **Exclude the hub**, as every sibling on those lines does. `physical_hold`
  does not filter on the action's `hub` flag, so the radial opens in the
  Mourningstar, claims the stick (blocking turning and the third-person orbit
  pitch) and delivers a wield mask that bypasses the hub filtering `forced`
  never sees.
- (done) **Handle the two item actions being bound apart.** `physical_hold` needs one
  control to carry the whole mask, and `device` and `cycle_pocketables` are
  separately bindable. A player who splits them keeps a working carried-items
  button and gets a silently inert radial.
- (done) **Guard on the off hand's tracking**, as `darktidevr_wrist_display` does, or
  the panel sits at the last-known grip pose while its sectors still respond.

## What was sound, and worth keeping

The stick claim works and cannot leave the player unable to turn: it is
recomputed every frame, and `stick_rearm` only clears once the stick returns to
neutral, so a release on a deflected stick leaks no binding. The ordering is
right — the radial samples before `controller_bindings.sample`, and `forced` is
consumed in that same call, so it can neither double-fire nor be lost. The
sector geometry, the deadzone, the drawing coordinates and the canvas lifetime
are all correct.

## Assumption recorded

This overlaps the virtual holsters, which put the same three items on the body.
It is not redundant while body holsters are withheld from release, so the item
stays open rather than being closed as superseded.
