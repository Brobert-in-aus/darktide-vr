# Very early alpha readiness

Investigated 10 September 2026. This is a proposed release scope and evidence
checklist, not a release approval or a request to resume general gameplay testing.
The user's instruction to skip basic gameplay verification remains in force.

## Recommended first release

Aim for a small, invited technical alpha: Windows x64, the exact supported game
build, Quest 3 through Virtual Desktop/VDXR, right-dominant controls, button melee
and locally hosted SoloPlay missions. Require testers to own the game and install
the declared mod prerequisites. State explicitly that official matchmaking,
progression, other headsets/runtimes and broad GPU compatibility are unsupported
until separately established. This is a proposed support boundary, not a claim
that every component of this combination has passed release acceptance.

The initial promise should be: install a reproducible package, launch into stereo,
play a supported mission with accessible controls and readable essential UI, and
exit or recover without damaging the ordinary installation. It need not deliver
physical melee, complete weapon coverage, perfect visual polish or 120 FPS on
every system. A range-only preview could ship sooner, but must be named and
described as such rather than presented as a mission-playable alpha.

## Release blockers

| Requirement | Current evidence and gap | Minimum completion evidence |
|---|---|---|
| One reproducible release candidate | Accepted Lua, native and viewer come from different focused branches. The packager copies existing binaries and explicitly does not record their build provenance. | Select the component revisions deliberately; build/package them with source revisions, build options, file hashes and dependency versions recorded. Test this exact archive, not a nearby developer installation. |
| A usable supported-game installation path | Steam discovery, explicit installation selection, initial mod registration, transactional deployment and recovery exist. The runner requires an exact prepared executable hash. | Document and rehearse the supported executable preparation and prerequisite steps on a separate clean installation. Wrong versions must fail before mutation. Tester setup must not rely on this workstation's files or remembered manual edits. |
| Clean install, update and removal | Extracted package checks and copied-file recovery tests exist; they do not establish live clean-install/uninstall acceptance. | Install the archive, launch it, update it, recover an interrupted/failed update and remove it while preserving unrelated mods and user settings. Document return to ordinary non-VR launch. |
| Reliable stereo and safe input | Worn acceptance exists for selected controls and alignment. Fresh stereo is observed in live sessions; synthetic counters cannot establish comfort. | Confirm the packaged build keeps correct eyes, pose and scale through loading and supported transitions. Tracking loss must release held actions and recover or offer a clear restart route. No persistent black/flat fallback presented as successful VR. |
| A complete supported mission route | Mission entry and the crosshair are accepted; today's performance runs stop at a stationary mission start. Full objective/extraction coverage remains unestablished. | For a declared mission/loadout, record start, essential combat/actions, objectives, carried items, results and return; include death/spectating or explicitly limit that route until checked. Reuse existing accepted evidence and target the remaining gaps rather than replaying every basic control. |
| Accessible essential actions | Many actions are implemented; implementation does not guarantee a convenient saved controller assignment. Communication candidates include unassigned bindings and are not all deployed. | Publish a controller map covering movement, turning, attack/block, weapon swap/reload, interact, ability, Blitz and the selected mission's device/carried-item actions. Provide an explicit desktop fallback for secondary menus/chat if needed. No objective may require an undisclosed unavailable action. |
| Readable, binocularly usable essential UI | Pickup-popup asymmetry, billboards and blur around HUD items remain open. Offline capture foundations are not installed fixes. | Worn assessment of health, ammo, objectives, interaction prompts and nearby important markers. Fix defects that prevent reading/interacting or cause binocular discomfort; tolerable cosmetic defects may be documented with a tested workaround. Do not blanket-defer the reported asymmetry as edge polish. |
| Sustained session and recovery | Prior VDXR slowdown remains unresolved; interrupted/background measurements do not close it. | Complete the existing 60-minute worn-session gate on the package, including normal transitions and clean exit. Exercise one suspend/reconnect path or clearly require a safe restart when it cannot recover. Record crashes, stalls and original/generated/repeated frame delivery. |
| Supportable distribution | Dependency notices and a development package manifest exist. External mods remain separate. | Complete a payload inventory, retain applicable notices, verify which dependencies may be redistributed and provide separate installation instructions where needed. Ship no game content, credentials, machine identifiers, personal settings or diagnostic captures. |

