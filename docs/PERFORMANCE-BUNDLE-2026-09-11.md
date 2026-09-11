# Performance bundle, 11 September 2026

The day's performance work is integrated on one line and built into the
launcher's own build tree (`build/windows-vs2022`), so a normal launch uses it
without trial wrappers or flags. This records what the bundle contains, what
its defaults now are, how it was verified offline, and what is still open.

## Contents (all on `codex/fresh-session-launch-guide-2026-09-11`)

The focused trial branches of 11 September were re-applied onto this line
during the day; nothing needed merging from them. The bundle is therefore the
branch head plus the changes below, built as:

| Component | Path | SHA-256 |
| --- | --- | --- |
| Native module | `build/windows-vs2022/src/producer/Release/darktidevr_native_capture.dll` | `CAF9E0DF7BACF5C20A2E0D82FA4C472BB423E0775E2BA0DCA52865371E31B9DC` |
| D3D12 bootstrap | `build/windows-vs2022/src/producer/Release/d3d12.dll` | `E7ED39290DEB169DBD536B950751266584BD361AD831A0B918047CF67DD0071C` |
| Viewer | `build/windows-vs2022/tests/xr_harness/Release/darktidevr-xr-harness.exe` | `1587F17202DD0A12CB287574130E469D1BA16B1052FEEE691838A7FB5D918487` |

Included native work (commit subjects on this branch): descriptor metadata
demand guards (`2ad852f`), the native original-frame ring and typeless eye
finals (`3507a93`, `41dade8`), enhanced-barrier capture lock filtering
(`7dfa753`), the gameplay mirror suppression control and counters, default
off (`7d2bda5`, `770ec42`, `96fe789`), batched stereo input and packed eye
colour transitions (`e41b0e3`, `fa4347f`), the DLSS-G completion-API
resolution and continuous-submission fixes (`8b31895`, `0288d86`, `e10997b`,
`347620f`), the review defect fixes (`d0a8633`), the DLSS quality-switch
recovery (`1214aea`) and, new here, bounded `binding_detail` logging on a
Present binding rejection. Included viewer work: batched packed original copy
transitions (`1a96172`), distinct-gap reporting (`f791f57`), runtime-owned XR
image states (`a8061e8`), paused desktop fallback capture during stereo
(`9856e00`), opt-in direct native ring copy (`4edf6fb`), the capture-worker
shutdown fix (`5b058cc`), deferred on-demand window capture (`f37b4be`) and
the flat-swapchain guards (`1eb20f1`). Bounded observers added during the day
stay opt-in behind their flags.

## Defaults changed in the launcher

`tools/stereo/start-darktide-vr.ps1`:

- Sets `DTVR_XR_PRECISE_PAIR_WAIT=1` and `DTVR_XR_NATIVE_ORIGINAL_DIRECT=1`
  for the viewer it starts (`-LegacyViewerTiming` restores the previous
  behaviour). Direct copies apply only when no generated frames are published.
- Native stereo launches (no `-DlssGeneratedStereo`) enable the native
  original ring beside both installed native modules and isolate the gameplay
  eye targets, restoring both flags after the run (`-NoNativeOriginalRing`
  keeps the legacy single-slot handoff). Persistent FG launches publish
  originals through the continuous submission and never construct the ring.

The simulator benchmark runner starts its own viewer and keeps its own
environment, so its FG-off runs pick up the ring through the launcher and
the direct copy only when a wrapper sets it.

## Offline verification (simulator, 2112x2304 per eye, hub spin, 120 Hz)

| Run | Native | Viewer | Result |
| --- | --- | ---: | --- |
| `synthetic-hub-bundle-fg-off-20260911` | CAF9E0DF (ring + isolated eyes by launcher default) | 1587F172 | 89.47 distinct native, clean exit |
| `synthetic-hub-bundle-fg-on-20260911` | CAF9E0DF | 1587F172 | 104.3 distinct over the runner's window (61.4 fresh + 42.9 generated); steady FG intervals 55.6 fresh + 54.8 generated = 110.4 distinct |
| `synthetic-hub-bundle-fg-on-accepted-viewer-20260911` | CAF9E0DF | 216E3F76 (accepted benchmark viewer) | 114.0 distinct over the window (57.0 + 57.0); steady 114.3 |
| `synthetic-solo-fg-a-20260911` (SoloPlay `cm_archives`, mission start) | CCC25279 (same source, focused build dir) | AD7DBEA6 (same source) | FG complete and published continuously, 0 context misses, 108.8 distinct over the FG intervals |

For comparison the day's controls were 92.6 native (D4AB131A, 2496x2688)
and 117.4 distinct FG (FB244186, 2496x2688). The bundle native with the
accepted viewer is within 3% of the FG control; with the bundle viewer the
steady state is about 3.5% lower again (110.4) and the runner's window lower
still because FG started later in that run. The viewer difference is small
and not attributed to a specific viewer commit. In both bundle FG runs the
engine rate dips to 47 to 55 FPS for a few seconds every 20 s of the spin
(the control dips to 55 to 57 in the same phase) with `present_mean_ms`
rising to 2 to 4 ms in those seconds; the same spikes appear on the FG-tested
lineage plus the quality-switch fix (`F5799F85`, run f), so they are not
specific to this bundle and are not attributed. The unit tests in the tree
pass (`continuous_recovery` on WARP).

## Deployment

Deployed on 11 September at about 21:00 by the ordinary development sync
(`tools/stereo/sync-darktide-vr-dev.ps1`): 91 files committed, transaction
`artifacts/deployment-backups/deployment-f6350854edec4ce299d69aa1002cd721`.
Installed afterwards: native `CAF9E0DF...` at both locations, bootstrap
`E7ED3929...`, Lua `D3E733CD...` with its modules. The previously accepted
native was `FCCDD0DE...` (Lua `7B03E9E1...`); restore that state with
`tools/stereo/restore-darktide-vr-deployment.ps1 -Manifest artifacts/deployment-backups/deployment-f6350854edec4ce299d69aa1002cd721/manifest.json`
if a worn session rejects the bundle. The normal launch is unchanged:

```powershell
tools/stereo/start-darktide-vr.ps1 -SkipDeploymentSync -EnableHudPanel -EnableMenuInput -DlssGeneratedStereo -AutoEnterHub
```

## Open

- Worn acceptance of the bundle as the baseline (the user's normal launch).
- The remote-server mission FG rejection loop (todo): reproduce worn with
  `artifacts/unattended/home-mission-fg-diag-20260911/launch.ps1`; the
  offline hub-to-range reproduction crashes on a stock husk-locomotion Lua
  error before the range loads (twice), and the SoloPlay path has no live-ring
  level transition.
- The unattributed Present-hook CPU spikes above.
