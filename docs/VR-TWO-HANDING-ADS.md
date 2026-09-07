# Two-handed guns, virtual stock and ADS

Status: researched design/backlog, 7 September 2026. Not implemented or deployed.
The current held-gun aim correction remains the prerequisite worn check.

## Requested interaction

Move the left hand to the gun's support grip and press grip to two-hand it.
That contextual press overrides the currently bound grip action. A press outside
the grip region retains its binding. Use logical support/dominant roles internally
so future handedness does not require duplicating this behavior.

Claim the whole press/hold/release gesture before normal action dispatch. Do not
start grabbing merely by moving a previously held grip into range. Release,
weapon switch, menus, death or tracking loss must end ownership cleanly and
require neutral input before restoring the displaced action. A held button must
never suddenly trigger its old action when the hand leaves the grip region.

## Research and proposed implementation

VR Expansion Plugin treats a secondary grip as a modifier on an existing primary
grip and calculates the secondary socket relative to the held object. That is
a useful reference for preserving the gun's main grip while the support hand
steers it. [Author documentation](https://vreue4.com/basic-gripping#secondary-grip-types).

Its gun implementation derives a stock anchor from an offset and headset yaw,
uses proximity to blend stock influence, clears mounting when the secondary
grip ends, and resets a smoothing filter on engagement. These are reference
mechanisms, not Darktide integration code.
[Author source](https://github.com/mordentral/VRExpansionPlugin/blob/Master/VRExpansionPlugin/Source/VRExpansionPlugin/Private/GripScripts/GS_GunTools.cpp).

Our proposed solver and acceptance work:

- Author or resolve support sockets per weapon; use a small acquisition volume
  and a larger release tolerance. Begin with the owned lasgun. Pistols need a
  support-hand cup near the dominant grip; stocks and foregrips are not universal.
- Keep the main grip position as the primary constraint. Derive orientation from
  the main/support grip line with the authored gun basis, retaining sensible
  wrist roll. Blend acquisition/release to avoid a barrel jump. Handle coincident
  hands and extreme angles explicitly; never scale the gun to controller distance.
- Add an optional adjustable shoulder anchor and stock-length contact test.
  Blend toward shoulder-supported aiming only near the shoulder. Use a stable
  body-heading estimate, avoiding an immediate gun swivel when the user turns
  their head independently. Headset yaw alone cannot measure torso yaw.
- Offer stock strength/offset and modest time-based smoothing; reset on recenter
  or tracking discontinuity. Keep high/low aiming, hip fire and eye alignment
  usable. Do not rigidly lock the weapon to the face or delay fast deliberate aim.
- Feed the same resolved gun basis to visual weapon, simulation aim and reticle.
  Preserve stock recoil/spread once. Keep the main hand seated; a constrained
  support-hand visual may differ slightly from raw tracking at the socket.
- Test grip-action suppression, release without an accidental old action,
  weapon/context changes, tracking loss, recenter, close hands, head-only turns,
  high/low aim, one/two-hand transitions, and worn sights/reticle/impact agreement.

All solver details above are a proposed adaptation and require worn tuning.

## ADS coupling

The user's suggested first candidate is: two-hand hold requests the weapon's
normal ADS/braced input; release requests its ordinary exit. Physical sight
alignment remains something the user performs with the held weapon. A later
option can require shouldering/sight proximity if users want supported hip fire.

The inspected local `lasgun_p3_m2.lua` has `action_zoom` (`kind = "aim"`),
`action_unzoom`, and `action_shoot_zoomed`. Its `alternate_fire_settings` select
different recoil/spread/sway templates and a movement-speed modifier curve.
Therefore ordinary ADS input is a plausible route to the intended movement and
accuracy tradeoff. Exact recoil/spread differences must be checked per weapon;
two hands by themselves must not be claimed to grant a universal bonus.

Audit input arbitration with an already held aim binding, interruptions, and
weapon-specific secondary modes (ADS, bracing, charging, special attacks).
Do not map staff grip to a charged cast indiscriminately. Preserve normal action
gates, stamina/ammo/timing and server-authoritative combat rules. Suppress flat
camera zoom/repositioning in VR through presentation handling, while retaining
gameplay ADS state; scopes need their own readable stereo treatment.

True firing origins remain the stock body/face-based origins. Two-handed aiming
and cosmetic muzzle effects do not enable gun-only blind fire around cover.