## Performance policy for this alpha

Keep 120 Hz / approximately 60 original + 60 generated FPS as the preferred target,
with DLSS Quality as the tested starting point on the current RTX 4090 system.
The 10 September simulator mission-start results were approximately 119.4–119.5
distinct images/s with FG and 73–75 FPS native. Updated 11 September controls at
2496x2688 per eye deliver 89.57/89.34 native FPS with the opt-in descriptor and
native-ring candidate versus a fresh 76.47 FPS accepted-build control. Matched
FG controls deliver approximately 120 distinct images/s at both 120 and 144 Hz;
the higher refresh adds repeats. The older 141.85 result is not a matched control
for this batch. Neither establishes a minimum GPU, combat guarantee or physical
headset performance. Physical 144 Hz is not a release gate. See the
[native-ring evidence and acceptance limits](NATIVE-ORIGINAL-RING.md).

Before publishing settings guidance, measure a supported mission segment and the
sustained session on the exact candidate. Separate original FPS, generated FPS,
XR submission rate, repeated images and streaming/reprojection; record resolution,
hardware, settings and perceived latency. Offer a documented FG-off alternative
if stereo artifacts or latency make FG unsuitable. Do not silently enable VD SSW
or present generated frames as native throughput.

Keep mesh streaming normal initially. Its approximately 6–7% native improvement
when disabled costs about 1.7 GiB extra VRAM and lacks traversal validation.
Worker counts, LOD and texture pools must not copy this machine's settings blindly.
Deep engine optimisation remains valuable development work, but an unspecified
future optimisation is not itself a release blocker.

## Can wait beyond the first alpha

- Physical contact/damage melee; retain stock button-driven melee.
- Left-handed support, broad controller/headset/runtime support and non-NVIDIA
  support claims. Expose only the configurations actually validated.
- Two-hand/virtual-stock calibration across all weapons, comprehensive weapon
  family acceptance and full controller-only convenience in secondary screens.
- Official-server compatibility and multiplayer communication, if the release
  stays explicitly local SoloPlay. They become blockers if that scope expands.
- Perfect particle appearance, minor nonessential UI polish, selective smoke
  suppression and optimal LOD policy. Essential visibility/comfort remains gated.
- 144 Hz and further CPU/GPU gains once the declared baseline is supportable.

These deferrals narrow release scope; they do not remove active development bugs
or override the user's priorities.

## Practical next steps

1. Freeze the supported scope and inventory the accepted component revisions.
   Select which of today's viewer/native changes belong in the candidate; do not
   package the accumulated main branch indiscriminately.
2. Close the essential UI and action-access gaps using the user's worn feedback.
   Record severity and a tested workaround for anything retained as a known issue.
3. Produce the archive with per-component provenance and a short install/remove
   guide. Resolve the prepared-executable and dependency setup explicitly.
4. When release validation is authorized, run the targeted mission, sustained
   session and clean-install/recovery gates on that exact archive. Current
   documentation work does not authorize restarting the skipped gameplay suite.
5. Invite a small tester group with a support matrix, known issues, controller map,
   settings baseline and rollback instructions. Collect version, hardware/runtime,
   reproduction steps and opt-in sanitized logs; give each report a triage outcome.

No release date is supported by the evidence yet. The largest uncertainty is
package and end-to-end acceptance, not whether core stereo rendering exists.

## Sources inspected

- [Accepted controls and remaining coverage](phase1/todo-2026-09-09.md)
- [Accepted component map](handoffs/2026-09-08-night.md)
- [Today's performance and fixes](DEVELOPMENT-HANDOFF-2026-09-10.md)
- [Package limitations and prerequisites](RUNTIME-PACKAGE.md)
- [Mission control audit](MISSION-CONTROL-AUDIT-2026-09-08.md)
- [SoloPlay scope](SOLOPLAY-SETUP.md)
- [Deployment recovery](DEPLOYMENT-TRANSACTIONS.md)
- `tools/release/runtime-package-files.psd1`, `build-runtime-package.ps1` and
  `test-runtime-package.ps1`: payload list and development-candidate verification.

Validation of this investigation: repository documentation and package source
inspection, relative-link existence check and `git diff --check`. No game changes,
new gameplay tests, packaging, dependency downloads or release publication.
