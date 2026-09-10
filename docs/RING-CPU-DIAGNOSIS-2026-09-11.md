# CPU diagnosis after the native delivery improvement

Quality delivers about 89.5 native FPS with the descriptor/ring candidate;
Performance delivers 95.80. Three further hook optimisations do not demonstrate
a live gain. Two isolated observations now investigate the remaining cost.

## Presentation-thread observation

Focused `a7ba197` adds the unchanged `PresentCpuProfile` observer to ring source
`10550a4`, without the additional hook-cost candidate. It records 240 intervals
after a 600-call stable-generation warm-up, measuring thread CPU and wall time
inside the outer Present hook and between its entries. Windows CPU accounting
is quantized; use aggregate means rather than per-frame CPU percentiles.

DLL SHA-256:
`83E4D445F4C4DBA3747A1F12FC87484815257E3523D6C2259BAC1875862EAF10`.
Windows x64 Release build and focused `native_capture_hooks` pass. The identical
profile header has no Git diff from the tested source; the root module's two
disabled/enabled checks pass after building their initially absent executable.
Receipts: `artifacts/unattended/ring-cpu-profile-*-20260911.log`.
The runner enables/restores the profile flag and requires the full 240-record
window. Mission capture is in progress; its FPS is diagnostic output.

## Descriptor-binding follow-up

Focused `3267863` applies only the descriptor-copy metadata guard to the previous
stage observer `0f53d13`. DLL SHA-256:
`46D98E6514C37BACF59E334DA30933BFE76FC2238FCC3C38202CB0B1A8B1BF09`.
The original observer DLL is preserved at
`artifacts/native-baselines/56A5A086-compute-stages.dll`. Release compilation
passes. The observer itself is unchanged; this comparison will use the same
4,096-record capture and reader checks. Its purpose is to compare instrumented
binding stages, not derive a whole-frame speedup from overlapping worker times.
