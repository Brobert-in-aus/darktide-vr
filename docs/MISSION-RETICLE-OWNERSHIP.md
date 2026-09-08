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
