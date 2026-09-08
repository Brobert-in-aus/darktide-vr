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
Fresh startup verification is in progress. No mission launch, mission damage,
objective completion, worn comfort or official-server acceptance is claimed.
