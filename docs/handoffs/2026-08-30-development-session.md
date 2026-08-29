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
working-tree diff contains no whitespace errors. A full VDXR session was not
needed for this launcher-only gate; the established wrapper still starts the
XR harness as soon as the confirmed Darktide process appears.
