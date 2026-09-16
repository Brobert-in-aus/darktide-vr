# Handedness: what still assumes a right-dominant player (16 September 2026)

The mod fixes the weapon hand at the right:

```lua
-- Foundation only: keep the accepted right-dominant presentation until weapon
-- attachments/effects and input rearming support a complete handedness option.
presentation.weapon_hand_roles = mod:io_dofile(
    "darktidevr/scripts/mods/darktidevr/darktidevr_weapon_hand_roles").new("right")
```

The user asked on 16 September that new work be written against roles rather
than sides, "since we're designing for the eventual handedness toggle". This
is the inventory that toggle needs: every place in the mod's Lua that names a
physical side, classified by whether it may stay.

The role API is `presentation.weapon_hand_roles.physical(role)` for `dominant`,
`support`, `left` and `right`, with `presentation.weapon_grip_target(role)` and
`presentation.controller_aim.target(role)` on top.

## The shape of the answer

- **Most side names are correct as they are** (about 61 groups across 33
  files): native input channels and their bits, anatomical joint names, loops
  over both controllers, stereo eyes and viewports, and the role dispatchers
  that resolve a role and *then* pick a channel. That last pattern is the
  intended one and is already used widely.
- **About 23 lines in 10 files mean a role and say a side.** These would be
  wrong for a left-dominant player and are straightforward to change today.
- **About 40 lines in 6 files are genuinely blocked**, and they all trace back
  to two facts about the shipped content, not to the mod's design.

## What blocks the toggle

Every blocked item comes from one of two places:

1. **`j_rightweaponattach` is the only populated weapon attach node** in the
   first-person rig. The gun's pose, the muzzle, the sight line and the
   attachment audits are all expressed in that node's frame
   (`darktidevr.lua:10770`, `:10932`, `darktidevr_gun_aim.lua:87`,
   `darktidevr_two_hand_support.lua:294`).
2. **The stock animation's support hand is the left one**, and every shipped
   and saved two-hand grip was measured for it
   (`darktidevr_two_hand_support.lua:237-259`). Flipping the role would
   invalidate the saved `vr_two_hand_grips_v1` calibration.

Handedness is already partly plumbed against both:
`darktidevr_body_proxy.lua:767` converts a hand rotation from the rig's right
hand to a left destination, and `darktidevr_gun_aim.lua:70` gates the
left-dominant path on that conversion existing. So the work is not to invent a
mechanism but to carry it through the authored-grip and attachment layers, and
to decide what happens to saved right-handed grips.

## Should be a role (changeable today)

### The off-hand locomotion reference (the largest cluster, and the only one a player can see)

`darktidevr.lua:11317-11382` and `darktidevr_data.lua:19-20`: the
"movement reference" option stores the literal value `left_hand`, and the code
behind it reads `left_aim_usable`, `left_controller_aim_target` and
`left_hand_movement_rotation`. It means "the off hand".

Recommended: keep the stored value `left_hand` so saved settings survive,
relabel the option to name the off hand, and move the reads onto
`physical("support")` as part of the toggle. Changing the stored value needs a
migration and buys nothing.

### The rest

| File | Line | What |
| --- | ---: | --- |
| `darktidevr.lua` | 5836, 11586 | `right_aim_usable` gating the primary fire action and the aim audit: it means the weapon hand's aim is live |
| `darktidevr.lua` | 6080 | `controller_aim_target()` in the keyboard-and-mouse roll input, meaning the dominant ray |
| `darktidevr_weapon_inspect.lua` | 134 | haptic pulse hardcoded to `"right"` (fixed 16 September, the same day it was written) |
| `darktidevr_attachment_scan.lua` | 307 | drift diagnostic reads `controller_grip_target()` where line 398 in the same file already uses `weapon_grip_target("dominant")` |
| `darktidevr_holsters.lua` | 443 | debug trace emits for the right hand only; the interesting hand is a role |

Plus seven raw right-dominant *fallbacks* that only fire if
`weapon_hand_roles` is missing (`darktidevr_controller_aim.lua:178`,
`darktidevr_melee_live_probe.lua:117,136`,
`darktidevr_melee_preview_display.lua:57`, `darktidevr_online_rules.lua:194`,
`darktidevr_haptics.lua:421`, `darktidevr_body_proxy.lua:756`). They duplicate
the role table rather than fail loudly. Worth folding into one helper so there
is a single answer to "which side is dominant when we cannot tell".

## Suggested order, when the toggle is taken on

1. One helper for the dominant/support fallback, replacing the seven copies.
2. The straightforward role swaps in the table above.
3. The locomotion reference cluster: relabel, keep the stored value, move the
   reads to roles.
4. The authored grip: decide whether a left-dominant player re-measures grips
   or whether the saved right-handed ones are mirrored, and say so in the
   option's text.
5. The weapon attach node: mirror the pose into a virtual left attach frame
   built from `j_rightweaponattach`, as the body proxy already does for hand
   rotations.
6. Only then the option itself, defaulting to right.

## Method

Read-only sweep of `mods/darktidevr/scripts/mods/darktidevr/*.lua` on
16 September, at `cb2902a`. About 1,900 lines mention "left" or "right"; some
350 of those are not hand sides at all (basis vectors such as
`Quaternion.right`, UI box geometry, alignment strings, stereo eye naming,
prose) and are excluded.
