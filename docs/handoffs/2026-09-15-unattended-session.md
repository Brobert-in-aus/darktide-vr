# Unattended session, 15 September 2026

Branch `codex/alpha-4-2026-09-14`. Queue:
[todo-2026-09-15.md](../phase1/todo-2026-09-15.md), under
[the 14 September brief](2026-09-14-unattended-brief.md), with the same
boundaries:
- local scenes only;
- no publishing and no `main` changes;
- no settings changes;
- new features off by default;
- an evening checklist entry for everything deployed
  ([test-checklist-2026-09-15.md](../phase1/test-checklist-2026-09-15.md)).

Start of the day:
- Quest at 96 %, awake, proximity automation on.
- VR mode with the restored settings; no crash overnight.
- Heartbeat cron every 20 minutes.

## Settings safeguard (todo item 2)

Commit `cd132ea`.
- **Backup at launch.** When the mod loads, the capture library copies
  `user_settings.config` into `%LOCALAPPDATA%\DarktideVR\settings-backups` as
  `user_settings.<stamp>.config`. It copies only when the file is sound:
  - at least 2 KB;
  - braces and brackets balanced outside strings, and never closing before
    they open;
  - no zero bytes (a crash-truncated file is often zero-filled);
  - it has a `mods_settings` block;
  - it is not identical to the newest backup;
  - it is not smaller than 70 % of the newest backup (the reset file on
    14 September was half the size).

  Five backups are kept. Logged as `DARKTIDEVR_SETTINGS
  backup=saved|unchanged|missing|invalid|shrunk|failed`.
- **Restore.** `darktidevr-mode.ps1 -Mode restore-settings` (batch option 4)
  restores the newest backup and keeps the replaced file as
  `user_settings.before-restore-<stamp>.config`. Status names the newest
  backup.
- **Tests:** `settings_backup` (plausibility, zero-fill, unchanged, shrunk,
  rotation) and `mode_switch` (refused without a backup, newest restored,
  the replaced file kept).
- **Evidence (`run26`):** `backup=saved` at launch, with a 23.6 KB backup
  written.
- **Settings file.** The only differences from the restored 07:23 profile are
  DMF's defaults for yesterday's new options (grip bindings, haptics,
  holsters, two-hand, ammo readout). No values the user had set changed.

## Two-handing through reload and bash (todo item 6)

- **Commits.** The fix `c83db86` (last night) was deployed this morning. The
  synthetic once path now presses reload during each two-hand hold
  (`ca007b0`) instead of after firing.
- **Evidence (`run26`, Informative haptics).** Every hold with a reload
  press, where `weapon_reload_pressed` was delivered 0.6 s into the hold,
  logged `released ... ended=released` at the let-go 0.9 s later. Last
  night's worn holds logged `ended=cancelled`. The reload vibration fired
  when the reload finished.
- **Not shown:** bash while holding (unit tested only), and how it feels.

## Ammo count layout (todo item 3)

Commits `7efa0ef`, `fe0277d`, `10717e5`, `0da004b`.
- **Layout.** The clip count, a dash (a bar, so it never depends on the
  font) and the reserve are stacked as separate glyph boxes with a gap above
  and below the dash, centred in the reload ring. `Readout.stack_layout` is
  unit tested for no overlap, the dash midway, the stack centred and fitting
  inside the ring.
- **Eye renders** (readout test flag `front`, 0.5 m ahead,
  `artifacts/unattended/ammo-readout-20260915/run1`..`run5`):
  - `run1` separated the numbers, but the gaps were uneven (large above the
    dash, small below).
  - `run3` and `run4` calibrated the glyph extents against the dash bar,
    which is drawn at an exact position; `run4` let the dash touch the clip.
  - `run5` gives clear, near-even gaps (about 25 and 20 px at 1.5x crop).
