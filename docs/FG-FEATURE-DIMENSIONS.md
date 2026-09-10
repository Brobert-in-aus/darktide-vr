# Framegen feature-creation dimensions

Evaluation records show a shared 4224x2304 output and separate 2112x2304
backbuffer subrects at x=0 and x=2112. That alone does not establish internal
allocation or computation dimensions for each feature.

The opt-in NGX probe now records at most 16 FG creation attempts, reading
`Width`, `Height`, `OutWidth` and `OutHeight` before the original creation call.
These names come from [NVIDIA's NGX definitions](https://github.com/NVIDIA/DLSS/blob/main/include/nvsdk_ngx_defs.h).
Each value retains its getter result and whether the parameter ABI was verified;
an unsupported key is unknown, not zero size. The record includes creation
result and successful feature lifetime. It retains no parameter/resource pointer
and never changes a parameter or feature request.

Main and focused Windows x64 Release native builds pass. The focused candidate
starts from diagnostic-cleanup baseline `37e2cde` and changes only this creation
diagnostic. Its DLL SHA-256 is
`0147D5446F4485495ECCCD48968FE08F036A87136F1FAE5628183ACF912BA847`.
The bounded 30-second simulator mission capture completed successfully. All four
creation attempts succeeded, and all four getters returned success for each:

| Run-local lifetime | Width × Height | OutWidth × OutHeight |
| --- | --- | --- |
| 4, 5 | 4224 × 2304 | 2112 × 2304 |
| 6, 7 | 2112 × 2304 | 2112 × 2304 |

The bounded evaluation log contains 128 FG records each for lifetimes 6 and 7,
with the expected separate eye subrects in the shared wide output. Thus the
active observed features have per-eye creation dimensions; the earlier wide
setup features are not evidence of sustained full-width evaluation overhead.
Creation dimensions still do not measure internal work or total FG cost.

Mission exit, zero pose mismatches and exact restoration passed. Evidence:
ignored `synthetic-solo-fg-creation-dimensions-a-20260910`. No engine, feature
parameters, accepted installation or visual defaults were changed.
