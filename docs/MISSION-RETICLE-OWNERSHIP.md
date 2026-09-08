# Solo mission crosshair ownership

8 September worn report: the user entered SoloPlay and saw no crosshair, then
closed the game and requested a fix/relaunch with melee preview enabled.

The installed targeting hook used `_is_local_unit` to decide who could publish
or clear the single shared VR reticle. Stock `player_character_unit_template.lua`
sets that flag from `not player.remote`; locally simulated bots therefore pass
the same gate. In online-rules mode the reticle pose helper correctly rejects a
bot as the human aim owner, but the caller then clears the shared reticle. Bot
updates following the human update can erase the crosshair for that frame.

The hook now requires both the existing local-simulation flag and identity with
`Managers.player:local_player(1).player_unit`. Other characters still execute
their stock targeting function with unchanged arguments/return value; they
cannot overwrite the human reticle or its convergence/tag cache. The current
owner can still clear unavailable aim. No damage, raycast or firing policy changes.

`test-reticle-owner.lua` executes the production hook with two local bots and a
remote player updating after the human. It covers both aim modes, owner
replacement and missing current-owner pose. The old implementation fails the
bot-after-human assertion; the corrected implementation passes. Six related
reticle, gameplay-context, rules and preview checks also pass (7/7, 0.12 s).
Old-code failure evidence is
`artifacts/unattended/mission-reticle-negative-20260908.log`.

The relaunch also includes the previously prepared F6/menu preview toggle. An
explicit startup request file, `darktidevr_melee_preview.flag`, enables the guide
only when its content is `enabled`. The launcher/operator owns this file and
must remove or restore it after initialization; the normal absent-file default
remains off. The startup reader is bounded and fails closed, with fixture checks
for valid/invalid content, close, default-off and requested startup. This is a
local visual guide, not physical melee or a damage guarantee.

Deployment and fresh mission verification follow default Ready. The first
preflight attempt found zero authorized ADB devices; no deployment or launch
was attempted on that failed readiness result. The user was asked to reconnect
the Quest while focused deployment preparation continues. Live/worn acceptance
must be recorded separately from the offline regression results.

The first preview-enabled relaunch crashed in Network.peer_id during startup:
local_player(1) was queried before the connection existed, and this engine assert
cannot be caught by Lua pcall. The display now checks presentation readiness
first and uses stock local_player_safe(1). The startup fixture covers loading,
an uninitialized connection, and subsequent successful drawing without a latched
failure. Seven related CTests pass (0.08 s); focused source compiles all 45 chunks.

Retry checkpoint: startup correction is committed as main 75cb39f and focused
9b53acf, pushed to PR59/60. Default Ready retried after the crash: the first
runtime creation timed out; the second created VDXR but returned
XR_ERROR_FORM_FACTOR_UNAVAILABLE / hmd-unavailable. USB remains authorized and
Quest awake. The corrected preview file has not yet been deployed; the prior
four-file deployment and explicit enabled startup flag remain installed. No
runtime restart or game launch was attempted on these failed readiness results.
The user has been asked to resume Virtual Desktop streaming. Receipts:
mission-preview-retry-ready-20260908.json and
mission-preview-retry2-ready-20260908.json under artifacts/unattended.

Live retry succeeded after the user resumed Virtual Desktop: default Ready
mission-preview-retry3-ready-20260908.json has readiness_verified=true. The
single corrected preview file was deployed transactionally; installed Lua gate
passed 46 chunks. Launcher mission-reticle-preview-retry-session-20260908.log
reached Psykhanium at 07:32:05 UTC. Fresh console 07.30.32 records preview=on,
rigid_hands=ready and native ready counters; harness shared_ready exceeded 1100.
No preview_error was observed. The startup flag transaction was restored after
initialization, leaving the current preview enabled and future launches default
off. F6 remains the direct toggle. Heartbeat remains paused and proximity override
disabled as requested. Worn mission crosshair and guide visibility remain pending.

Known live warning: DMF rejects the delayed hook_safe ActionSweep.start observer
because the same mod already has a regular start hook. The existing hook stays
active; the rejected observer only logs predicted-versus-started action matching,
not preview drawing. Combine that logging with the existing hook in a subsequent
patch and validate without interrupting this user test session.

8 September evening worn acceptance: the user confirms the mission crosshair
works. The melee guide draws but accumulates blue geometry across frames.
Before edits, the newest three Quest recordings (17:36:02, 17:41:41, 17:53:16)
were copied to artifacts/quest-recordings/2026-09-08-evening and all SHA256 hashes
matched the originals. The files remain on the headset.

The guide created a retained world GUI while appending fresh rect_3d primitives
every update. It now creates an immediate world GUI, matching the existing HUD
panel approach, so the engine retires those rectangles each frame. A 120-frame
moving-pose fixture rejects stale geometry and checks hidden frames and reuse of
one GUI. The old source fails; the correction passes. Related CTests: 3/3 in
0.06 s; focused Lua source gate: 45 chunks. Live visual acceptance is pending.
