# DLSS unattended continuation, 6 September 2026

Branch: `codex/dlss-live-integration-2026-09-05`.
User authorized unattended headset setup and development while away.
Proximity override Disable/Status and default Ready preflight passed. VD/VDXR
remained connected. Character selection required an observed desktop Start
click; Psykhanium entry was armed while the game was closed.

## Packed Present copy

Launch: `tools/stereo/start-darktide-vr.ps1 -EnableHudPanel -EnterPsykhanium -StreamlineStereoStageProbe`.
The first attempt exhausted the 16,384-record diagnostic log before gameplay.
The logger now reserves half its bounded capacity for stereo transaction and
input snapshot records. The retry captured a complete transaction:

- Runtime eye/final/HUD-less size 2496x2688; engine depth/motion/input 1664x1792.
- Packed 4992x2688 image matched the actual Present target, format 28.
- Source frame 4167 reached the packed Present copy at outer frame 4174.
- Copy fence 5 completed. No extra Present, new stereo tags, or XR generated
  metadata were submitted. Both input-processing fence references were retained;
  they were pending at observation and describe the game's existing inputs.
- OpenXR continued delivering fresh pairs with zero reported pose mismatches.
  This is unattended transport evidence, not new worn visual acceptance.

Ignored evidence: `artifacts/diagnostics/dlss-live-20260906/stage-copy-probe.tsv`
and `stage-copy-report.txt` (`result=pass`). The exhausted log is preserved too.

## Submission preparation

`StreamlineSubmission::prepare` no longer retains a frame token. `stage` requires
the caller to provide it at the actual submission point and retains it through
cleanup. Tests cover a null token, a different token on a later batch, partial
API failures, cleanup retry and both completion tickets. Native code still does
not call `stage`; this change does not certify a token's Present ownership.

The next live diagnostic records current per-eye constants/token identity and
successful game DLSS-G options at the prepared Present boundary. It makes no
additional Streamline API calls. This is needed before selecting a fresh token
and enabling/configuring paired viewport submission.

The pinned [NVIDIA 2.7.30 guide](https://github.com/NVIDIA-RTX/Streamline/blob/v2.7.30/docs/ProgrammingGuideDLSS_G.md)
supports multiple viewports writing one backbuffer, independent tags, matching
frame identity and retained inputs. A successful packed copy alone satisfies
none of the remaining temporal-history or generated-output identity requirements.

## Validation

Windows x64 Release native capture, submission tests and official-header ABI
reference builds passed. `ctest --test-dir build/windows-vs2022 -C Release
--output-on-failure -R '^(stereo_color_resample|streamline_(submission|input_lifetime|stereo_inputs|abi_reference))$'`
passed all five tests. Launch retained the LuaJIT gate. No Lua source changed.
`git diff --check` passed.

Next: inspect the current-frame/options diagnostic, then integrate paired SL
submission, cleanup and retirement before attempting generated XR publication.
Keep accepted HUD, menu, resolution and LOD configuration intact.