- **Why the worn screenshot overlapped.** At hand distance the small reserve
  font renders relatively larger (0.63 of the clip's height instead of 0.5).
  The reserve's extent is therefore taken generously (0.30-0.90 of its size).
- **Not shown:** the worn view at hand distance.

## Research and designs (todo items 7 and 8)

- **Research notes.** Two background research passes, web sources only, each
  claim tagged [S] sourced or [I] inferred, copied to `docs/phase1/research/`:
  - two-handing and virtual stocks;
  - full-body IK.
- **Two-handed aim.** [two-hand-aim-design-2026-09-15.md](../phase1/two-hand-aim-design-2026-09-15.md).
  - The mod's aim model already matches VRExpansionPlugin, FRIK and XRI: a
    minimal swing on the dominant hand's pose.
  - The difference is the filter. The swing is smoothed in controller-local
    space, so wrist rotation drags the barrel off the support hand.
  - Offline measurement: a 10° wrist yaw with still hands leaves the barrel
    8.5° off the hands line on the next frame and 2° after 10 frames.
  - Proposed fix: filter the hands line in tracking space and recompute the
    swing from the current wrist every frame. Then a virtual stock anchored
    to a shared shoulder estimate.
- **Full-body IK.** [full-body-ik-design-2026-09-15.md](../phase1/full-body-ik-design-2026-09-15.md).
  - Maps how the gameplay avatar, first-person rig, gloves, upper-body proxy,
    camera and networking relate today.
  - Chooses a full-profile proxy (all cosmetics) posed by the mod, with legs
    copied from the stock avatar (the VHVR hybrid).
  - A body frame module owns the virtual shoulder for both the stock and the
    arm IK.
  - Revises the 14 September design; milestones are listed.
- **First step implemented and deployed: the steadying option.**
  Commits `9b1e549` and `ddaa54b`. Option *Two-hand steadying*: Classic
  (default, unchanged) or Hands line.
  - *Tests:* the pure tests pass.
    - A 10° wrist turn keeps the barrel on the hands line (0.00° off, where
      Classic gives 8.5°).
    - A stick turn has no lag.
    - 1 mm support jitter shows 0.013° against 0.17° raw.
    - A fast 10 cm sweep is within 0.1° after 3 frames.
    - Roll, release and ease-in are covered.
  - *`steady1` (Psykhanium, test flag `enabled_line`):* every synthetic hold
    released cleanly, with the same 9° steering as Classic in `run26` and no
    script errors. The synthetic path has no wrist rotation, so it cannot
    show the difference; that needs the worn A/B (evening item 4).

## Stray cartridge at the right glove (todo item 5)

Fix `abc400b`, deployed (evening item 5).
- **What it is.** The galvanic rifle receiver's column of rounds. Outside a
  reload the stock animation parks it on the gun at the grip, inside the
  character's wrist and sleeve. During a reload it moves into the
  magazine, which is why it vanished then. With the avatar's arms hidden
  (tracked gloves or the upper-body proxy), nothing covers it.
- **How it was found.**
  - *Scans* (`scan3`, `scan4`, dev flag `darktidevr_attachment_scan.flag`):
    listed every mesh and node of the wielded weapon. The receiver
    (`receiver_01`, 66 meshes) has cartridge-shaped meshes, four per round.
  - *View mode* (the same flag, `view ...`): while the rifle is wielded it
    holds the right controller at a fixed pose ahead of the headset. It also
    holds the trigger, grips and right stick so ammo and weapon stay put,
    and hides chosen meshes or attachments.
  - *Eye renders by elimination* (`artifacts/unattended/stray-bullet-20260915/`:
    `view2`, `bisect1`, `units1`, `units2`, `groups1`, `sets1`):
    - hiding the receiver removes the round, and the stock, barrel,
      underbarrel or muzzle alone does not;
    - it takes meshes 27-58 *and* 63-66 together, because overlapping rounds
      cover for each other;
    - the receiver has none of the likely visibility group names.
- **Fix.** `darktidevr_weapon_parked_parts.lua` hides those meshes while the
  avatar's arms are hidden, except during reload actions. The mesh table is
  keyed by attachment unit name and currently holds the galvanic receiver
  only.
  - *Test:* `weapon_parked_parts` covers selection, reload, stock arms,
    weapon change and failure restore.
  - *Evidence (`fix1`):* no round from three angles with no dev hiding; the
    drum and the rest of the gun draw normally; `parked_hidden meshes=36`
    logged; no script errors.
- **Ruled out on the way.** Moving the rig's mapped bones to follow the
  tracked gun (built, then removed before pushing). All 20 mapped bones
  already follow the attach node (`chain1`).
- **Not shown:** the worn view, and whether other guns have parked parts.
  The same scan and view flags can check them.

## Crosshair and iron sights (todo item 4): not solved

- **What is known.** The reticle sits where the aim ray hits (a raycast from
  the aim pose along the muzzle's direction). The gun is rotated so its
  muzzle points along that ray (`aim_angle_deg=0`).
- **Likely cause.** The aim ray starts at the controller's aim position,
  while the iron sights sit a few centimetres above the bore. The two lines
  run parallel rather than meeting at the target, leaving an offset of
  about 0.3° at 10 m. This is not measured yet.
- **Next.**
  - The scan's `sight` lines log the stock ADS eye point (the hidden
    first-person rig) and the VR aim origin, both in the muzzle frame, once
    ADS has been held for 0.8 s.
  - Needs ADS held: the synthetic path never presses the left trigger.
    Either a worn check or a synthetic ADS press, which is a viewer change.

Note: `run2` died because I piped the capture script through
`Select-Object -First 1`, which stopped the script and so the runner's job
(the runner force-stopped the game). The game did not fault.
