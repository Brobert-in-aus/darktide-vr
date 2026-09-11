# Remote-server mission admission (12 September 2026)

The user confirmed full mod functionality in a SoloPlay mission (local server
authority) on 11 September and asked for missions on a remote dedicated
server to be set up next. Until this change the gameplay-context policy
withheld body/hand presentation, controller input and hand aim in any mission
whose simulation this process did not own, which is what the worn remote
missions of 11 September showed (`DARKTIDEVR_IK presentation_blocked
reason=not_first_person_body_mode mode=coop_complete_objective`), while
stereo and frame generation worked.

## What changed

`darktidevr_gameplay_context.lua`

- `Context.authority(session)` answers `true` (this process is the server),
  `false` (a remote server is), or `nil` (missing, retiring, or a non-boolean
  answer). Only the two established answers admit anything.
- `Context.remote_mission(mode, session)`: a mission mode
  (`coop_complete_objective`, `survival`, `expedition`, `prologue`) under an
  established remote authority, and the owner's `remote_missions_allowed`
  reader returning `true` (a failing or non-boolean reader admits nothing).
- `Context.body_mode` (presentation and stock input) now admits remote
  missions. `Context.aim_mode` and `local_mission` are unchanged: the
  local-authority route stays local.

`darktidevr_online_rules.lua`

- `enabled()` admits missions under either established authority. A remote
  mission therefore uses the same stock-input route that Psykhanium's online
  rules and SoloPlay missions already use: the dominant hand's yaw/pitch/roll
  and the movement vector are written into the stock fixed-frame input cache
  that prediction, resend, replay and the server all read. No custom RPC, no
  hand-origin override, no aim-field write, no change to remote players.
  Ranges still require local authority. The admission record now names the
  authority: `DARKTIDEVR_ONLINE_RULES range=<mode> enabled=true
  authority=local|remote origins=stock damage=stock`.

Main module and settings

- New mod setting `remote_mission_input` (default on, applied per query):
  "VR input and hands in online missions". Off restores the previous
  view-only behaviour in remote missions without a relaunch.

Nothing else moved. Because `is_controller_aim_mode` is false whenever the
online rules are enabled, every local-authority override (weapon pose
proxies, staff/throw convergence, button-melee reference proxies, left-hand
block proxies, local aim-field writes, body-follow root translation) stays
off in remote missions exactly as it does in SoloPlay missions. The two
hard range-only paths, the test-only `fire_once` action and the first-person
weapon-hand grip override, remain range-only; missions present hands and
weapons through the body IK path, which is what the user accepted in
SoloPlay.

## What a remote mission gets

| Feature | Route |
| --- | --- |
| Stereo, HUD, frame generation | unchanged (client presentation) |
| Body, hands, weapon presentation | body IK path, admitted by `body_mode` |
| Buttons, movement, dodge, sprint, interact, slots, wheel, push-to-talk | stock input injection, admitted by `body_mode` |
| Hand-aimed firing, throws, button melee | stock input columns authored by the online rules; the server keeps its own firing origin, actions and damage |
| Reticle, projectile visuals, melee preview, gun-hand alignment, roomscale render offset | presentation only, from the simulated first-person component (`simulation_aim_active`) |
| Spectator stick input, downed states | stock, admitted by `body_mode` |

Not provided, by design: independent tracked weapon origins, two
authoritative hand poses, always-active physical melee. See
[ONLINE-MISSION-REQUIREMENTS.md](ONLINE-MISSION-REQUIREMENTS.md) for the
capability boundary.

## Offline verification

- `gameplay_context` (CTest): remote admission for the four mission modes
  under an established client session, rejection under missing, retiring and
  non-boolean sessions, the settings reader withdrawing admission, and the
  local-authority predicates unchanged.
- `online_rules` (CTest): missions author under local and remote authority
  with the authority recorded; unestablished sessions leave stock columns;
  ranges still require local authority; latch and diagnostics unchanged.
