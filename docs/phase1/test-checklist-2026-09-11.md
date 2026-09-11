# Home test checklist, 11 September 2026 evening

Two worn sessions: **A** attributes the frame-generation blur around HUD
objects; **B** compares stock versus cylindrical atlas billboards. Both use
the accepted installation. None of today's review fixes or the new viewer
capture options are deployed, and nothing here deploys them.

## Preparation already done

- Ready preflight passed at the start of the evening:
  `artifacts/unattended/home-test-ready-20260911.json` (VDXR renderable
  session, Quest 3 awake, proximity override applied). Rerun Ready if the
  stream drops or the headset sleeps; do not restart Virtual Desktop merely
  because streaming is suspended.
- Installed files verified: native `FCCDD0DE...` at both locations, Lua
  `7B03E9E1...`, bootstrap `d3d12.dll` `7FA7FE77...`; no game or viewer
  process was running. Superseded at about 21:00 by the deployed
  [performance bundle](../PERFORMANCE-BUNDLE-2026-09-11.md): native
  `CAF9E0DF...`, bootstrap `E7ED3929...`, Lua `D3E733CD...` (transaction
  `deployment-f6350854edec4ce299d69aa1002cd721`).
- Eight stale presence-gated probe flags (seven `darktidevr_streamline_*_probe`
  files and `darktidevr_ngx_output_probe.flag`) were found in the installed mod
  root and would have activated diagnostics on every launch. They are backed
  up under `artifacts/unattended/home-test-flag-backup-20260911/` and removed.
  The launcher recreates the ones a switch asks for and restores them after.
- Saved DLSS configuration: `dlss=5` (Quality), `dlss_g=1`, Reflex on,
  windowed. Both billboard trial profiles pass `apply-trial.ps1 -ValidateOnly`
  against the current installation (`status=validated_only`).
- The launcher's viewer is `build/windows-vs2022/.../darktidevr-xr-harness.exe`
  (`36D60D68...`, 8 September); the accepted benchmark viewer `216E3F76...`
  lives in `build/xr-frame-stage-timing`. Pass `-Harness` to the runner only
  if you want to pin the accepted one; otherwise leave the launcher default.

## Launch

From the repository root in Windows PowerShell:

```powershell
tools/stereo/start-darktide-vr.ps1 -SkipDeploymentSync -EnableHudPanel -EnableMenuInput -DlssGeneratedStereo -AutoEnterHub
```

`-SkipDeploymentSync` is required: without it the launcher commits the
development checkout into the game (91 files, including the root's stale
8 September native build and today's unaccepted Lua). The first launch this
evening did exactly that; the game was stopped, the transaction
`artifacts/deployment-backups/deployment-78e2d36d...` was restored, and the
accepted hashes were re-verified before relaunching.
`-DlssGeneratedStereo` is the accepted FG-on configuration; it also enables
the isolated gameplay eye targets implicitly. Any FG-off launch that should
exercise the native ring must pass `-StreamlineEyeTargetProbe` explicitly:
the ring captures only named eye finals, and the first ring trial this
evening omitted the switch, so the ring never attached and delivery fell to
about 50 FPS (the descriptor-demand-alone case). Its log is archived as
`home-ring-trial-20260911/launch-attempt1-no-eye-targets.log`. For Session A's
FG-off arm, omit `-DlssGeneratedStereo` **and** set `dlss_g` to 0 in the
game's options before launching (the stock master DLSS toggle switches SR and FG together, so use
the individual controls). Verify the applied state in the console log
before comparing. Close the game gracefully between arms and let the launcher
finish its cleanup so the flags and settings are restored.

## Session A: frame-generation blur around HUD objects

Same scene, same standing pose, same per-eye extent and streaming settings
for every arm. A mission start or the Psykhanium range is better than the hub
because the HUD is fully populated. Keep the HUD panel where it is.

| Arm | SR | FG | HUD | Purpose |
| --- | --- | --- | --- | --- |
| A1 | Quality | on | visible | baseline, the reported symptom |
| A2 | Quality | on | hidden (`-EnableHudPanel` omitted) | is the blur tied to HUD presence? |
| A3 | Quality | off | visible | does FG cause it? |
| A4 | off (DLAA or native) | on | visible | does SR cause it? |

