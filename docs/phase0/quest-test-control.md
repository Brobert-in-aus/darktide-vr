# Quest 3 unattended test control

The Phase 0 headset is a Quest 3 running Android 14 and connected to the PC by
authorized wireless ADB. On 24 August 2026, the following temporary override
kept the display/runtime active without depending on the wear sensor:

```powershell
adb shell am broadcast -a com.oculus.vrpowermanager.prox_close
```

Restore normal proximity/wear behavior with:

```powershell
adb shell am broadcast -a com.oculus.vrpowermanager.automation_disable
```

A headset reboot also clears the temporary behavior. The repository wrapper
locates one authorized Quest automatically and makes the direction explicit:

```powershell
tools\quest\set-proximity-override.ps1 -Action Disable
tools\quest\set-proximity-override.ps1 -Action Status
tools\quest\set-proximity-override.ps1 -Action Enable
```

## Safety and limitations

- This is a development convenience, not a permanent firmware setting.
- Disabling wear automation can leave the displays and streaming session active,
  increasing heat and battery drain. Restore it after unattended runs.
- The broadcast reports successful delivery but Quest does not expose a durable,
  authoritative query for the override. Reapply it before a test if uncertain.
- The override does not disable Guardian, tracking, cameras, or physical safety
  systems, and this project does not change those systems.
- Do not commit device serials, local IP addresses, ADB keys, or device logs.

## Validation

After applying the override and removing the headset, the strict harness
submitted 600/600 projection frames through VirtualDesktopXR at approximately
117.5 Hz, stayed `XR_VISIBLE`/`XR_FOCUSED`, reported no D3D12 debug errors, and
completed clean requested-exit/`STOPPING` teardown. This confirms unattended
operation on the inspected Quest 3 firmware; it is not merely a successful
broadcast-delivery result.