- Optional stock-source fixtures against `_downloads/Darktide-Source-Code`:
  `test-online-input-stock-contract.lua` with the adapter (fixed-frame aim
  and action agreement, resend, duplicates, ring wrap, gaps) and
  `test-online-rules-stock-contract.lua` in range and mission modes (stock
  first-person pose keeps the body origin and recoil, walking keeps direction
  and the backward penalty, the orientation selector retains forced views,
  and the smart-targeting, flamer, placement and pocketable sections). Both
  fixtures had rotted since the adapter began deriving yaw, pitch and roll
  from the forward and up vectors; their engine-rotation stubs now supply
  those axes and the flattened right/up the stock smart targeting uses.
- The full offline CTest suite (`ctest --test-dir build/windows-vs2022 -C
  Release`) passes, 234 of 234, with every target built. Two unrelated test
  regressions were fixed on the way (`visual_settings` stub, launcher
  cleanup continuation under strict mode).

## Deployment

Deployed at about 10:20 on 12 September by the ordinary sync, transaction
`artifacts/deployment-backups/deployment-830a70dd1ee24082b2ae33ed40b44621`:
native `5B7D5B9B...` unchanged from the 11 September bundle, main Lua
`4F273B2D...`, `darktidevr_gameplay_context.lua` `CF1ABFA6...`,
`darktidevr_online_rules.lua` `C6B32F0D...`. Rollback with
`tools/stereo/restore-darktide-vr-deployment.ps1 -Manifest artifacts/deployment-backups/deployment-830a70dd1ee24082b2ae33ed40b44621/manifest.json`,
or turn the `remote_mission_input` setting off for view-only remote missions
without touching files.

## Limits

- No offline stand-in for a dedicated server exists here; the SoloPlay
  mission remains the local control. Real-network latency, correction
  convergence, other players' husks and official-server acceptance are only
  observable worn.
- Traversal follows the sent aim (ledge discovery uses the dominant hand's
  direction), the known online-rules limitation.
- Nothing here changes what the server validates; damage, spread, recoil and
  weapon statistics stay stock.

## Worn check: passed (12 September, 22:54 to 22:59)

`home-remote-mission-20260912/`: a dedicated mission server
(`host_type(mission_server)`, `mission_fm_resurgence`,
`coop_complete_objective`). The user reports that hands and controls worked
in the mission. Logs: `DARKTIDEVR_ONLINE_RULES range=coop_complete_objective
enabled=true authority=remote origins=stock damage=stock`, then
`input_frame=31244 aim=dominant_hand movement=stock_packed
replay=stock_history challenge=2 resistance=2`; 166 gameplay deliveries
(fire, release, sprint, wield, and others), 5 melee wrist-roll records, 0
`presentation_blocked`, 0 `input_fallback`; the ring paused and resumed
around the mission load and again on the return to the hub, no failures,
FG published in the mission (5048 pairs by the end). The exit code 1 during
the hub reload is the user's force-quit key (Super+F4), not a crash; no
crash record exists.
Rubber-banding was not reported. Per-action-family coverage (throws,
interactions, downing, rescue, spectating, extraction) and the
traversal-aim policy remain the later checks in
[MISSION-READINESS.md](MISSION-READINESS.md).

### Procedure

`artifacts/unattended/home-remote-mission-20260912/launch.ps1` runs the
normal session and, after exit, keeps the console lines that decide the
result next to the script: `DARKTIDEVR_ONLINE_RULES ... authority=remote`
and `input_frame=` (hand aim authored on the server route),
`DARKTIDEVR_INPUT gameplay_delivery` (buttons delivered), no
`DARKTIDEVR_IK presentation_blocked` for the mission, plus the ring phases and
health log. Check in the mission: hands and weapon visible and following the
controllers, movement and turning, firing where the dominant hand points,
reload/dodge/sprint/interact, a throw, button melee, and that the view stays
with the headset while the gun points elsewhere. Stop on any correction
fighting (rubber-banding) and note where it happened.
