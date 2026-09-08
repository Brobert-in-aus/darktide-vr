# SoloPlay mission test setup

8 September: the user requested preparation now for their return from work.
This supersedes the earlier hold on installing SoloPlay until all Psykhanium
acceptance is complete. Mission gameplay and official-server acceptance remain
separate checks.

The explicitly supplied `_downloads/SoloPlay` reports version 2.6.2. It is
installed unchanged after the VR mod in `mod_load_order.txt`; its `.mod` entry
requires DMF, already installed. No other dependency is declared there.
The existing native capture, bootstrap, shaders and accepted weapon alignment
remain installed. Only the VR gameplay-context and online-rules modules change.

Locally owned supported missions now always use the same stock input-cache aim,
movement packing, simulation origins and action/sweep/damage rules as the
Psykhanium online-rules mode. Disabling that range-only option does not allow
local hand-origin combat overrides in a mission. Rules relatch on session or
mode change. Remote authority and unknown modes remain excluded. This prepares
local mission tests; it does not enable or validate official matchmaking.

The saved Normal preset selects `cm_raid`, no circumstance or optional side
mission, and the default mission giver. Difficulty index 1 is the supplied stock
table's Uprising entry (challenge 2, resistance 2), chosen as an initial gameplay
check and editable in the SoloPlay screen. Friendly-fire override and optional
mission briefing are off; the mod's normal random side-mission seed remains on.
SoloPlay's local hosting and built-in workarounds remain; this is not an exact
dedicated-server simulation and it awards no progression or rewards.

Open the mod options with F4, select Solo Play, then Open; alternatively enter
`/solo` in chat. The Normal tab holds the prepared mission. Review difficulty
and select Play when ready. Physical melee remains paused; use stock button
melee. The optional first-swing preview is available through
`/dtvr_melee_preview_on` and defaults off.

Validation: gameplay-context and online-rules fixtures pass (2/2); eight related
aim, reticle, tag and melee fixtures pass. The optional stock source contract
passes firing, movement, sweeps, targeting, block, interaction and traversal
checks with its documented engine substitutes. Integrated VR Lua compiles all
50 chunks; installed focused VR compiles 46, and all 22 supplied SoloPlay Lua
and `.mod` chunks compile with the pinned LuaJIT gate.

Ready preflight passes. Installation and settings have verified transactional
backups recorded in `artifacts/unattended/soloplay-install-receipt-20260908.json`.
The previous game session closed cleanly before settings were written.
Fresh startup verification passes: SoloPlay hooks load without a mod error;
Psykhanium entry passes at 03:14:23 UTC and online rules report enabled with
stock origins/damage. The viewer exceeds 1,022 shared-ready frames at about
54 original plus 54 generated pairs/s with zero interval fallback, reuse or
pair-pose mismatch. This is startup evidence, not mission acceptance.
No mission launch, mission damage, objective completion, worn comfort or
official-server acceptance is claimed.

Integrated checkpoint `9b7736a`, PR #43; focused accepted-preview counterpart
`0ff82f7`, PR #44. The focused source compiles 45 chunks; the installed unused
gun-alignment module accounts for its extra chunk. Native DLL hashes still
match the accepted preview deployment. Initial session was PID 144416, launcher
7180. After passive billboard diagnostics, the restored current session is
PID 1976, launcher 15586, started at 13:44:30 Brisbane:
`artifacts/unattended/soloplay-post-readback-session-20260908.log`. Fresh
Psykhanium entry, online-rule initialization and stereo pass again.

Current session after a timing-only viewer update: Darktide PID 120404, launcher
72645, started 14:48:16 Brisbane. Log:
`artifacts/unattended/soloplay-frame-stage-session-20260908.log`. Psykhanium
passes at 04:49:34 UTC; stock rules, rigid hands and fresh stereo pass. Native,
bootstrap, Lua, SoloPlay settings and shaders remain unchanged. The viewer adds
stage-duration reporting to investigate a sustained idle slowdown; it does not
change frame selection or combat. See [viewer timing](XR-FRAME-STAGE-TIMING.md).

## Current live comparison, 16:00 Brisbane

The earlier timing-only session reproduced the sustained runtime submission
decline and was saved before closing. SoloPlay settings and game files remain
unchanged in game PID 84828, started 15:58:54. A focused
[precise-wait viewer trial](XR-PRECISE-PAIR-WAIT.md) now runs with fresh range,
stock-rules and rigid-hand initialization and nonzero shared stereo. Its fresh
delivery is about 54 original + 54 generated pairs/s; sustained and worn checks
remain pending. No solo mission was launched. Launcher session 94365 has the
usual approximately 23:58 Brisbane deadline unless the user stops development
earlier. Use the linked trial document for the exact backup and recovery root.
