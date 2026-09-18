# Why the controllers keep dropping, 18 September 2026

Pulled from the headset over adb (`192.168.8.100:5555`, Quest 3).

**The controllers are losing a quarter to two thirds of their radio packets at
excellent signal strength, and only while the headset is being worn.** It is
not the batteries, it is not range, it is not one controller, and the PC is not
involved.

## Correction: the first read of this was wrong

This document first said the right controller's cell was browning out, on the
strength of eight `Reset reason: battery insert or brownout` lines. The user
then said they had been **pulling the battery to reset the controller**, which
is the other half of that reset reason, and the timing bears them out: every
one of those resets lands about a second *after* a reconnect, which is a
controller booting on a freshly inserted cell and saying so.

The drops that happened *before* any of that — 19:14:43, 19:14:57, 19:15:04 —
have **no reset line at all**. The controller did not reboot; the link died
while the controller stayed up. That is a radio fault, not a power one.

The voltage does not support a flat battery either. 1249 mV is unremarkable for
a NiMH rechargeable, which sits at 1.2–1.25 V for most of its discharge, and
the controller's own gauge shows 2 of 4 dots.

## What the radio statistics say

Every disconnect logs the link's own counters. `RSSI` is signal strength in
dBm, where anything better than about −50 is strong:

| time | RSSI | rx | missed | loss | headset |
| --- | --- | --- | --- | --- | --- |
| 18:49:56 | −39 | 250004 | 1308 | **1%** | off |
| 18:53:41 | −63 | 750867 | 15858 | **2%** | off |
| 18:56:40 | −38 | 89447 | 300 | **0%** | off |
| 19:14:43 | −34 | 133 | 253 | **66%** | worn |
| 19:14:57 | −25 | 333 | 279 | **46%** | worn |
| 19:15:04 | −28 | 66 | 63 | **49%** | worn |
| 19:16:25 | −24 | 14107 | 6953 | **33%** | worn |
| 19:16:54 | −23 | 1950 | 1424 | **42%** | worn |
| 19:17:03 | −30 | 470 | 486 | **51%** | worn, **left controller** |
| 19:17:51 | −24 | 2930 | 911 | **24%** | worn |
| 19:19:01 | −41 | 4635 | 1622 | **26%** | worn |

Two things fall straight out of that table.

**The signal is not weak — it is being corrupted.** The worst losses come at
the *strongest* signal readings (−23, −24 dBm). A controller that is too far
away or blocked by a body shows a weak RSSI and loss together. Strong signal
with heavy loss is what collisions look like.

**It starts when the headset goes on.** The only proximity event in the buffer
before the collapse is `PROX_ON` at **19:14:32**, eleven seconds before the
first bad disconnect. Every reading from the period the headset sat idle is
1–2% loss over hundreds of thousands of packets; every reading from the period
it was worn is 24% or worse.

**Both controllers do it.** The left shows 51% loss at 19:17:03. So it is not a
fault in one controller's radio.

## What was ruled out, and how

- **The batteries.** See the correction above. Both read 30% / 1249 mV, both
  are on 207.5.0 firmware, and the left does this too without ever having been
  reset.
- **Range or body blocking.** RSSI −23 to −41 dBm throughout.
- **Virtual Desktop and the PC.** VD does not appear in the log after
  **14:56**. Through the whole bad window the foreground apps are the Quest's
  own shell, the library panel and the guardian dialog. The streaming link was
  not up, so the PC cannot be the source — **and this reproduces in the Quest's
  own menus, with Darktide not running at all.**
- **The 5 GHz streaming network.** `TheVR` is on 5240 MHz, so it does not share
  a band with the controllers regardless.
- **A pending controller firmware update.** `update-required` appears 37 times
  but only ever on the *disconnected* lines; connected ones read `mcnt`, and
  both controllers report the same 207.5.0.

## What is left, and how to tell them apart

The controllers use a proprietary 2.4 GHz link. Something is talking over it,
and it only matters when the headset is awake and worn. In rough order of how
cheap they are to test:

1. **Something in the room on 2.4 GHz.** Put the headset on in a different
   room, well away from the router and the PC, and use the Quest's own menus
   for a minute. If the controllers behave, it is environmental. The router's
   2.4 GHz radio is the first suspect — `TheVR` is 5 GHz, but the same router
   is almost certainly also broadcasting a 2.4 GHz network.
2. **The headset itself, when its full stack is running.** If it is just as bad
   in another room, it is headset-side — the cameras, display and compute all
   start on don, and a desensitised receiver would look exactly like this.
   Worth a Meta support conversation with these numbers, which are more than
   most support paths ever get.
3. **Bluetooth.** The adapter has been on for 25 hours and is 2.4 GHz. It was
   also on throughout the healthy period, so it is not sufficient on its own —
   but if something paired to it starts streaming when the headset wakes, that
   would fit. Worth turning off for a test.

Not worth chasing: the headset is on AC power and was for the healthy period
too, so the charger and its cable do not correlate.

## What this does and does not explain

It explains the dropouts and the `live=false flags=0` telemetry, and very
likely the hands and body flickering while running (item 52) — a hand whose
pose stops arriving a third of the time is a hand that flickers.

**It does not explain the gun that stopped firing.** A controller losing
packets delivers nothing for a moment and then everything again; it does not
deliver working melee and a silent rifle on the same trigger. Both faults are
real and they are separate.
