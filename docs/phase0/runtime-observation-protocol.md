> Historical research record. This is not the current operating policy or acceptance checklist. See [current status](../CURRENT-STATUS.md).

# Runtime observation protocol

**State:** External ETW and semantic Lua camera observation completed; native
renderer observation not executed
**Purpose:** Identify the final desktop swapchain using metadata only
**Authorization boundary:** Loading into or attaching to the game remains a
separate mechanism with a stricter gate

## External observation result

On 24 August 2026, the exact known build was launched normally through Steam
while the signed Intel PresentMon 2.5.1 console tool recorded DXGI ETW events.
This did not load a DLL into Darktide, open its memory, or modify its resources.

- The launcher explicitly logged `Using EAC: False`, started `Darktide.exe`
  directly, and left the installed `EasyAntiCheat_EOS` service stopped.
- One swapchain address accounted for all 12,080 presents during a 153.5-second
  capture. Candidate selection was therefore unambiguous.
- The output window measured 3072x1728. Of the captured presents, 12,075 used
  hardware-composed independent flip, three used hardware independent flip,
  and two used composed flip during startup transitions.
- Interval telemetry was p50 11.7654 ms, p95 19.5934 ms, and p99 32.8036 ms
  across startup and the operative-selection screen.

The ignored raw capture and JSON summary are under `artifacts/phase0/`. The
reproducible scripts live under `tools/present_observer/`.

A later synchronized capture paired 2,501 presents from one swapchain with 69
valid samples from the repaired semantic `CameraManager._update_camera` probe.
A separate 180-second main-menu soak observed 20,875 presents from one
swapchain with no crash and clean shutdown, but produced no camera samples
because that screen did not invoke the hooked gameplay-camera method.

## Hard gate

The native adapter's `evaluate_observation_request` decision defaults to deny.
It allows an in-process metadata-only experiment only when every condition
below is true:

1. The executable SHA-256, game version, and PE file version exactly match the
   known Phase 0 identity.
2. The operator explicitly opts in and declares the environment staged.
3. EAC is inactive.
4. No resource mutation, camera change, frame replacement, concealment, spoofing,
   or bypass behavior is requested.

The decision is not an anti-cheat compatibility claim. It prevents accidental
use of a future native observer under conditions this phase has not approved.
External ETW collection does not use this in-process permission.

## Permitted telemetry

For each factory/swapchain candidate, the planned experiment may record only:

- adapter LUID, device and command-queue identity;
- window handle and whether that window is visible/foreground;
- swapchain dimensions and description;
- present count, resize count, and present-interval mean/deviation; and
- session start/stop reason and the exact artifact fingerprints.

It must not read gameplay memory, inspect credentials or network traffic,
modify resources, change camera state, intercept input, or submit replacement
frames. Logs go under the ignored `artifacts/phase0/` directory and must not
contain machine-specific game paths.

## Candidate selection

The game-independent tracker requires a visible window, valid dimensions, and
at least 120 presents. It ranks candidates using surface area, foreground-window
status, and pacing stability. When the best two scores are within five percent,
selection fails as ambiguous instead of guessing. Resizes and timing statistics
remain attached to each candidate for review.

This matters because the inspected build routes D3D/DXGI creation through
`sl.interposer.dll`; a direct system-DXGI import is not the correct model and a
Streamline wrapper may expose more than one plausible swapchain.

## Staged execution sequence

For any future native observation, the smallest experiment is:

1. Re-fingerprint all build-scoped artifacts and evaluate the hard gate.
2. Confirm EAC is inactive and remain outside matchmaking and live services.
3. Start the game in the agreed staged mode and collect candidate metadata only.
4. Stop after the selection window; unload/exit and confirm no observer remains.
5. Review the log before permitting any camera correlation or rendering work.

If the environment cannot run Darktide with EAC inactive without bypassing or
concealing the observer, the native experiment stops and the project redirects
to an external-viewer design.

## Current evidence boundary

No Phase 0 native executable has attached to, injected into, or modified
Darktide. External ETW remained out of process. The separately documented
community mod-loader path patched the bundle database and loaded the read-only
Lua semantic camera probe while EAC was explicitly inactive; its pristine
backup and removal path are retained. The native policy gate and candidate
tracker have only run in unit tests with synthetic identities and timing
samples.
