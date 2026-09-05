# DLSS offline continuation

User explicitly switched interim work from queued menu acceptance to DLSS.
Branch: `codex/dlss-submission-2026-09-05`, based on menu commit `322ac82`.
VD remains closed. No deployment, launch or live test occurred.

Added paired tag/constants preparation and input-retirement bookkeeping.
The pair owns stable descriptors and copied constants, rejects unknown ABI
versions/chains and cross-eye aliases, and preserves jitter/matrices. The
lifetime guard requires per-eye completion tickets plus tag clearing before
retirement after Present. Submission identifiers cannot be reused. The owner
must still retain GPU resources and fence COM references; these helpers do not
call Streamline or represent enabled frame generation.

Validation on Windows x64:

```powershell
cmake --build build/windows-vs2022 --config Release --target darktidevr-streamline-input-lifetime-tests darktidevr-streamline-stereo-inputs-tests darktidevr-streamline-abi-reference
ctest --test-dir build/windows-vs2022 -C Release --output-on-failure -R '^streamline_(input_lifetime|stereo_inputs|abi_reference)$'
git diff --check
```

All three Release builds and tests passed, with compiler warnings treated as
errors. The ABI test uses the locally configured official 2.7.30 headers;
they remain outside Git. No Lua changed, so no Lua compilation was needed.

Next offline work: connect preparation and retirement to the native snapshot
owner, implement submission failure cleanup and resource transitions. Obtain
completion state through the existing coordinated Present-thread observation;
do not independently poll and consume presentation counters. Generated-output
identity and actual GPU completion remain necessary before publishing to XR.
Keep the accepted DLSS Quality/jitter configuration. Fresh Ready preflight is
required before the next deployment/live session. Menu acceptance remains
queued separately in MENU-INTERACTION-AUDIT.md.
