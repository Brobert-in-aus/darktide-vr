# Release checklist: 0.3.0-alpha.1 (drafted 19 September 2026)

The next release is **0.3.0-alpha.1**, not 0.4.0. The tags so far are
`v0.1.0-alpha.1`, `v0.1.0-alpha.2`, `v0.1.0-alpha.3` and `v0.2.0-alpha.1`
(15 September, on `d6d0e90`): a minor bump opens each alpha cycle and the
suffix counts its re-releases. The branch name `codex/alpha-4-2026-09-14`
counts alphas overall, not versions. `CHANGELOG.md` already carries an
"Unreleased" section headed "Since 0.2.0-alpha.1", so 0.3.0-alpha.1 is what
that section becomes. 351 commits sit between the last tag and `ec73ee6`.

Items are numbered as headings because the reader's viewer renumbers lists.
Each item says what decides it. Nothing below is done yet unless it says so.

**Progress (19 September, 17:55).** Item 1 decided by the user: "whatever
we've got to after today's testing is what the full body should be"; the
option now runs the stock-legs overlay (`Mirror.OPTION_MODE`). Item 3
reported: "all pass except the flamer skull, which isn't grabbed in the
right place and isn't fixed to the hand, it rotates weirdly", plus the
cone attack's direction against its preview; both changed in `ec73ee6`'s
successor, awaiting the worn clearance. The user's order: once the grab
and the cone aim are cleared, items 4 to 8 proceed; item 9 waits.

### 1. Decide what "Full body (experimental)" ships as

The option today runs the overlay with the procedural gait; the dev flag
`darktidevr_body_mirror.flag=overlayanimated` runs the same overlay with the
stock model's legs (the animation copied onto the copy's leg joints) and the
torso rest from the model's normal pose. The user called the stock legs
"working" and the gait "really bad" at 14:44. Decision: make the option map
to the stock-legs mode (`Mirror.requested_mode` and `MODES`), or ship the
gait and keep the flag. Whichever, the flag must not be needed for the
shipped behaviour. This is the one design decision on the list; the rest
is mechanics.

### 2. Reset the install's flags to the shipping set and run a clean worn pass

The install has these set now, from the day's work:
`body_mirror=overlayanimated`, `body_trace=enabled`,
`full_body_experimental=enabled`, `controller_aim_test=enabled`,
`gameplay_input_test=enabled`, `reticle_in_eyes=enabled`, `xr_log=enabled`,
`crosshair_scale=70`. The package carries none of them (only the two
play-configuration flags under `bin`), so a release-candidate worn pass has
to run with them deleted, the options set from the mod menu, and the
Psykhanium and a mission both visited. `Assert-NoStaleFlags` in the readiness
gate reads the deployment manifest for what belongs; run the sync script
(`tools\stereo\sync-darktide-vr-dev.ps1`), not hand copies, for this pass,
so the native DLL in the install is the one the package will carry.

### 3. Worn verification of what changed today, on the candidate build

Each of these is a worn report against a log line, per the 19 September
checklist:

- The body does not flicker while moving (`render_eye_lag` near zero,
  `d_unit_rel_eye_m` under 2 mm on moving frames). Confirmed at 14:44 and
  after; confirm on the candidate.
- The camera stands at the calibrated eye height on load and after a
  recenter (`eye_stack`: tracked eye minus avatar root equals
  `calibrated_eye_height_m`). Confirmed at 17:40; confirm on the candidate.
- The stock legs stand on the floor (`stock_legs toe_above_floor_m` near
  zero) with the torso at the model's height (`torso` line: copy hips to
  eyes equals avatar hips to eyes). Unconfirmed since the camera fix.
- The mirror: fixed in the world at spawn, true mirror, head at eye level
  and following the headset, fingers matching, the wielded weapon in the
  reflected hand and pointing where yours points. Head and weapon are
  unconfirmed since the camera fix; the rest was confirmed at 17:40.
- The servo skulls do not flicker (`d_skull_rel_eye_m` near zero).
  Confirmed at 15:50.
