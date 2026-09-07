# First stock swing preview

8 September 2026: the user paused physical melee until server-side stock melee
is locked in, and requested a preview based on the tracked hand. This candidate
is local presentation only. Focused PR #11 at `8efdf66`, based on accepted
`ab9e9db`, is deployed with the melee visual correction from PR #13. Fresh range,
rigid hands and shared_ready=1068 pass with zero interval fallback/mismatches.
Preview remains opt-in; worn alignment and server damage are not accepted.

`/dtvr_melee_preview_on` enables a thin cyan path with an arrow at its end;
`/dtvr_melee_preview_off` removes it. It defaults off. The path follows the outer
tip of the stock collision box across its authored damage-window frames. It is
not a predicted hit, wall test, entire hit-volume outline or damage guarantee.
It shows the path for the aim held now. Moving aim during the real swing can
change the stock sweep reference; the guide does not promise a latched path.
The optional cached-source `test-melee-reference-stock-contract.lua` executes
the stock sweep update and confirms pre-window reference refresh, previous/current
reference sampling during damage, final-frame clamping, one exit/proc dispatch,
and suppression after abort. Its poses and spline/physics sinks are fixtures;
it does not establish network precision, authoritative damage or worn alignment.

The preview asks the stock action handler which `start_attack` is currently
valid, then follows its unambiguous light-attack chain. It uses that action's
existing sweep splines and box modifiers. It hides during any running weapon
action, menus, unavailable aim, tracking loss and missing player context.
Unsupported/conditional routes and sphere sweeps are hidden. This first version
does not preview heavies, charge transitions or later combo swings.

In stock-input proving mode, the preview uses the action's simulated first-person
position and rotation. That includes stock yaw/pitch handling and does not add
raw wrist roll which the server input path does not transmit. In the existing
local hand-aim mode, it uses the same controller rotation as the melee override
with the stock first-person origin. Neither mode moves damage origin to the
physical hand. Changing that would be a separate gameplay change.

The sampler and display never query physics, start an action, consume an input,
change a damage profile or call attack/proc routines. Authored frame samples are
copied to scalars to avoid engine temporary reuse. GUI ownership resets when the
world changes; disabling/unloading destroys it. An adapter exception disables
further work until the preview is explicitly re-enabled.

Offline checks cover route rejection, all authored fixture frames, box offsets,
separate raw versus simulated aim ownership, vector copying, invalid data,
default-off behavior, UI/tracking/player loss, world replacement and failure
latching. The display fixture does not establish actual world-GUI rendering.
It also exercises the real display's segment/arrow construction using vector
and matrix fixtures, checking lengths, orthonormal planes and backward wings.

While enabled, an observation of stock ActionSweep.start compares the selected
action name with the latest same-player/same-weapon preview up to one second
old, then consumes it. The log reports matching, age and server-process status,
explicitly damage_verified=false. UI/tracking/owner loss, world replacement and
expired predictions clear it. This does not change actions or prove damage.
The integrated branch now includes the focused candidate's display diagnostics
and unknown-hand-role rejection. The focused live deployment is unchanged.

Required worn check when the user is available: with the first melee weapon
idle, enable the guide and rotate the hand left/right and up/down. Report whether
the guide is visible in both eyes and whether the first button-triggered light
swing follows it. Check that it disappears during the attack and on opening a
menu. Test stock-input mode separately; success in local hand-aim mode does not
establish remote-server melee acceptance. Continue offline server-side audits
while this observation is unavailable.
