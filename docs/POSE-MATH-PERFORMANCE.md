# Pose composition normalisation cost

9 September 2026, offline core/native/viewer candidate, undeployed. This change
is not included in the staged native-only performance trial.

Pose composition normalised both input quaternions, then called public multiply
and rotate helpers which normalised them again. Composition now validates and
normalises each input once, multiplies directly and normalises the resulting
orientation. Its position rotation uses a private already-normalised helper.
This reduces six normalisations to three. Inversion uses the same private helper,
reducing two to one. Public rotate still normalises its input, and public multiply
retains its existing behaviour. No normalisation bypass is exposed publicly.

## Windows x64 offline validation

Native capture and the XR viewer build in isolated `build/xr-frame-stage-timing`.
Six focused CTests pass in 0.66 seconds: core math, pose performance, aim
stabilisation, panel pointer, pose snapshot and two-bone IK. These validate math
used by affected callers; no gameplay or worn visual test was run.

100,000 deterministic random parent/child poses compare new composition and
inverse against pre-change implementations compiled in a separate translation
unit with the same Release flags. Quaternion scales span 10^-15 to 10^15;
positions are within +/-10 units per axis. Orientation tolerance is 2e-6,
position tolerance 2e-5; the maximum observed component difference is 8.58307e-6.
Zero, subnormal-underflow, infinity, NaN and magnitude-overflow quaternion inputs
retain invalid-argument rejection for parent, child and inverse.

Five alternating-order trials of one million compositions measure old
42.2353-45.3082 ms (median 42.5970), new 23.7988-24.5152 ms
(median 24.0944). The baseline preserves the previous implementation's own
compiler inlining opportunities, instead of making it call current public
helpers across translation units. Timing is informational, not a pass threshold.

This is CPU transform throughput, not in-game FPS or worn acceptance. Removing
redundant normalisation changes floating-point rounding; outputs are not claimed
bit-identical. The input range and numeric limits above bound this comparison.

```powershell
cmake --build build/xr-frame-stage-timing --config Release --target darktidevr_native_capture darktidevr-xr-harness darktidevr-pose-performance-tests darktidevr-core-math-tests darktidevr-aim-stabilization-tests darktidevr-panel-pointer-tests darktidevr-pose-snapshot-tests darktidevr-two-bone-ik-tests
build/xr-frame-stage-timing/tests/core_math/Release/darktidevr-pose-performance-tests.exe
ctest --test-dir build/xr-frame-stage-timing -C Release -R '^(core_math|pose_performance|aim_stabilization|panel_pointer|pose_snapshot|two_bone_ik)$' --output-on-failure
```

Use Visual Studio 2022 Community bundled CMake/CTest here. Receipts in
`artifacts/unattended`: `pose-performance-build-20260909.log`,
`pose-performance-build-final-20260909.log`, `pose-performance-benchmark-20260909.log`,
`pose-performance-tests-20260909.log`. No installation, runtime, graphics or
headset changes. Preserve accepted mixed installation; any deployment needs Ready.
