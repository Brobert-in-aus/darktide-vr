# Quest passthrough recovery investigation

7 September 2026, approximately 07:12 headset log time. The user requested an
ADB route around the Guardian check, suspecting accidental double-tap passthrough.

Verified a reversible passthrough command from
[FrameLink's implementation](https://github.com/FrameLinkVR/passthrough-guard/blob/main/src/PtGuard.Core/Adb/AdbCommands.cs):

```text
adb shell am broadcast -a com.oculus.vrshell.intent.action.UPDATE_FULL_PASSTHROUGH -n com.oculus.vrshell/.ShellControlBroadcastReceiver --es toggle_point QuickActionMenu
```

This is a **toggle**, not an idempotent "off" operation. The first call logged
`isInFullPassthrough` changing from 0 to 1; the second reversed it. A prior generic
`PT is: ON` compositor log was insufficient to establish *full* passthrough mode.
Do not automatically toggle based on that generic log, a paused VD activity or
the presence of a Guardian activity. No historical DoubleTap event was confirmed.

Resumed the installed Virtual Desktop launcher activity with `am start`, without
force-stop/restart. VD became resumed, but a Guardian dialog appeared. A local
ADB screenshot read: "Finding position in room" and explained the headset could
not detect movement. It offered "Continue without tracking" and travel mode.
The generic Guardian activity name had not identified that condition earlier.
UIAutomator exposed only VD's surface, not actionable dialog controls; no blind
button press, boundary disable, tracking disable or travel-mode change was made.

Applied proximity Disable then Status before recovery. After the toggle/resume,
Ready preflight still failed with HMD unavailable (smoke exit 1, missing result).
Restored proximity Enable then Status in `finally`. No Darktide launch or new
deployment occurred. No persistent toggle monitor was installed.

Meta documents that entering system passthrough can pause immersive apps and
returning to immersive/resume reverses that lifecycle event:
[VRC.Quest.Functional.2](https://developers.meta.com/horizon/resources/vrc-quest-functional-2/).
The observed tracking-loss dialog is a separate remaining blocker. Rendering
with tracking disabled, if later enabled deliberately, must not be reported as
positional-tracking or worn acceptance.

Ignored local evidence: `artifacts/unattended/quest-readiness-20260907.png`,
`quest-passthrough-recovery-ready-20260907.json`, corresponding logs and
`quest-passthrough-proximity-restored-20260907.log`. The screenshot includes the
room and is not committed. No device identifier is recorded in Git.
