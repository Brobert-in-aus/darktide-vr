# Remaining development: melee, HUD and DLSS

Updated 5 September 2026. The user has reserved the headset for non-VD use;
development is offline until they resume testing. No game launch, deployment or
XR readiness probe is needed for the work below.

## Melee

Hand-directed button attacks and left-hand placement are accepted. Implement
physical contact according to [the selected rules](TRACKED-MELEE-DESIGN.md).
The offline foundations cover volume dimensions, rotational query planning,
contact deduplication, effective timing, per-target cooldowns and simulation
ownership. They do not yet query engine physics or apply damage.

Next integration work:

- Resolve the wielded weapon's explicit normal/heavy action routes and effective
  timing through its live action context; reject unsupported routes visibly in
  diagnostics rather than substituting guessed damage or timing.
- Build the non-damaging overlap/sweep adapter, preserving shield/world blocking
  and reporting saturated queries. Calibrate the grip-to-volume transform with
  a visible overlay when worn testing resumes.
- Introduce a dedicated stock damage context with explicit proc lifetimes and
  prediction ownership. Validate continuous contact and multiple targets before
  adding weapon specials. Do not invoke the stateful stock action hit routine
  indiscriminately on every overlap.

See [motion smoothing](MOTION-SMOOTHING.md): minimal physical-weapon lag, optional
light aim stabilization, one shared sample policy for presentation and attacks.

## HUD

The fixed-panel prototype is in `darktidevr_hud_panel.lua`, disabled by default.
It separates spatial elements from fixed status elements and uses a dedicated
offscreen target plus a completed-copy resource for world presentation. World
markers retain the accepted immediate-GUI path. Extreme-edge marker asymmetry
is [post-release polish](POST-RELEASE.md), not a reason to redesign that baseline.

The draw hook now restores the stock renderer and full element list after any
partitioned draw failure. Its offline fixture covers error recovery and once-per-
frame fixed authoring across two eye draws. This establishes CPU state recovery,
not GPU copy ordering or worn legibility.

Next: audit render-target completion, resizing and resource lifecycle; then make
the fixed status layout configurable without moving world/depth markers onto
the panel. The current one-metre, two-metre-wide panel remains an experimental
layout and needs worn acceptance. Loading, menus and transitions need dedicated
checks when the headset is available again.

## DLSS

The accepted graphics baseline uses DLSS Quality. Stereo frame generation is
unfinished. Existing native code observes Streamline, snapshots per-eye inputs,
packs stereo color, reserves transport and can stage a diagnostic backbuffer
copy. `STEREO_PRESENT_STAGE` explicitly reports `tags_staged=0` and no additional
Present submission. That is not a completed generated-stereo submission path.

The [current NVIDIA DLSS-G guide](https://github.com/NVIDIA-RTX/Streamline/blob/main/docs/ProgrammingGuideDLSS_G.md)
requires independently tagged viewports sharing one backbuffer. It does not
support a separate swapchain per eye. Tagged inputs must remain valid through
Present and constants must correspond to the presented frame. This supports the
existing packed-stereo direction, but does not prove compatibility with the
game's installed integration. The current guide is version 2.12.0; our read-only
ABI mirror targets 2.7.30. Do not construct new API structures from that minimal
mirror without checking the exact installed version and matching headers.

Next: prepare version-matched per-eye tag/constants staging, validate backbuffer
subrects and input lifetimes, then establish generated-output identity and GPU
completion before publishing to the XR consumer. The desktop frame rate alone
does not prove additional stereo frames reached the headset. Preserve the
accepted reconstruction jitter; historical per-eye reset experiments worsened
quality and throughput.

Offline frame-identity checks now reject the unknown frame sentinel and prevent
unsigned counter wrap from appearing as adjacent source timing. Native Release
and the corresponding test target build with warnings as errors; both Streamline
tests pass. These changes do not enable frame generation or replace its remaining
integration and live acceptance work.
