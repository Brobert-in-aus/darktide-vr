# OpenXR simulator dependency

The synthetic frame-generation benchmark uses the existing D3D12 XR consumer
with a process-local simulator runtime. It does not change the system OpenXR
registration or certify physical headset readiness.

Upstream: [OpenXR Simulator](https://github.com/elliotttate/OpenXR-Simulator),
[v1.5.0 release](https://github.com/elliotttate/OpenXR-Simulator/releases/tag/v1.5.0).
The Windows archive SHA-256 published by GitHub is
`2a67596a20d106e3f54e455533149fce8454e1d9f8959cb38daaabe9f65a1768`.
Its DLL SHA-256 is
`4b80eb1d85e3c61bfebd7dc5076086d1c74f53806530dac1a86f21d8f903bded`.

The release rendered 120/120 frames with our consumer, but `xrRequestExitSession`
reported EXITING immediately, leaving the application waiting for STOPPING.
The adjacent patch makes that request enter STOPPING, then makes `xrEndSession`
enter IDLE and EXITING. It checks the session handle and expected state. This
is a focused local compatibility fix, not a claim of full runtime conformance.
The upstream MIT license is included beside the patch.

## Reproduce the local runtime

1. Extract the v1.5.0 source archive, whose root identifies commit `88e18ed`.
   The downloaded GitHub zipball SHA-256 was
   `a6df91cb42bbeb0108e9f95c3a630b95801f26b87d00022d0bf0a1cb58b2cbbe`.
2. Apply `openxr-simulator-v1.5.0-shutdown.patch` from the source root with
   `git apply --check`, then `git apply`.
3. Configure the upstream CMake project for VS 2022 x64, setting
   `SIMXR_VULKAN_INCLUDE_DIR` to extracted Vulkan-Headers v1.4.321 `include`.
   Its tag archive SHA-256 was
   `cace1d5832fc00287c9b10b27577c41033b2c86434e884eef5c8dcea098d5118`.
4. Build Release. Use the generated `bin/openxr_simulator.json`, which contains
   the absolute DLL path. The release's bare DLL filename did not resolve with
   our app-local loader; no registry registration is needed.
5. Set `XR_RUNTIME_JSON` only in the test process, run the harness with
   `--flush-log --require-openxr --require-rendering --xr-frames 120`, and
   restore the prior environment value. Require 120 submitted frames, zero
   non-rendered frames, `openxr.lifecycle=stopped`, and `result=pass`.

The locally built DLL tested on 10 September 2026 had SHA-256
`fb154e4496611c111e757b8cc4c523d1f77543a7a69eff3387bb6021d5a02aa6`.
Rebuilt binary hashes can differ; the benchmark requires the explicitly chosen
DLL's hash rather than accepting any runtime manifest silently.

The optional `openxr-simulator-v1.5.0-refresh.patch`, applied after the shutdown
patch, adds a process-local `DTVR_SIMULATOR_REFRESH_HZ=120` clock selection.
Unset or other values preserve upstream 90 Hz. The wrapper exposes this as
`-SimulatorRefreshRate 90|120`, records it and restores the previous environment
value. Use the patched runtime for 120 Hz; older binaries ignore this setting.
The rebuilt DLL SHA-256 was
`c08da02708dcb68d450409118936034478cc98e3810b19d2788f5946ad618309`.
Its 120-frame smoke test rendered every frame, exited cleanly and passed;
elapsed time was 992.77 ms (the first frame does not wait a full period).

The simulator defaults to a 90 Hz frame clock. The benchmark disables desktop preview
copies and fixes Quest 3, 64 mm IPD and the requested eye resolution for both
frame-generation settings. Simulator submission rate is not headset latency or
a measurement of Virtual Desktop SSW. Neither `XR_EXT_frame_synthesis` nor
`XR_FB_space_warp` was advertised by this runtime in the smoke test.

[Meta XR Simulator](https://developers.meta.com/horizon/documentation/native/xrsim-intro/)
is another documented Windows D3D12 option. It has not been installed or tested
for this project. The selected open-source simulator allows the full existing
consumer to run; no separate buffer-drain implementation was needed.
