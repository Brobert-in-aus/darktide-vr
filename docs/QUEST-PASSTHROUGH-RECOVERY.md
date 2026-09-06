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

## Follow-up: actionable tracking dialog

At approximately 08:02, after another wake/resume attempt, Guardian owned window
focus and UIAutomator exposed the actual dialog. Its enabled primary button
had text `Continue without tracking`, resource ID
`com.oculus.guardian:id/oc_dialog_primary_button`, and bounds
`[50,440][450,495]` on the logical 500-by-800 dialog display. A fresh dump verified
those values immediately before `adb shell input tap 250 467`. These coordinates
are evidence from this visit, not a reusable constant or stereo screenshot
coordinates. Future recovery must inspect the current UI again.

The click dismissed Guardian; UIAutomator next showed VR Shell, then Virtual
Desktop after resuming its launcher activity. This establishes an ADB route
through this specific tracking-loss prompt. It does not establish that accidental
double-tap caused the condition or that tracking was recovered. Travel mode and
boundary settings were not changed.

Ready progressed from HMD unavailable to HMD available and session creation,
then failed at `xrCreateSwapchain` with `XR_ERROR_RUNTIME_FAILURE`. A settled
retry had the same result. The VDXR log identified an `ovr_CreateTextureSwapChainDX`
failure with numeric result `-7000`; its underlying cause remains undetermined.
An ADB screenshot was black. Because this was now a persistent rendering failure
after successful resume, one restart of the Quest Virtual Desktop app was tried;
Ready still failed at the same call. The PC Streamer was not restarted.

Normal proximity automation was restored with Enable then Status in `finally`;
the headset returned to asleep. Darktide remained closed and no deployment was
performed. Do not claim renderability, positional tracking or worn acceptance.

Ignored evidence: `quest-continue-without-tracking-ready-20260907.json`,
`quest-continue-without-tracking-settled-ready-20260907.json`,
`quest-vd-client-restart-ready-20260907.json`, corresponding logs,
`quest-continue-proximity-restored-20260907.log` and the local dialog/after-click
screenshots under `artifacts/unattended`. Device XML dumps remain in the Quest
Download folder. None of those files belong in Git.
