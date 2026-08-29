# 2026-08-30 development session

## Authenticated launcher automation

The installed Fatshark launcher was decompiled read-only to determine whether
it exposes a supported autoplay or direct authenticated-game option. It does
not. `Launcher.ArgumentHolder` parses `Environment.CommandLine` only to append
arguments to the game command line. `Launcher.App` always constructs the WPF
main window, and `Launcher.UI.OnLaunchButtonClick` owns settings persistence,
the protected/unprotected executable choice, game-argument construction and
process startup. Starting `Darktide.exe` directly therefore remains a rejected
route; no Steam ticket, backend authentication or EAC bypass was added.

`tools/stereo/invoke-darktide-launcher-play.ps1` now automates that normal Play
handler. It fails closed unless all of the following are true:

- Darktide is not already running;
- exactly one `Launcher.exe` resolves to the expected installed-game path;
- its main window exists and has the exact title `Launcher`;
- the current launcher client has the known 1.55--1.67 aspect range and is at
  least 1000 by 600 pixels; and
- a new `Darktide.exe` process appears before the startup deadline.

The current launcher does not publish an external accessibility tree. A
background `PostMessage` experiment was correctly rejected when WPF ignored
the queued click and no game process appeared. The retained helper foregrounds
the verified window, converts the stable normalized Play centre to client
coordinates, performs one real click and immediately restores the original
cursor position. It never uses a hardcoded desktop coordinate.

`start-darktide-vr.ps1` now invokes this helper by default after asking Steam to
run app 1361210. `-ManualLauncherPlay` restores the old manual step, while
`-DoNotOpenLauncher` retains its existing external-launch/testing meaning. The
desktop `launch-darktide-vr.ps1` entry therefore performs Steam launch,
Fatshark Play, game-start confirmation and XR attachment without user input.

Live validation used the installed 1400 by 870 launcher. The helper clicked
client position 1145,757, confirmed a new Darktide PID, and the fresh game log
entered `StateTitle` with `auth_platform = steam`. The launcher then exited.
`SendCrashReports = false` was reapplied only after all stale launcher
instances were closed; it persisted through this clean launch. Console logs
remain available. The non-XR validation game was closed cleanly and the normal
ten-second Steam cooldown was observed.

Validation commands:

```powershell
# Parse the three changed launch scripts with the PowerShell AST parser.
[System.Management.Automation.Language.Parser]::ParseFile(...)

Start-Process 'steam://rungameid/1361210'
.\tools\stereo\invoke-darktide-launcher-play.ps1 -TimeoutSeconds 120

git diff --check
```

Result: all three scripts parse, the native helper live test passed, and the
working-tree diff contains no whitespace errors.

The first complete wrapper run exposed one additional Windows foreground-lock
case: a background PowerShell process could not foreground the WPF launcher
with `SetForegroundWindow` alone. The helper now temporarily attaches its input
thread to the current foreground and launcher UI threads, restores and raises
the verified launcher window, then fails closed unless that exact window has
actually become foreground. It detaches both input queues before clicking.
This is the standard Win32 foreground-activation sequence and does not weaken
the launcher's path, title, geometry, single-instance, or PID guards.

The subsequent end-to-end wrapper test passed. Steam opened the authenticated
Fatshark launcher, the helper activated and clicked Play, Darktide entered
`StateTitle` and then `StateGameplay: hub_ship`, the stereo mod logged
`DARKTIDEVR_STEREO active` and `native_capture publishing`, and the XR harness
attached the shared-eye resources with increasing nonzero `shared_ready` and
fresh paired frames. This validates the self-service authenticated XR launch
path rather than only the isolated Play helper.

Additional validation commands:

```powershell
.\tools\stereo\test-darktide-lua-source.ps1
.\tools\stereo\start-darktide-vr.ps1 -DurationSeconds 28800 `
    -EnableMenuInput -AutoEnterHub -DoNotOpenLauncher `
    -SkipDeploymentSync
```

Result: Lua source guard passed at 198/198 file-scope locals; the revised
launcher helper parsed; the authenticated wrapper reached live stereo in the
hub with nonzero `shared_ready`.

## Upper-limb IK industry comparison

The current architecture follows the usual tracked-avatar layering: preserve
the authored animation pose, treat head and hands as independent tracked
effectors, solve each arm as a two-bone chain, apply exact wrist transforms,
distribute axial wrist rotation over the rig's authored forearm twist bones,
and add bounded shoulder-girdle/clavicle contribution only near full reach.
Equal bilateral reach requests oppose and cancel at the girdle, while either
arm can independently request yaw and a small amount of clavicle protraction.

This is close to production practice in structure, but the shoulder layer is
not yet equivalent to a production full-body IK solver. It currently derives a
reach scalar from a hardcoded 94% arm-length threshold, rotates `j_spine2`
directly, and caps independent clavicle translation at 2 cm. A mature solver
would distribute competing hand effectors through a calibrated constrained
spine/shoulder chain using per-bone stiffness, anatomical rotation limits and
preferred bend angles. Darktide's heterogeneous character proportions also
make the planned T-pose/arms-down calibration important rather than optional.

The next production-quality refinement is therefore not another arbitrary
offset pass. It is a rig-specific constrained distribution layer: retain the
existing exact hand and twist behavior, derive per-avatar limb lengths from
calibration, give spine/chest/clavicle bones explicit stiffness and limits, and
validate unilateral, bilateral, crossed, overhead and tracking-reacquisition
paths. The current solution is an appropriate staged approximation for the
engine-access constraints, provided worn validation confirms its cancellation
and reach behavior.
