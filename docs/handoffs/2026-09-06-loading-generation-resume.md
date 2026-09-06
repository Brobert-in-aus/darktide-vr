# VR remains cached after hub-to-Psykhanium loading

The user reports loading completes on the desktop while VR returns to the last
pre-loading frame. The game and harness remain alive. This run includes the HUD
material cleanup candidate; fresh HUD initialization in the new level reports
23 fixed elements transferred with zero failures. No recurrence of the previous
material-destruction script error was found in this transition.

Harness evidence: shared readiness continues advancing, `fresh=1 pose_synced=1`
but `settled=0`. Committed, rendered and resume generations all remain 103. The
compositor deliberately consumes those incoming pairs while presenting its
cached pair, because it has not received a newer restored-gameplay generation.
This is not a missing render or eye-copy stall.

Lua logged the initial hub owner commit at generation 103 and a later modal
suspension, but no new owner commit or modal restore after the loading screen.
On a new orientation owner, the old code cleared suspension and committed only
if presentation was already mode 1. A new level's owner can appear in loading
mode 2, permanently missing that one-shot commit. Subsequent fresh pairs retain
the old generation and cannot satisfy the unchanged compositor resume gate.

The candidate keeps a pending generation on owner change and non-world
presentation. It commits only in mode 1 after restoring the authoritative
orientation. A failed native commit remains pending for retry. It does not
loosen pose matching or accept stale menu-camera frames on a timeout.

Validation: `gameplay_heading`, `lua_source_compile` (31 chunks), `hud_panel`
and `presentation_policy` pass. The heading test checks orientation is authored
before every commit, owner creation during loading, same-owner loading,
single commit on return, and native failure/retry. No native source changed.

Next live check: manually enter the Psykhanium from the hub, verify a new
`DARKTIDEVR_AIM gameplay_generation` commit after loading, matching rendered
generation, advancing fresh-pair presentation and user-confirmed moving VR.
Automatic Psykhanium entry stays disabled. The NGX observer is still disabled
for this transition validation; its next-launch candidate remains separate.
