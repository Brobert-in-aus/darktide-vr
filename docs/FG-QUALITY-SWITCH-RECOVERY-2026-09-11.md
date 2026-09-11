# Frame-generation recovery after an in-game DLSS quality change (11 September 2026)

## Defect

With frame generation on, changing the DLSS quality in the options menu
(Quality to Performance, or back) left the mod's FG path broken for the rest
of the session: DLSS-G evaluations kept running, but stereo completion and
publication stopped, so the engine paid for FG while only native stereo was
delivered. Seen worn on 11 September (`artifacts/unattended/physical-streaming-gap-20260911/*after-quality-switch*`)
and reproduced offline the same evening.

## Offline reproduction

`artifacts/unattended/sim-dlss-quality-switch-20260911.ps1` (ignored
artifact): FG-tested baseline native `FB244186`, fixed combined viewer
`437F6D97`, simulator hub, FG on, Quality, Reflex on, 2496x2688 per eye. A
test-only Lua flag action (`darktidevr_set_dlss_quality.flag`, handled by
`presentation.update_dlss_quality_test`) applies the quality the way the
options menu does (`dlss_enabled`, `upscaling_quality`, `apply_user_settings`,
`bake_static_shadows`, `event_on_render_settings_applied`). The accepted
installation lacks modules the checkout Lua now requires, so the deployed
test file is the installed Lua plus that action only
(`artifacts/unattended/sim-dlss-quality-switch-lua/`); it is byte-restored
afterwards.

Failure signature (run `c`, `synthetic-dlss-quality-switch-c-20260911`):

```
STEREO_CONTINUOUS phase=binding_rejection captured=3 source_present=6024 present=6033 previous_present=6032 pose=17777 bound_pose=17799 bindings_match=0
STEREO_CONTINUOUS phase=paused frame=3149 reason=present_binding_or_gap
```

then no `resumed`; health froze at `complete=6296 paired=3148 published=3147`
while `evaluations` kept climbing past 19,000. Switching back to Quality did
not recover.

## Cause

A throttled capture-gate diagnostic (`phase=gate_reject`) showed every frame
after the switch rejected on the viewport check with everything else
coherent:

```
why=constants eye=0 present=6019 pose=18655 constants_valid=1 constants_present=6019 constants_pose=18655 constants_viewport=1314844562 state_viewport=2214818336
why=constants eye=1 ... constants_viewport=474417066 state_viewport=1966374655
```

Applying render settings makes the engine register new Streamline per-eye
viewport handles and re-create the depth and motion inputs at the new internal
resolution. The snapshot state and the ring kept the startup handles, so the
gate rejected every frame; the pair captured just before the switch could no
longer bind at Present, the ring paused, and nothing could resume it. A
first attempt that only cleared the observed identity (constants, tags, armed
poses) after a bounded stall changed nothing, which is how the viewport
handles were isolated; that fallback is not part of the fix.

After the handles were followed, the first capture failed terminally with
`capture_extent`: Performance re-creates depth and motion at 1248x1344 while
the ring textures stayed at the Quality extents.

## Fix (commit `158a50f` on `codex/fg-quality-switch-recovery-2026-09-11`, ported to this branch)

- **Viewport migration.** When the armed eye's constants match this present
  and pose but carry a new viewport handle, the gate adopts it for that eye,
  the ring migrates its handles (`migrate_viewports`, pausing first when tags
  on the old handles are still installed, refused while a frame is staged),
  and the retired handle's DLSS-G options slot is released so the finite
  table cannot fill with dead handles.
- **Ring reallocation.** When the tagged inputs no longer fit the ring
  textures (`accepts`), the gate pauses the ring and rebuilds its textures
  (`reallocate`) once every frame is idle: presented frames retire through
  their completion tickets, captured-but-unpresented frames through their
  capture fences, and the pause fence must have completed. Both eyes' tagged
  inputs must be from this or the previous present. Waiting longer than 240
  presents cancels the ring (`reallocation_timeout`), so the fail-closed
  behaviour is kept, only later.
- **Diagnostic.** `phase=gate_reject` lines (at most 48 per session, only
  while the ring is paused) name the identity check a paused ring waits on.
- The capture-time extent check stays as before; a stale input still fails
  the ring rather than copying into the wrong texture.

## Verification

Same wrapper with the fixed native (`sim-dlss-quality-recovery-20260911.ps1`,
30 s settle and soak, 170 s window):

| Run | Native | Quality to Performance | Performance to Quality | Published after |
| --- | --- | --- | --- | --- |
| e (`synthetic-dlss-quality-recovery-e-20260911`) | `14780B9A` (fix plus stall fallback) | paused at present 4173, migrated, reallocated 1248x1344, resumed at 4174 | paused at 5645, reallocated 1664x1792, resumed at 5646 | 2919 to 7898, one context miss per switch |
| f (`synthetic-dlss-quality-recovery-f-20260911`) | `F5799F85` (committed source, fallback removed) | paused at 4203, resumed at 4204 | paused at 5645, resumed at 5646 | 2898 to 7441, one context miss per switch |

