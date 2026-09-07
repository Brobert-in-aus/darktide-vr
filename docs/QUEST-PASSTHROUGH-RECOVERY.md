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

## Follow-up: PC Streamer restart unavailable

After further offline development, a controlled PC Streamer restart was attempted
to test a different recovery boundary from the earlier Quest-app restart. One
Streamer process and one authorized ADB device were present; Darktide and the XR
harness were closed. Windows rejected stopping Streamer with `Access is denied`.
The command stopped there, so no replacement instance was launched and no PC
restart occurred. No privilege workaround, headset wake, proximity change or new
Ready result followed. The rendering failure remains unresolved; continue useful
offline work while the user is away.

## Follow-up: verified Guardian pause/resume command

At approximately 12:14, the installed SideQuest desktop 1.1.0 implementation
(`dist/sidequest-desktop/browser/chunk-JNO7CKtG.js` inside its application archive)
provided this reversible development command, shown as Android-shell input:

```text
am broadcast -a com.oculus.vrguardianservice.JsonCmdUserBroadcast --es cmd '{"settings":{"name":"guardian_paused","action":"set","val":true}}'
```

The Android shell command is the broadcast and JSON above; host-shell quoting
must preserve the JSON. Send `val:false` to resume Guardian. This sets a state,
unlike the earlier full-passthrough toggle. Meta also documents a development
Boundary toggle in MQDH's Device Manager, with restoration after development:
[Manage your Headset with MQDH](https://developers.meta.com/horizon/documentation/unity/ts-mqdh-basic-usage/).

One bounded attempt applied proximity Disable/Status, sent the pause command,
resumed VD and ran default Ready preflight. Guardian's own log confirmed the
preference change; cleanup sent `val:false` and the log confirmed `1 -> 0`,
`paused via pref store : 0` and Guardian resume. The older
`getprop debug.oculus.guardian_pause` query remained empty before, during and
after this change: it cannot verify this preference-based route on this headset.
Broadcast success alone is also insufficient; use the receiving service's
state-change evidence.

The immediate Ready attempt still reported HMD unavailable, before session or
swapchain creation; its timestamp preceded the logged pause completion. A second
bounded attempt at 12:16 allowed 15 seconds after pause/resume, recorded Guardian
paused before Ready, and reached HMD/session creation. It failed at the same
`xrCreateSwapchain` / `ovr_CreateTextureSwapChainDX -7000` boundary. Therefore this
verified Guardian route has not resolved the rendering blocker. Cleanup again
confirmed `guardian_paused: 1 -> 0` and `paused via pref store : 0`.

No game launch, deployment or permanent monitor followed. Normal proximity
automation was restored in `finally`; its immediate power sample remained awake.
Boundary pause does not establish tracking recovery or a double-tap cause.

Ignored local evidence: `quest-boundary-ready-20260907.json` and the matching
pause, restore, state-evidence and proximity logs under `artifacts/unattended`;
the settled attempt uses the `quest-boundary-settled-` prefix.

## Follow-up: swapchain failure diagnostics

At 12:41, harness `03d60d1` added failure-only diagnostics and a settled Ready
attempt collected them with Guardian paused. The first eye failed with OpenXR
result `-2`: width 2496, height 2688 (the reported recommendation), format 29,
sample count 1, usage flags 33, one array layer/face/mip. The application D3D12
device returned `GetDeviceRemovedReason = 0` and its debug message queue contained
zero messages. VDXR still reported `ovr_CreateTextureSwapChainDX -7000`.

This rules out an observed removal/debug-layer error on this application device;
it does not inspect VD's internal device, prove memory availability or identify
the runtime's underlying exception. No texture parameter fallback or graphics
setting was changed. The bounded smoke completed normally with exit 1, complete
captured output and `timed_out=false`. Guardian restoration was confirmed by
`1 -> 0` in its log, and proximity Enable/Status ran in `finally`. Darktide stayed
closed and nothing was deployed. The next retry needs a new recovery condition,
not another identical smoke run.

Ignored evidence uses `quest-swapchain-evidence-` under `artifacts/unattended`.

## Follow-up: exact runtime source and backend diagnostic

The installed log identifies VDXR 1.0.10 source revision
`f17345f7dbc7bc52395eaedb7aa15bfa13a675bf`. A read-only checkout of that revision
is under ignored `_downloads/VirtualDesktop-OpenXR-source`. Its
[D3D12 interop](https://github.com/mbucchia/VirtualDesktop-OpenXR/blob/f17345f7dbc7bc52395eaedb7aa15bfa13a675bf/virtualdesktop-openxr/d3d12_interop.cpp)
creates a separate D3D11 submission device for OVR. The failing
[swapchain call](https://github.com/mbucchia/VirtualDesktop-OpenXR/blob/f17345f7dbc7bc52395eaedb7aa15bfa13a675bf/virtualdesktop-openxr/swapchain.cpp#L387)
uses that device, not the application's D3D12 device. Its error wrapper logs only
the numeric OVR result. The pinned LibOVR header (`3621783c`) names `-7000` as
`ovrError_RuntimeException`; this category does not identify the internal cause.

Harness `4298262` reads the optional `ovr_GetLastErrorInfo` export only from the
already loaded Virtual Desktop backend, immediately after swapchain failure.
It never loads or initializes another backend. The verified ABI contains one
32-bit result and 512 text bytes; output is bounded. This is a thread-local last
error query and may be empty or stale, so it cannot replace the failed XR result.
Release build and four focused desktop/argument checks pass.

One settled Ready attempt at 13:15 collected `result=0 text=` from that query;
it did not provide further detail. The same first-eye texture request failed,
with no application-device removal/debug message, complete output and no timeout.
Guardian restored with logged `1 -> 0` and proximity Enable/Status ran in cleanup.
No game launch/deployment. Ignored evidence uses `quest-backend-error-20260907-`.

The accessibility JSON warning does not establish a corrupted setting: the file
is absent here, and the inspected source tries parsing an empty string in that
case. Its factory catches the error and returns no optional accessibility helper.
No accessibility file was created or changed. The official
[VDXR trace procedure](https://github.com/mbucchia/VirtualDesktop-OpenXR/wiki/Capturing-debug-traces)
uses its installed WPR profile and an elevated capture; a read-only WPR status
query found no recording. No trace session or support message was started.

At 13:56, read-only Application and System event queries covering 13:10–13:20
completed without access/query errors. Across all event levels, no Application
messages matched Virtual Desktop/LibOVR/OpenXR/the harness, and no System events
matched Display, nvlddmkm or DxgKrnl providers. These filters found no additional
evidence; they do not establish that the backend had no internal error. The
current Windows token is not elevated, so the documented elevated trace has not
been started. No new Ready attempt or device setting change followed this check.

## Double-tap preference ownership, 14:07

Read-only ADB settings/property inventory found no named Guardian or headset
passthrough shortcut in the standard global/system settings. Secure settings
contained `double_tap_to_wake=1`; AOSP defines this as the
[wake gesture setting](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/provider/Settings.java),
which does not establish ownership of Meta's headset shortcut. The sole matching
property, `persist.sys.fuse.passthrough.enable`, concerns
[filesystem FUSE passthrough](https://source.android.com/docs/core/storage/fuse-passthrough).
Neither value was changed.

The installed shell APK was copied read-only to ignored
`_downloads/quest-shortcut-inspection` and inspected with Android SDK tools.
It is `com.oculus.vrshell` version `207.0.0.539.436` / code `1051347662`, SHA-256
`ab8fde3129c15dac90d8455673412110570ca93a335ef37103ad472c13395f19`.
The APK/disassembly remain local and are not distributed in Git.

In this build, sensor handler `X.08B.onSensorChanged` reads the boolean
`passthrough_on_demand_enabled` through
`horizonos.os.preferences.PreferencesManager`. When enabled, it forwards a new
sensor timestamp to `IShellAPI.forwardDoubleTapEvent` after its one-second
initial grace period. The constructor selects `oculus.sensor.doubletap`.
The `double_tap_passthrough:is_enabled` string is a feature/config lookup,
not a standard Android settings key. If that lookup is false, setup is complete
and the preference is false, the handler writes the preference true. Thus simply
finding a writable preference would not prove a persistent disable under every
feature configuration. Native event handling remains a further boundary.

Service inventory exposes `PreferencesService` with the Horizon OS preferences
interface. Its `cmd ... help` request failed a transaction, and its diagnostic
dump explicitly returned `PERMISSION_DENIED` to ADB shell (despite an ADB exit
code of zero). No preference value was read or changed, and no service-call
transaction numbers, root access or identity workaround were attempted. This
identifies the actual Java event gate; it does not establish an available ADB
shortcut toggle, the current preference value, or the cause of the earlier
passthrough event. No XR session, wake/proximity override or game action ran.

## Opt-in runtime D3D11 diagnostics

The harness now supports `--runtime-d3d11-diagnostics`; the Ready preflight
forwards it with `-RuntimeD3D11Diagnostics`. It instruments D3D11CreateDevice
inside the harness process, requesting the D3D11 debug layer and recording up to
eight device results. If the optional layer is missing, it retries the original
flags only for that specific SDK-component error. Other creation errors remain
errors. Swapchain failure reports captured device removal reasons and up to
eight bounded debug messages per device, alongside the existing application
D3D12 and backend-last-error records. A successful session also reports them.

This covers D3D11 creation in the test process, not a proven attribution of every
captured device to VDXR. The inspected runtime's submission-device creation calls
that API. Instrumentation retains captured devices until scope exit and can
change execution/performance; it is a diagnostic condition, not a default or a
performance sample. It does not replace the installed runtime, change registry
settings, or attach to another process.

Release harness/fixture builds and seven focused CTests pass in 4.69 seconds.
The WARP fixture checks requested flags, original failure preservation, recorded
messages, the eight-record bound, rejected nested scopes and restoration after
scope exit. Desktop-only mode rejects the option before XR discovery. Missing
debug-layer fallback is environment-dependent; no layer was removed to force it.
The fallback uses Microsoft's documented
[D3D11CreateDevice error](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-d3d11createdevice).

At 15:37 the bounded Ready run captured one D3D11 device: original flags 32,
requested/actual flags 34, successful creation without fallback and removal
reason zero. Its debug queue contained two ID 381/error-severity records:
`ID3D11Device::OpenSharedResource: Returning E_INVALIDARG, meaning invalid parameters were passed.`
The first eye still failed with OVR -7000; application D3D12 messages remained
zero and backend last-error text empty. This adds a shared-resource import clue,
not proof of a stale handle, format mismatch or particular calling component.
[OpenSharedResource](https://learn.microsoft.com/en-us/windows/win32/api/d3d11/nf-d3d11-id3d11device-opensharedresource)
has resource/handle/interface requirements; the failed parameters are not yet
captured. No installed runtime change or deployment occurred.

The child exited 1 with complete output and no timeout. Guardian restoration was
confirmed in a time-bounded log query (`guardian_paused: 1 -> 0` and pref-store 0),
then normal proximity restoration completed. Darktide and the harness are closed.
Evidence: `artifacts/unattended/quest-internal-d3d11-20260907-153717.json` and its
recovery log. A fresh Quest Virtual Desktop client connection is the next scoped
recovery test for the newly observed import failure.

At 15:40 the Quest Virtual Desktop app was stopped and relaunched; its process
changed, with an empty process check between stop/start. After 20 seconds, Ready
again reached the same first-eye error and two OpenSharedResource E_INVALIDARG
messages on its sole captured D3D11 device. A fresh client process did not clear
the observed failure; this does not prove all PC-side session resources reset.
Guardian logs confirm 0 -> 1 -> 0 and normal proximity restoration completed.
No game/deployment or PC Streamer restart. Complete output, no timeout. Evidence:
`artifacts/unattended/quest-fresh-vd-client-20260907-154028.json` and recovery log.