For each arm, report three regions separately, and say whether the blur is
present while still, appears during head movement, or persists after motion
stops:

- [ ] opaque HUD interior (text, icons)
- [ ] the translucent HUD boundary
- [ ] world pixels just outside HUD coverage

Also note, as separate observations, any duplicated or displaced HUD, any
difference between eyes, and whether the effect follows the HUD panel when you
turn your head. Please do not describe A2 as "no blur" unless you looked at the
same world region the HUD used to cover.

What the answers mean:

- A3 clean and A1 blurred: FG. Next step is tracing where the world-space
  panel enters the FG inputs (hudless colour, UI-tagged colour, or only the
  final backbuffer). A follow-up launch with `-ObserveDlssSrInputs` and
  `-NgxOutputProbe` collects that evidence.
- A4 clean and A1 blurred: SR history. Next step is the SR input capture at
  the reconstruction boundary before any mask or history change.
- A2 clean: the HUD's own contribution; candidate fixes are a separate OpenXR
  quad layer for the panel or tagging the panel as UI, each needing a worn A/B.
- All four blurred equally: not a HUD problem; record it as general softness.

## Session B: cylindrical atlas billboards

Only the two atlas shader files change; native, Lua and the accepted
raw-particle correction stay as they are. Run from the repository root.

1. Pick the scene where you see the smoke or haze problem and note how to
   reach it again (hub spot, mission start, Psykhanium). Close Darktide
   gracefully if it is running.
2. Stock control:
   ```powershell
   artifacts/unattended/atlas-billboard-home-trial-20260908/apply-trial.ps1 -Profile stock
   ```
   Launch with the line above, reach the scene, and look at the smoke while
   turning your head in yaw, then pitch, then roll. Note per eye: does the
   sprite face you, does it keep its authored spin, does anything jump near
   straight-up or straight-down views.
3. Close gracefully, then restore using the receipt path that `apply-trial`
   printed as `trial_installed=stock receipt=<path>`:
   ```powershell
   artifacts/unattended/atlas-billboard-home-trial-20260908/restore-trial.ps1 -ReceiptPath <path>
   ```
4. Cylindrical candidate:
   ```powershell
   artifacts/unattended/atlas-billboard-home-trial-20260908/apply-trial.ps1 -Profile cylindrical
   ```
   Same scene, same head movements, same notes. Also check behaviour right
   after a recenter and whether ground haze looks correct at floor level.
5. Close gracefully and restore as in step 3. Restore is required after an
   adverse or inconclusive result too; acceptance is only your worn report.

If the smoke you see does not change in either profile, the family you are
looking at is not one of the two staged shaders (`e18a...`, `fe640...`); say
so, and the next step is attributing that draw rather than adjusting these.

## Session C, optional: viewer capture policy

Only if time allows, and only after A and B are restored. The launcher has no
viewer override, so this needs the shared-eyes runner started by hand with
the fixed viewer built today, to confirm the capture worker stops cleanly
when the game closes while a menu is open (the hang fixed today):

```powershell
tools/stereo/run-darktide-shared-eyes.ps1 -EnableMenuInput -Harness build/focused-simulator-window-capture/tests/xr_harness/Release/darktidevr-xr-harness.exe
```

Expected in the viewer log: `openxr.capture_window=closed session_exit=clean`
followed by `openxr.lifecycle=stopped` and `result=pass`. This viewer is
`E8154112...`; it is not the accepted viewer and is not left installed. Skip
this session if A and B use the whole evening; the offline reproduction
already covers the fix.

## Wrap-up

- [ ] Confirm no Darktide or viewer process remains and that
      `restore-trial.ps1` ran after Session B.
- [ ] Recheck installed hashes (native both locations, Lua) match the values
      above.
- [ ] Restore proximity automation:
      `tools/quest/set-proximity-override.ps1 -Action Enable`.
- [ ] Tell me the per-arm observations for A and the per-profile notes for B;
      I will record them in the handover and pick the next step from the
      decision table above.
