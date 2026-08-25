# DarktideVR

Experimental Windows PCVR feasibility work for Warhammer 40,000: Darktide.
Phase 0's private-research feasibility gate is complete. The project contains
no anti-cheat bypass behavior. External Present observation is out of process;
the optional documented semantic camera probe uses the community Lua mod-loader
path only while EAC is explicitly inactive.

## Build

Use a Visual Studio 2022 x64 developer environment, or invoke the CMake bundled
with Visual Studio directly:

```powershell
cmake --preset windows-vs2022
cmake --build --preset windows-vs2022-debug
ctest --preset windows-vs2022-debug
```

Configuration fetches the official Khronos OpenXR SDK at the exact revision
recorded in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), builds its loader
DLL, and copies the DLL plus license beside the harness executable.

To include the compositor-visible headset test in CTest, configure with
`-DDARKTIDEVR_ENABLE_HEADSET_TESTS=ON`. It is intentionally opt-in because it
requires an active, renderable OpenXR session.

## Phase 0 tools

Fingerprint a local installation without starting the game:

```powershell
build\windows-vs2022\tools\fingerprint\Debug\darktidevr-fingerprint.exe `
  --exe 'X:\path\to\Darktide.exe' `
  --game-root 'X:\path\to\Warhammer 40,000 DARKTIDE'
```

Run a bounded, external ETW observation against an already-running known build
using the approved signed Intel PresentMon 2.5.1 binary:

```powershell
tools\present_observer\observe-present.ps1 `
  -GameExe 'X:\path\to\binaries\Darktide.exe' `
  -PresentMonPath '_downloads\presentmon-2.5.1\PresentMon-2.5.1-x64.exe' `
  -DurationSeconds 60
```

The observer rejects unknown game/tool hashes and invalid tool signatures. It
uses ETW and does not inject into or read memory from the game.

The optional Lua camera probe source is under
`mods/darktidevr_camera_probe/`. Its output can be validated with:

```powershell
tools\camera_probe\summarize-camera-log.ps1 `
  -LogPath 'X:\path\to\darktide-console.log' `
  -OutputJson 'artifacts\phase0\camera-summary.json'
```

With Darktide already at character select, run the guarded mono-source theatre
viewer in the headset:

```powershell
tools\theatre\run-darktide-theatre.ps1 -DurationSeconds 300
```

This is a live flat game image on a binocular OpenXR quad, not true scene
stereo. The wrapper rejects unknown game builds and an active EAC service.

The current same-tick stereo path is documented in
`docs/phase1/synchronized-stereo-probe.md`. With its exact reversible
skinner-guard patch and research viewport armed, consume the two isolated
1920x2160 shared eye resources as OpenXR projection views with:

```powershell
tools\stereo\run-darktide-shared-eyes.ps1 -DurationSeconds 300
```

Shared-eye submission is pair-driven by default: one `xrEndFrame` is issued per
new complete game pair. After 500 ms without a pair, loading/producer-loss
fallback updates at a bounded 33 ms cadence. Use `--continuous-shared` only for
a compositor-rate A/B diagnostic. The
legacy `run-darktide-stereo-sbs.ps1` filename remains as a compatibility alias.

Run the independent D3D12 `Present` smoke test and OpenXR discovery probe:

```powershell
build\windows-vs2022\tests\xr_harness\Debug\darktidevr-xr-harness.exe `
  --frames 120 --resize-at 60 --show --debug-layer
```

Add `--require-openxr` for a headset gate that fails unless an OpenXR session
can be created. Without it, the D3D12 smoke test can run when the runtime or HMD
is unavailable. The harness does not load Darktide.

With the headset awake and Virtual Desktop in the foreground, exercise the
compositor-paced stereo projection path:

```powershell
build\windows-vs2022\tests\xr_harness\Release\darktidevr-xr-harness.exe `
  --frames 300 --debug-layer --require-rendering --xr-frames 300
```

`--require-rendering` distinguishes a merely connected HMD from a session that
has reached `XR_VISIBLE`/`XR_FOCUSED` and is allowed to submit projection layers.

`--debug-layer` fails the run if the D3D12 info queue records corruption or an
error. `--resize-at N` resizes the flip-model swapchain before frame `N` and
verifies render-target recreation and device health.

See [Phase 0 status](docs/phase0/README.md) and the
[Phase 1 status](docs/phase1/README.md), plus the
[current bug review](docs/phase1/bug-review-2026-08-25.md), the
[design brief](docs/DARKTIDE-VR-DESIGN-BRIEF.md). The
[runtime observation protocol](docs/phase0/runtime-observation-protocol.md)
defines the explicit approval boundary before any Darktide process interaction.