- The flamer skull grab: locked to the palm where grabbed, turning with the
  hand, throw still works (`DARKTIDEVR_SKULL_GRAB_DRAWN ... in_hand=` holds
  three constant numbers while held). Worn at 19:40: "grab is locked,
  throwing towards works" (the grab is CLEARED: in_hand did not move a
  millimetre, the bob was node 10 and is frozen). Open: a throw AWAY from
  the aim point. Worn at 20:00 on the accelerating blend: "it absolutely
  teleports at the end of the ballistic arc" (max_step 0.45 to 0.70 m in a
  frame). Test-checklist 1aj and 1ak: the blend is replaced by a chase
  with the acceleration capped, the speed and the deceleration not (the
  user's rule at 20:15); the drawn skull arrives late on an away throw
  (`chase_start`, `flight_end away caught late_s max_step_m`). Worn at
  20:30: "still disappears the instant the ballistic arc ends" while the
  drawn point's largest move was 28 cm; 1al switched the skull's culling
  off for the flight. **Worn at 20:45: "Yep, that fixed it."** The engine
  culled the unit by its root while the drawn parts were metres away.
  CLEARED. Item 3 is complete: the user's order at 20:45, "Run through
  steps 4-8". Also open: "for a short while the skulls were no longer turning
  with me" (20:05), now logged as `state from= to=` rows.
- Cloth on the body: still jiggles as of 17:15. Either it settled with the
  smooth anchor and the calibrated camera, or it ships as a known issue.

### 4. Bring the changelog up to date

`CHANGELOG.md` "Unreleased" (and the short form in `docs/NEXUS-PAGE.md`)
was written on the 18th. It does not yet have, from the 19th:

- The full body no longer flickers while moving (it was placed on a
  different timeline from the view), and its legs run the game's own
  animation if item 1 ships that.
- The view is placed at your calibrated eye height on load and after a
  recenter (it stood 27 cm high before; this applies to everyone, not only
  the full body).
- The view moves smoothly every frame rather than stepping at the game's
  fixed rate (the anchor change of 15:10), which affects everyone.
- The Psykhanium mirror is a true mirror: fixed in the world, head on your
  headset, fingers matching, weapon in the reflected hand.
- Grabbing the flamer skull holds it in the hand and turns it with the
  hand.
- Servo skulls no longer flicker (the 18th's note says this; the 19th's
  fix is what made it true).
- Known issues to state: cloth on the full body jiggles; the mirror does not
  mirror the legs' left and right; the full body's feet follow the
  animation, not the floor, on slopes and steps.

Then retitle "Unreleased" to "0.3.0-alpha.1 (date)" on the day, as the
memory records for alpha.2 and alpha.3.

### 5. Run the full test suite, not the day's four

`ctest --test-dir build\windows-vs2022 -C Release` with the Visual Studio
CMake (`C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\ctest.exe`);
the tooling tests alone are the `tests/tooling/*.lua` files under LuaJIT,
which the day ran selectively (body_mirror, body_hand_rig, body_frame,
skull_throw, dmf_unique_hooks). Any test that fails on a release candidate
blocks it.

### 6. Rebuild the native components and record provenance

The package carries `d3d12.dll`, `darktidevr_native_capture.dll`,
`darktidevr-xr-harness.exe` from `build\windows-vs2022\...\Release`, the DXC
runtime, the billboard shader DXIL, and every Lua module. Build Release,
then `tools\release\record-component-provenance.ps1 -OutputPath <explicit path>`
(the default path fails from bash; the memory records it), then
`tools\release\build-runtime-package.ps1 -ReleaseVersion 0.3.0-alpha.1 -OutputDirectory <explicit path> -ComponentProvenancePath <the record> -RequireComponentProvenance`.
The archive name embeds the commit (`darktidevr-0.3.0-alpha.1-<12 hex>.zip`);
`tools\release\test-runtime-package.ps1` checks it. Record the SHA-256.

### 7. Install the built archive fresh and play it

Not the dev install: extract the zip over a game folder, run
`Darktide VR Mode.bat`, launch through Steam, and do the item 3 pass on that.
This is the only test of the package as a user receives it, and 0.1.0-alpha.1
went out with the mode switch untested that way.

### 8. Documents that ship inside the package

`docs/USER-GUIDE.md`, `tools/release/package-README.txt`, `LICENSE`,
`THIRD_PARTY_NOTICES.md` and `CHANGELOG.md` are copied into
`mods\darktidevr`. The user guide needs the full body, the mirror (F8), the
skull grab and the calibrated camera height described as they ship; the
README's version line and any "known issues" paragraph need the item 4 list.

### 9. Publish, in the recorded order

From the mirror memory, as done for alpha.2, alpha.3 and 0.2.0-alpha.1:
the user publishes on Nexus first; then date the changelog heading and
record the publication in a commit; fast-forward `main` on both remotes to
the branch (`git fetch . <branch>:main`, then push `main` to `origin` and
`github`, and update the local `main` the same way, never by force);
annotated tag `v0.3.0-alpha.1` on the commit the archive was built from
(not a later doc commit), pushed to both; `gh release create v0.3.0-alpha.1
--latest --notes-file <notes>` with the sections Changes, Install, Archive
(archive name, build commit, SHA-256) and the zip attached. Update
`docs/NEXUS-PAGE.md` with the published changelog post.

### 10. Afterwards

Write the next-session pointer and the release memory (`darktide-vr-github-mirror`
records each release's tag and build commit). Open the next cycle's
checklist from the known issues in item 4 and the open items in
`docs/phase1/test-checklist-2026-09-19.md` (the animated legs on slopes,
the mirror's legs, cloth, the gait if it is kept as a fallback).
