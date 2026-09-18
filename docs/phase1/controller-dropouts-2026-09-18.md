# Why the controllers kept dropping, 18 September 2026

**The headset's controller-radio stack was in a bad state. Rebooting the
headset fixed it.** Not the batteries, not the controllers, not the mod, not
the PC.

Written after the fact, so the conclusion is the one that was confirmed by the
fix rather than the one that was argued for. Three earlier answers in this
document were wrong and are kept below, because the way each was reached is
worth more than the fact that it was wrong.

## What the log shows, independently of the fix

`SyncBossFW` and `SyncBossHAL` are the **headset's** sensor and radio
coprocessor, not the controllers. Through the whole window they are failing
their own operations:

```
18:56:40 E SyncBossHAL: Excessive enumeration duration (1549ms)
18:56:40 E SyncBossFW:  {WIHO}: Register read failed (-128)
18:56:40 E SyncBossFW:  {WIHO}: Failed to get or set pulsar value for reg 36 with error -128
18:56:41 W SyncBossFW:  {WIHO}: Got a TX timeout event when no requests were outstanding
19:15:10 E SyncBossHAL: Excessive enumeration duration (7661ms)
19:15:13 E SyncBossFW:  {WIHO}: Register read failed (-128)
```

Three things in there say "wedged" rather than "interfered with":

- **The headset cannot read its own radio's registers.** `Register read failed
  (-128)` is local to the headset; no controller is involved in it.
- **Enumerating a controller takes up to 7.6 seconds.** That is a
  millisecond-scale operation.
- **`Got a TX timeout event when no requests were outstanding`** — the radio
  reporting a timeout for a request that does not exist. That is a state
  machine that has lost track of itself.

And the packet statistics fit a degraded link rather than a broken controller:
loss of 24–66% at **strong** signal (RSSI −23 to −41 dBm), on both controllers,
where the same right controller had earlier run 750,000 packets at 2% loss.

The first of these errors is at **18:56:40**, well before the headset was put
on at 19:14:32. So the stack was already misbehaving before any of the visible
symptoms.

## Why it looked orientation-dependent

The right controller connected held sideways and dropped held upright, which is
what an antenna fault looks like — and it was the observation that nearly
produced a fourth wrong answer. A reboot does not fix an antenna.

In a degraded radio state the link is marginal rather than absent, so small
changes in orientation and in how the hand wraps the grip are enough to tip it
either side of working. The orientation dependence is a symptom of the margin
being gone, not of a directional fault in the hardware.

## Three wrong answers, and what produced each

1. **"The right controller was lost."** From `right_live=false right_flags=0`
   in the mod telemetry. Wrong: the **left** does exactly the same thing all
   session, three columns away in the same lines. Settled by the user pointing
   out that melee on the same trigger kept working.
2. **"The right controller's battery is browning out."** From eight
   `Reset reason: battery insert or brownout` lines. Wrong: the user had been
   pulling the battery to reset the controller, and every one of those resets
   lands about a second **after** a reconnect — a controller booting on a
   freshly inserted cell. The drops that mattered carry no reset at all, so the
   controller never lost power. 1249 mV is also unremarkable for a NiMH
   rechargeable, which sits at 1.2–1.25 V for most of its discharge; an
   alkaline curve was read onto a rechargeable.
3. **"It starts when the headset is worn."** The correlation was real —
   `PROX_ON` at 19:14:32, eleven seconds before the first bad disconnect, with
   1–2% loss before and 24%+ after. But the headset-side errors predate it by
   eighteen minutes, so donning revealed the fault rather than causing it.

The common thread: each answer came from correlating one signal and stopping.
The register failures were in the same file the whole time.

## Two things that were correctly ruled out

- **Virtual Desktop and the PC.** VD does not appear in the log after 14:56;
  through the whole bad window the foreground apps are the Quest's own shell,
  library panel and guardian dialog. The fault reproduced with the game not
  running and no streaming link up.
- **Band contention with streaming.** `TheVR` is on 5240 MHz, so it does not
  share a band with the controllers regardless.

## For next time

- **Reboot the headset first.** It costs a minute and it is the fix for this
  entire class.
- **Read `{WIHO}: Disconnected device stats: RSSI=..., rx=..., missed=...`.**
  Strong RSSI with heavy loss is a degraded link; weak RSSI with loss is range.
- **Connection and tracking are different columns.** `CONNECTED` / `SEARCHING`
  is the radio; `POSITION` / `ORIENTATION` / `NONE` is the cameras. Cleaning
  the lenses helps the second and cannot help the first, so it was never going
  to fix this one.
- **If it recurs often**, the register failures are the thing to report to Meta
  — they are headset-side and specific.

## What this does not explain

**The gun that stopped firing.** A controller with a degraded link delivers
nothing for a moment and then everything again; it does not deliver working
melee and a silent rifle on the same trigger. That remains open and separate,
and the shot-dispatch logging added on 18 September is what will answer it.

It also does not explain the hands and body flickering while running — the user
confirms the controllers were not flickering. That stays with item 52 and the
body trace.
