# Isolated motion-cleanup dispatch comparison

A utility-library compute program reads a pixel and writes zero only if any
component is NaN. Its 32×32 thread group and nearby `clean_motion_vectors` name
hash agree with the configured cleanup pass. This association still needs a
live PSO/dispatch match before any replacement is considered.

The manual benchmark compares the decoded program with a small behavioral
reconstruction compiled at 32×32, 32×8 and 32×4. It uses an RTX 4090 and the
captured SR motion extent, 1664×1792, in a typeless RG16 resource with an RG16F
UAV. Each trial uploads fresh pixels before its timed dispatch; upload and
readback are outside the timestamp interval. Two datasets cover finite values
and scattered NaNs, with infinities retained in both datasets.

All output pixels match the CPU expectation for all four programs in both
datasets. The debug-layer run also passes an explicit info-queue warning/error
check. The hardware timing run rotates order, discards two warmup rounds and
retains twenty rounds per dataset. Its results were captured before the later
synthetic game launch; the final debug check is validation only, not timing data.

| Dataset | Decoded original | Recompiled 32×32 | 32×8 | 32×4 |
| --- | ---: | ---: | ---: | ---: |
| Finite, median microseconds | 9.552 | 9.216 | 7.488 | 13.152 |
| Scattered NaNs, median microseconds | 10.752 | 10.752 | 7.808 | 13.248 |

32×8 is faster than the original in all twenty measured rounds of each dataset.
Median paired reductions are 2.048 and 2.832 microseconds respectively. This is
a small isolated gain, not a measured game-frame or stereo FPS improvement.
The same-compiler 32×32 control helps separate layout effects from compiler
differences. The cleanup operation has not been removed or weakened.

## Reproduction and scope

Build target `darktidevr-motion-cleanup-benchmark` in Release. Compile
`tools/renderer_probe/motion-cleanup-comparison.hlsl` with Windows SDK DXC
10.0.26100.0 using `-T cs_6_0 -E main -O3 -D GROUP_Y=N`, for N=32,8,4.
Pass the original container and those three outputs to the benchmark in that
order. Add `--debug` for the short validation run; debug timings are not evidence
of performance. This is a manual hardware experiment, not a CTest gameplay gate.

Original decoded-container SHA-256:
`baf7d38283e9620ec8665043f1f5a2c25a2291f3277013d93d4e7a362580c7b3`.
Its group is `dd8d138293b9ea32`, packed record offset 254178. The high 32 bits of
the `clean_motion_vectors` MurmurHash64A name are `5613271d`, occurring nearby at
offset `3e09a`. This is supporting static evidence, not a complete group parser.

Receipts are `artifacts/unattended/motion-cleanup-{hardware,summary,final-debug}-20260910.*`.
No game shader, setting or installed DLL was changed. The benchmark source and
reconstruction are committed; extracted game shaders are not.