Both switches recover within one present of the pause; `complete`, `paired`
and `published` keep rising afterwards and the final `phase=resumed` is the
last ring phase of the session. Run f's eight startup context misses came
from a concurrent build on the same machine, not the switch.

`darktidevr-continuous-recovery-tests` (WARP) now covers migration on an idle
and a paused ring, rejection of duplicate handles, reallocation only while
paused and only after the fences complete, capture after reallocation, and the
retained `capture_extent` failure for stale inputs. It passes on both
branches.

## Physical check 1 (11 September, about 19:54 to 20:00): inconclusive

`artifacts/unattended/home-fg-quality-switch-20260911/launch.ps1` installed
`F5799F85` with FG on (2112x2304 per eye, hub); the user reported that FG
appeared to break on the switch to Performance. The copied logs say:

- The mod-side recovery worked on the headset. Each of the three
  render-settings applies (Performance at present 13934, Quality at 16799, a
  third apply at 17549) went `paused` (the options menu is non-world
  presentation) or `binding_rejection`, then `viewports`,
  `viewport_migration` for both eyes, `reallocated` (1056x1152, then
  1408x1536 depth and motion), `input_extent`, `resumed`; no `phase=failed`
  in the session (`ring-phases.log`).
- Generated output had already stopped before the first switch. The DLSS-G
  completion ticket froze at ring frame 9480 (`value=12269`) and health
  `evaluations` froze at 18,840 with `foreground=0` and `focus_changes=1`,
  about 25 s before the menu pause at ring frame 10739. From then on the
  viewer received native frames only (`interval_generated_pair_fps=0`,
  native 75 to 85 FPS in Performance), which is the known unfocused
  behaviour: the game stops DLSS-G evaluation while its window is not the
  foreground window. Focus returned only in the last seconds of the session.

So the worn outcome was decided by the window losing foreground, not by the
identity or extent failure this change fixes; the fix is neither confirmed
nor disproved worn. What took foreground is not in the logs (the viewer
does no foreground operations; the launcher's focus handling runs only at
start-up).

## Physical check 2 (11 September, about 20:05 to 20:15): passed

Same wrapper, same native, game window kept foreground (`foreground=1`
across both switches, `focus_changes=0` until exit). The user reports that
frame generation kept working through the switch. Logs
(`home-fg-quality-switch-20260911/`, `attempt-1/` holds the first run):

| Switch | Ring | Viewer |
| --- | --- | --- |
| Quality to Performance, present 3931 | `paused` (options menu), migrated both eyes, `reallocated` 1056x1152, `resumed` at the same present, two single-present binding rejections while the new handles settled, then steady | generated pairs back within seconds, 100 to 114 distinct FPS |
| Performance to Quality, present 4731 | same sequence, `reallocated` 1408x1536, one binding rejection, steady | same |

Health `complete`, `paired` and `published` rise together after each switch;
context misses grew by a handful per switch, not per frame. The worn defect
the user reported this morning does not reproduce with this native.

## Observed in the same session, outside this fix

- **Remote-server mission (`mission_km_station`, dedicated mission server,
  from present 8888):** the engine registered new viewport handles again on
  the mission load; migration and resume ran, but every following present
  was a `binding_rejection` with `bindings_match=0` and matching pose, so the
  ring paused and resumed each present while health `context_misses` and
  `unmapped` climbed (42 to 315 and 57 to 340 in about 40 s) and the viewer
  delivered no generated pairs. Not analysed further here; missions have not
  been an FG test scene, and the binding check's options requirement
  (`options_present == constants_present`, `mode == 1`) is the first thing to
  inspect. Recorded on the todo.
- **No tracked hands, weapons or controller input in that mission:** the mod
  logged `DARKTIDEVR_IK presentation_blocked reason=not_first_person_body_mode
  mode=coop_complete_objective` while the viewer tracked both controllers
  throughout. This is the documented remote-mission gate
  (`darktidevr_gameplay_context.lua`: mission modes admit body, input and
  hand aim only when the local process is the server), see
  [MISSION-READINESS.md](MISSION-READINESS.md) and
  [MISSION-AUTHORITY-AUDIT.md](MISSION-AUTHORITY-AUDIT.md); not a regression.

## Limits

- The build from this branch, `BF8ED0A1...`, compiles and passes the WARP
  test but cannot be verified offline because this lineage still fails FG at
  launch in the simulator (`missing_state_api`, see the todo); the worn pass
  above is for `F5799F85` (FG-tested baseline lineage plus this fix).
- Only DLSS quality changes were exercised. Other render-settings changes
  that rebuild the eye targets (resolution scale, DLSS off and on) go
  through the same path in principle and are untested.
- The world-UI alpha route was not active in the reproduction; reallocation
  honours the allocated UI plane but was not exercised with it.
