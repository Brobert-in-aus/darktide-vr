# Live hub versus simulator: 10 September

The user's approximately 80 FPS hub observation is confirmed: a live interval
delivered 39.5721 original and 40.2543 generated pairs/s, 79.8264 distinct pairs/s.
The viewer submitted 81.8732 frames/s including 2.04683 repeated images/s.
Other foreground FG intervals ranged approximately 76–94 distinct pairs/s.
Quality DLSS and a 120 FPS cap were selected. No settings changed during inspection.

## Established differences

- VDXR recommends **2496x2688 per eye**, confirmed in both the Ready receipt and
  native eye-capture records. Earlier synthetic tests used **2112x2304**, giving
  the physical session about **37.9% more output pixels**. Matching DLSS mode did
  not make those workloads resolution-equivalent. This can increase rendering,
  reconstruction, FG and copy work; it does not quantify each contribution.
- The hub is a different scene from the stationary SoloPlay mission start.
  It has not been isolated from runtime, resolution, camera and population effects.
- The user confirmed frequent alt-tabbing. During a sampled background interval
  ChatGPT was foreground, native FG tickets reported one frame instead of two,
  and the viewer reported no new generated images. Foreground intervals with
  approximately equal original/generated rates remain valid. Do not average
  these different states together or simply halve the whole-session average.
- The live launcher used standard pair polling; synthetic runs explicitly enable
  `DTVR_XR_PRECISE_PAIR_WAIT=1`. Standard polling sleeps measured about 1.5 ms.
  This is another comparison difference, not a demonstrated explanation of the gap.

## What the current timing says

In a foreground 90.54 FPS interval, mean loop time was 11.043 ms: source-pair wait
7.003 ms, GPU-fence wait 3.530 ms and `xrEndFrame` 0.146 ms. This differs from the
previous sustained VDXR slowdown, where `xrEndFrame` rose above 9 ms while source
waiting was nearly absent. The observed interval does not implicate that older
submission-blocking failure as the current dominant delay.

Two GPU snapshots showed 75%/84% utilisation, approximately 290/298 W, 2715 MHz
and 13.5–13.6 GiB reported memory use. A five-second thread CPU sample found one
game thread consuming about 84% of a core, with several others at 36–51%.
These are snapshots, not enough to classify the whole run as exclusively CPU-
or GPU-bound. Source waiting also includes producer dependencies and scheduling;
it is not a direct measurement of engine rendering CPU time.

## Benchmark correction

`run-synthetic-framegen-benchmark.ps1` no longer silently assumes 2112x2304.
Pass `-VdxrReadinessPath` with a successful VDXR Ready receipt; the recommended
resolution is applied to simulator settings and its hash/time recorded in the
benchmark receipt. Both explicit eye dimensions remain available for deliberate,
labelled controls. Missing, failed, stale (>24 hours), ambiguous and non-VDXR
receipts are rejected before settings mutation. Refresh the receipt whenever
Virtual Desktop resolution settings change, even within 24 hours.

This consumes the runtime's effective recommendation, not a guessed translation
of Virtual Desktop quality presets. It is a snapshot, not live settings monitoring.
FOV, pose, refresh, streaming overhead and scene content are not made identical
by matching resolution alone. Do not run a preflight alongside the worn session.

Validation: resolver acceptance/rejection tests pass; today's actual Ready receipt
resolves 2496x2688 with its exact SHA256; PowerShell parsing and diff checks pass.
No simulator or second XR session was launched while the user was testing.

## Next comparison

When the live session ends, repeat the synthetic mission at 2496x2688 with the
same native/viewer, Quality, FG, cap and polling settings. Separately compare a
foreground physical hub and mission segment at the same resolution. Record focus
and stable FG delivery, and exclude loading/background intervals. These controls
are needed to apportion the gap between resolution, scene and runtime overhead.
There is not yet evidence that hub content alone causes the entire shortfall.

Local evidence: `artifacts/unattended/home-test-ready.json`,
`artifacts/unattended/home-headset-test-20260910/launch.log`, and the active
process's Streamline records. Raw local logs are not release artifacts.
