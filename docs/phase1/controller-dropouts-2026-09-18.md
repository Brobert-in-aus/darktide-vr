# Why the controllers keep dropping, 18 September 2026

Pulled from the headset over adb (`192.168.8.100:5555`, Quest 3) after the
worn session. **The answer is hardware, not software: the right controller's
cell is browning out and rebooting the controller.** Nothing in the mod or the
viewer is involved.

## The finding

```
19:15:21 W/SyncBossInput [ruby (right) 5555144efd3a9ff0]: Reset reason: battery insert or brownout
19:15:22 I/SyncBossInput [ruby (right) 5555144efd3a9ff0]: Battery: 1249mV (40%)
19:15:22 I/SyncBossHAL   Controller 5555144efd3a9ff0 battery level changed: 0% -> 30%
```

Eight of those in the buffer, **all on the right controller, none on the
left**. "Battery insert or brownout" is the controller's MCU reporting why it
just restarted: either the cell was physically removed and replaced, or the
supply rail collapsed. It was not being removed and replaced eight times.

Each one takes the radio down with it, and the headset sees exactly what the
mod saw:

```
09-18 19:15:13  DISCONNECT
09-18 19:15:21  BROWNOUT RESET
09-18 19:16:25  DISCONNECT
09-18 19:16:42  BROWNOUT RESET
09-18 19:16:54  DISCONNECT
09-18 19:17:39  BROWNOUT RESET
09-18 19:17:51  DISCONNECT
09-18 19:18:46  BROWNOUT RESET
09-18 19:19:01  DISCONNECT
```

Roughly one a minute. The disconnect is logged a few seconds before the reset
reason, because the reason is only reported once the controller has rebooted
and re-established the link.

Downstream, `ControllerManagement` records the status ladder collapsing:

| status / tracking | count |
| --- | --- |
| `CONNECTED_ACTIVE` / `NONE` | 108 |
| `CONNECTED_ACTIVE` / `ORIENTATION` | 41 |
| `CONNECTED_ACTIVE` / `POSITION` | 40 |
| `SEARCHING` / `NONE` | 9 |

`POSITION` is full 6DoF, `ORIENTATION` is the IMU alone, `NONE` is nothing at
all, and `SEARCHING` is the headset hunting for a controller that is no longer
transmitting. Only a quarter of the samples are fully tracked.

`tracking: NONE` on a `CONNECTED_ACTIVE` controller is precisely the mod's
`DARKTIDEVR_CONTROLLER tracking_transition ... live=false flags=0`.

## The state of both controllers

```
Paired device: 5555144efd3a9ff0, Type:  Right, Model: RUBY, Firmware: 207.5.0,
  Battery: 30%, Serial: 2G0YZJ3F9Z00SF, Status: Searching, TrackingStatus: NONE
Paired device: 2f4c20989f8cae37, Type:   Left, Model: RUBY, Firmware: 207.5.0,
  Battery: 30%, Serial: 2G0YYJ5F9Z037D, Status: Searching, TrackingStatus: NONE
```

Both read 30 per cent. **The left one is about to do the same thing**, and it
has not been connected in the last 78 minutes of the buffer, so this window
cannot show whether it already has.

The measured 1249 mV is the number that matters rather than the percentage.
These take a single AA, and a cell at about 1.25 V has very little left: it
reads fine at rest and then sags below the brownout threshold the moment the
radio transmits. That is why it fails in bursts, under use, rather than simply
going dead.

## What was ruled out, and how

- **Interference from the streaming link.** The controllers use 2.4 GHz, so
  Virtual Desktop sharing that band would have been the obvious suspect. The
  headset is on `TheVR` at **5240 MHz** — 5 GHz — so it is not competing with
  them.
- **A pending controller firmware update.** `PairedControllerInfo` shows
  `update-required` 37 times, which looked like one. It is not: that string
  only ever appears on the *disconnected* lines (`connected` lines read `mcnt`
  instead), and both controllers report the same firmware, **207.5.0**. It is
  the disconnected-state string, not a pending update.
- **Anything in the mod or the viewer.** The reset is reported by the
  controller's own firmware, through the headset's input HAL, about its own
  power rail. The PC is not in that path.

## What to do

1. **Put a fresh AA in the right controller.** That is the fix.
2. **Do the left at the same time.** It reads the same 30 per cent and there
   is no reason to wait for it to start doing this mid-mission.
3. **If it comes back with a fresh cell**, it is the contacts rather than the
   battery — the spring or the terminal. "Battery insert" is the other half of
   that reset reason, and a cell losing contact for a millisecond looks
   identical to a brownout from the inside.

## What this does and does not explain

It explains the dropouts, the `live=false flags=0` telemetry, and very likely
the body and hand flicker reported as item 52 — a hand whose pose stops being
reported for a second at a time is a hand that flickers.

**It does not explain the gun that stopped firing.** That was ruled out on the
user's own evidence: the trigger was reaching the game (sound and animation
played), and melee on the same trigger kept working. A controller that has
rebooted delivers nothing at all for a few seconds and then everything again;
it does not deliver a working melee and a silent gun. Both faults are real and
they are separate.
