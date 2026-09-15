# Animation-driven presentation audit (16 September 2026)

Todo item: nothing presentation-side driven by 1p or 3p locomotion or
animation, except what the server drives. Static audit of the branch at
`51ce584`; line numbers refer to that revision.

## Strafe wobble: diagnosis

- The body anchor (`body_camera_anchor`, `darktidevr.lua:4921-4984`) is
  `first_person_component.position` (fixed-step) plus a model-eye offset
  captured once in the `active_base_rotation` frame. After capture it does
  not turn with the body. The post-update writer
  (`refresh_body_anchor_from_avatar`, `:5082-5089`) and the camera writer
  (`:5226-5233`) agree within a frame: no fixed step runs between them.
- The mismatch was the tracked eye. It is stored at the camera update
  (`:5246`), after the locomotion post-update has placed the displays
  (`:11707-11745`), so `eye_pose` returned last frame's eye there. On frames
  where a fixed step moved the player, that eye lagged a step of travel
  behind this frame's anchor; while strafing the lag is sideways to the view,
  so the forearm miniatures (billboarded to the eye) flicked between two
  yaws. The ammo counter's away-from-eye offset and the gun sight zeroing
  weight read the same stale eye.
- Fix (16 September): the eye is stored relative to the anchor the camera
  wrote and read back from the current anchor (`store_tracked_eye`,
  `eye_pose`; test `tracked_eye_anchor`). Input-time readers see the anchor
  the eye was stored with and are unchanged. Worn check: checklist
  2026-09-16 item 2.

## Inventory (drawn, not server-driven)

| # | Read | Feeds | Status |
|---|---|---|---|
| A-C | stale `eye_pose` in post-update | forearm miniature yaw, ammo counter offset, sight zeroing weight | fixed with the eye anchor |
| D | anchor not refreshed on some post-update paths (stock melee animation, keyboard and mouse, IK disabled, errors: `:10354-10370`) | displays and gun placement use last frame's anchor there | fixed: the stock melee animation and keyboard-and-mouse branch refreshes it (16 September) |
| E | `BodyProxy.align_gun_hand` (`darktidevr_body_proxy.lua:718-731`): glove = attach pose x animated hand-in-attach offset | gun-hand glove, `hand_pose` | open: capture the offset once per weapon, or place from the controller wrist |
| F | `visible_grip_target` (`darktidevr.lua:8571-8584`) built on E | ammo counter melee branch, body mirror | open: use `weapon_grip_target` |
| G | `follow_gameplay_hands` (`darktidevr_body_proxy.lua:772-810`): animated 1p wrists for stock melee animation and keyboard and mouse hands | both gloves during melee swings; keyboard and mouse hands | needs a user decision: melee with controller hands, or keep the animation |
| H | `copy_gameplay_fingers` (`darktidevr_body_proxy.lua:245-272`) | finger curl only | later: fixed per-item grip poses |
| I | `sync_equipment_hand_to_proxy` (`darktidevr.lua:9267-9313`) | held item placement, via E in body-drawn-hand mode | clean once E is fixed |
| J | holsters `body_frame` (`darktidevr_holsters.lua:283-311`): built at input time, drawn in post-update; yaw from the first-person unit rotation when `body_visual_yaw` is nil (includes stock recoil offsets) | body holster zones, models, counts (withheld) | open: rebuild at draw time, yaw from the tracked eye, before body holsters return |
| K | one-time capture of the model-eye offset from animated eye bones and 3p root yaw (`darktidevr.lua:4839-4843`, `:4887-4901`, `:4960-4974`) | camera and every controller target (constant offset) | open: breed constants or capture only when root yaw matches scene yaw |
| L | `body_visual_yaw` seeded from 3p root yaw (`:9691`) | full-body spine and shoulders, two-hand stock | full-body flag only; seed from `body_head_yaw` |
| M | virtual stock `frame.body_position = Unit.world_position(unit, 1)` (`darktidevr_two_hand_support.lua:503`) | virtual stock anchor | only with a finite `body_visual_yaw`; use the anchor position |
| N | `observe_authored` reads the 1p rig's left hand in the attach node | support grip socket (averaged, frozen) | acceptable; shipped or stored grips only |
| O | `gun_sights.measure` (1p muzzle and camera) | sight-line calibration (relative, frozen) | acceptable |
| P | body mirror and overlay copy every animated joint | full-body copy | dev flag only; replaced by the full-body IK design |
| Q | scanner hologram re-placed from the held item | hologram | fine after E; the flamer stream keeps gameplay aim |
| R | `author_weapon_pose` (`:10750-10874`) | 1p weapon | dev flag only |
| S | 3p aim constraint from the smoothed root (`:11605-11623`) | hidden 3p head and torso | not drawn |

Excluded as server-driven or diagnostic: teammate `j_head`
(`darktidevr_teammate_status.lua:92`), projectiles, log-only reads,
`attachment_scan`, `pose_trace`. `sight_ads` and `holsters.sample` run at input
time with last frame's anchor and eye, consistently.

## Order

1. Eye from the current anchor (done, 16 September).
2. Refresh the anchor on the stock melee and keyboard-and-mouse path (D; done, 16 September).
3. Holster frame at draw time, yaw from the tracked eye (J), before body
   holsters return.
4. Gun-hand glove without the animated offset (E), then `visible_grip_target`
   users to `weapon_grip_target` (F).
5. User decision on melee and keyboard-and-mouse animated hands (G), then
   fingers (H).
6. Model-eye capture from constants (K), then the full-body-only items (L, M).
