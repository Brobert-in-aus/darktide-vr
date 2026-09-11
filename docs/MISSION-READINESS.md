# First end-to-end mission test

8 September setup update: the user explicitly requested SoloPlay preparation
now for their return from work. The [installed setup](SOLOPLAY-SETUP.md) brings
installation forward and extends stock online-style VR rules to locally owned
missions. Older installation holds below are historical; worn mission and
official-server acceptance remain open.

7 September online follow-up: [online mission requirements](ONLINE-MISSION-REQUIREMENTS.md)
now separates a potential stock-server compatibility mode from the local-server
candidate below. The stock input stream can represent aim angles; it does not
provide independent tracked hand origins or physical melee contacts.

6 September follow-up planning. No game launch or gameplay change in this update.
The user asks what is needed to try a full mission; that is a smaller milestone
than completing every mod/release feature.

## Later SoloPlay test stage

The user supplied `_downloads/SoloPlay` and requested testing it fairly late,
once VR functionality works properly in Psykhanium. Use it as the subsequent
in-mission test environment: first verify compatibility with the VR mod and its
mode/input paths, then combat, mission interactions/objectives, sustained
performance, loading and return-to-hub behavior. Do not install or launch it as
part of this documentation update. Another source copy exists under
`_downloads/deluxghost-darktide-mods/SoloPlay`; prefer the explicitly supplied copy
and inspect its version/dependencies when this task begins.

The [author's description](https://www.nexusmods.com/warhammer40kdarktide/mods/176?tab=description)
describes offline solo missions without rewards/progression. This makes it a
candidate for local mission testing; success there is not proof of online
mission-server replication/authority. Keep that later acceptance separate.

## Current candidate and remaining blocker

7 September: [the authority audit](MISSION-AUTHORITY-AUDIT.md) and shared context
policy now admit explicit mission modes only when the local process owns the
server simulation. Body/input and hand aiming use the same decision. Offline
tests pass; this is undeployed and has no mission/worn acceptance. Remote-server
missions remain excluded because local pose hooks do not supply independent
hand aim/origin to their authoritative action. SoloPlay remains the later test stage.

12 September: SoloPlay missions were confirmed worn on 11 September, and
remote (dedicated-server) missions are now admitted through the same
stock-input route by [REMOTE-MISSION-ADMISSION-2026-09-12.md](REMOTE-MISSION-ADMISSION-2026-09-12.md):
presentation and stock input by `body_mode`, hand aim by the online rules
under either established authority, local-authority overrides still local
only, a `remote_mission_input` setting to withdraw it. Offline tests and the
optional stock fixtures pass; worn acceptance on a real mission server is
the open step.

The following describes the original blocker before that candidate:

`presentation.is_first_person_body_mode` in the main stereo Lua module accepts
only `hub`, `shooting_range` and `training_grounds`. Gameplay input uses that
predicate, as do body/IK paths. `darktidevr_controller_aim.lua` accepts hand-authored
aim only in `shooting_range` or `training_grounds`. Thus accepted range behavior
does not establish mission functionality. Extend these paths deliberately;
simply deleting mode guards is not mission support.

The mission server must receive/use the intended attack direction and origin
through the game's supported prediction/authority path. Local reticle movement
and range hits are insufficient evidence. Audit existing server-reconstructed
attacks and client-owned actions before deciding whether or how additional pose
transport is needed; do not assume every action requires a new network protocol.

## Minimum before the first full attempt

1. Enable supported mission VR input, tracking, hands, turning, movement and
   hand-aim paths with correct ownership. Verify damage/impacts on the mission
   server, not merely local weapon animation or reticle placement.
2. Verify one chosen Psyker loadout: ranged fire/reload/aim, button-driven light
   and heavy melee, block/push, dodge/sprint, blitz and combat ability. Test the
   selected Psyker's quelling behavior where applicable. The user now owns ranged
   guns, equipable through Operative; inspect the actual models before selecting
   coverage. Full all-class weapon acceptance can follow the first limited test.
3. Check mission-critical interaction coverage: use/hold interactions, revive
   and rescue, pickups, carry/drop/place objectives, and mission devices or
   scanner/minigame screens where present. These are unverified checks, not all
   known broken features. A keyboard fallback may help diagnose, but cannot be
   silently treated as completed controller support.
   The [7 September source audit](MISSION-INTERACTION-AUDIT.md) identifies the
   existing stock routes and adds assignable carried-item/stim/device selection.
   These actions remain unbound by default and are not mission-accepted.
4. Check the complete lifecycle: mission selection/matchmaking, loading into
   active stereo, menus during gameplay, death/spectating if encountered,
   extraction, results and return to hub. Track crashes, frozen XR/mirror output
   and stale controller state across transitions. Existing hub/range transition
   candidates still need their live regression checks.
5. Establish usable performance over sustained combat, with readable objectives
   and HUD and no severe frame-time collapse. Start with frame generation off
   if needed; independently choose whether to retain DLSS super resolution.
   The user has not requested changing graphics settings in this planning turn.

These are prerequisites for a useful first attempt, not a promise that all
mission events can be proven before running one. Use the first complete run as
an instrumented acceptance test for the chosen character/loadout.

## Not prerequisites for that limited attempt

- Physical swing/contact melee: use the previously accepted button-driven melee
  after verifying its mission authority path. Physical damage integration remains
  unfinished and is not enabled by this plan.
- Left-handed weapon support; all-class/all-weapon coverage; final controller
  glyphs and cosmetic hint polish where essential actions are already accessible.
- Perfect frame-generation image quality: use FG off for the initial run if it
  remains problematic. Blur-first DLSS work is nevertheless active on the backlog.
- Post-release LOD policy, slight extreme-edge marker asymmetry and selective
  smoke removal, provided they do not prevent this particular test.

## Updated research/testing directions

DLSS image quality is reactivated: blur first, then duplicated/displaced elements,
which may have a separate cause. Do not treat the earlier static matched capture
as a blur or motion pass, or repeat the rejected pose hypothesis without evidence.

Performance is now an active two-part task: isolate DLSS-related frame-rate loss
and run a general performance pass. Compare SR off, SR on with FG off, and SR+FG
under controlled scene/headset/output settings; report render/input sizes and
quality so different workloads are not mistaken for overhead. Measure original
frames, generated frames and compositor delivery separately, plus CPU/GPU times
and frame-time spikes. Prior measurements (~2.06 ms Evaluate per eye) explain
much of one run's FG cost but do not establish that all overhead is unavoidable.
