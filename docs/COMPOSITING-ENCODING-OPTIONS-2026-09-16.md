# Compositing and encoding: what runs, what can be switched (16 September 2026)

The 16 September profile ([LUA-FRAME-PROFILE-2026-09-16.md](LUA-FRAME-PROFILE-2026-09-16.md))
put the Hub's frame in the headset pipeline: the two eyes take at most 7 ms of
GPU alone and 23.5 ms with Virtual Desktop streaming, and the game is pinned
near 55 Hz regardless of scene load. The user asked what documentation or
options exist to speed up the compositing and the encoding. This is the
answer from the runtime's source, Virtual Desktop's guides and the
repository's own measurements. Facts with their sources; the last section
ranks the options.

## What runs on this PC's GPU per displayed frame, beyond the game

Three processes share the GPU while the game streams: the game, the mod's
viewer (the OpenXR application), and Virtual Desktop's streamer, into which
the OpenXR runtime VDXR is loaded through Virtual Desktop's LibOVR shim.

**The viewer** (`src/xr/main.cpp`): copies each fresh eye pair into its
swapchains and submits, in gameplay, two composition layers, the projection
and the reticle quad. It enables only `XR_KHR_D3D12_enable`; it requests
sRGB `R8G8B8A8` swapchains at exactly the runtime's recommended size
(`src/xr/main.cpp:5299-5324`); it submits no depth. Its own 3D-engine share
was measured at about 2 per cent (`artifacts/unattended/physical-streaming-gap-20260911/gpu-engine-activity.jsonl`).

**VDXR, per `xrEndFrame`** (source: `mbucchia/VirtualDesktop-OpenXR`,
`frame.cpp`, `precompositor.cpp`, `swapchain.cpp`, `session.cpp`):

| pass | runs when | switch |
| --- | --- | --- |
| alpha pre-process (compute) on a blended layer's image | the layer has `BLEND_TEXTURE_SOURCE_ALPHA` (clears or premultiplies alpha) | none; a function of the layer's flags |
| FSR1 EASU upscaling (compute), both eyes | `m_upscalingMultiplier != 1`, from registry `upscaling` (percent, default 100) | `upscaling` = 100 |
| CAS sharpening (compute), both eyes | `m_sharpenFactor > 0`, from registry `sharpen` (percent, default 0) | `sharpen` = 0 |
| depth handling | `quirk_use_depth`; Virtual Desktop "does not use the depth buffer for anything" (`RuntimeConfiguration.h`) | irrelevant; the viewer submits none |
| slow-path swapchains (the runtime's own three images and copies) | cubemaps, MSAA, NT-handle sharing, or `quirk_force_slowpath_swapchains` | not taken by the viewer (2D, 1 sample) |
| mirror window (copy of the right eye + a `Present` per frame) | `mirror_window` = 1 | default off |
| `ovr_EndFrame` on the asynchronous submission thread, with running start | default on; `quirk_disable_async_submission`, `quirk_disable_running_start` | leave on |

The registry key is `HKLM\SOFTWARE\Virtual Desktop, Inc.\OpenXR` (DWORDs;
`runtime.h`, `RegPrefix`). **On this PC the key does not exist** (checked
16 September; the active runtime is
`C:\Program Files\Virtual Desktop Streamer\OpenXR\virtualdesktop-openxr.json`),
so every value is at its default: no upscaling pass, no sharpening pass, no
mirror window, asynchronous submission with running start. There is nothing
to switch off in the runtime; it is already at its cheapest for this viewer.

**Virtual Desktop's own compositor and encoder** (closed source; what the
repository measured): the streamer's 3D engine at about 6 per cent and its
two video-encode engines at 26 to 43 per cent each during play
(`docs/FRAME-PRODUCTION-2026-09-11.md:32-35`, the jsonl above). The encode
runs on NVENC, a separate engine; what competes with the game on the 3D
engine is the per-vsync composition and colour packing at the stream's
resolution, once per displayed frame, 120 times a second at 120 Hz. This is
the work the 16 September arms could not move from the game's side (queue
priority, process class, padding, frame generation), and it is proportional
to two things the user controls: frames per second and pixels per frame.

The repository also holds one measurement that bears on today's outlier:
with the headset asleep and no streamer engine above 0.1 per cent,
delivered frames rose 19 per cent (97.4 to 115.8 distinct FPS,
`docs/FRAME-PRODUCTION-2026-09-11.md:57-111`). A run whose headset dozed
sees less contention, which is the shape of `hub-gpuprio-high1`; the runner
now records the headset's wakefulness at the hold's midpoint.

**The streamer's recorded state on this PC** (`C:\ProgramData\Virtual Desktop\StreamerSettings.json`,
last written 16 September 15:27; read only): codec H.264+, automatic
bitrate off (a manual bitrate is in force; the guides recommend automatic,
which is a network matter rather than a GPU one), OpenXR runtime VDXR,
streamer 1.34.22, service 1.18.60, device Meta Quest 3. No streamer-side
sharpening, upscaling or game-priority value is recorded in the file; those
live in the Quest client or per connection.

## What Virtual Desktop's documentation offers

From the VR Discord community guide and the Aboleth deep-dive (sources at
the end), with the repository's measurements where they exist:

| setting | where | what it changes on the PC | measured or stated effect |
| --- | --- | --- | --- |
| Frame rate 72 / 80 / 90 / 120 Hz | Quest client | composites and encodes per second | not run here; a quarter fewer at 90 Hz; the game makes about 32 fresh pairs a second at either rate, the rest is the runtime's reprojection |
| VR Graphics Quality (Potato to Godlike) | Quest client | render target size, composite size, encode width | one step down (2496x2688 to 2112x2304): game GPU per stereo frame 25.6 to 21.9 ms, delivery 86-97 to 109 distinct (`docs/handoffs/2026-09-11-end-of-day.md:428-441`); already applied |
| Codec H.264 / H.264+ / HEVC / HEVC 10-bit / AV1 | Quest client | encoder work and its pre-pass | H.264+ about 10 per cent shorter game spans than HEVC 10-bit (`:378-389`); already applied. The guides: H.264+ lowest latency at high bitrate; AV1 and HEVC at high bitrates can spike on NVIDIA |
| Bitrate, automatic bitrate | Quest client | encoder rate control | a few per cent at most (200 vs 50 Mbps, `:380-384`); leave automatic |
| Sharpening | Quest client (CAS) | applied on the headset after decode | "negligible performance loss" (Aboleth); distinct from VDXR's registry `sharpen`, which is PC-side and off here |
| Synchronous Spacewarp | Quest client | headset-side frame synthesis | never enabled here; the guides say avoid unless motion sickness demands it |
| Video Buffering | Quest client | one frame of client-side buffering | latency, not PC load; guides disagree, VD says leave on |
| Boost Game Priority | Streamer (PC) | the game's Windows CPU process priority | "can help performance in some games... may cause lag in others"; not a GPU priority; untested here |
| OpenXR runtime VDXR vs SteamVR | Streamer (PC) | one compositor instead of two | already VDXR |
| Render resolution over 100 per cent (VD's `RenderResolution`) | Quest client | supersampling factor VDXR reports to the app | keep 100; "minimal visual gains" (Aboleth); the mod already renders at the recommended size |
| FOV tangent (Virtual Desktop, per cent) | Quest client | the frustum the runtime recommends, so pixels per eye | user set 90 per cent on 16 September: the eye went from 2112x2304 to 1908x2076, 19 per cent fewer pixels per eye for both the game and the pipeline; the mod takes the narrower frustum from the runtime (projection, padding and marker plane all derive from it). Measured twice (`hub-fov90-1`, `hub-fov90-2`, headset awake): 21.2 and 20.7 ms of GPU per pair against 22.5 to 23.2 for the day's normal-class arms, loop 59 Hz against 53 to 56, the size the pixel count predicts and repeatable: about a tenth off the pair's GPU. The first pipeline arm of the day with a real, repeated gain |

The performance overlay (both thumbsticks clicked) splits latency into
Game, Encoding, Networking and Decoding; the guides read "Game" as the GPU
bottleneck and "Encoding" as packing delay; decoding of 12 to 15 ms is
usual for AV1 or HEVC on the headset. Under 40 ms total is the target.

## What Windows and the driver offer

- **Hardware-accelerated GPU scheduling is on** (user, 16 September
  evening, checked in Windows' graphics settings). The engine's startup line
  "Hardware Accelerated GPU scheduler: false" is the game misreporting, not
  Windows. So the "untested arm" is already the state of the machine, and
  the 16 September null results for queue priority and the process class
  were measured with it on, which is where priority classes matter least:
  with hardware scheduling the GPU arbitrates its own queues. Both flags
  stay opt-in and closed.
- **Process and queue priority.** Measured 16 September: no demonstrated
  effect with hardware scheduling off; `realtime` starves the viewer.
- **Other GPU clients.** Anything else that composes or encodes during play
  (a browser with hardware acceleration, an overlay, a second capture)
  competes on the same engines; the repository found the desktop encoder
  stealing GPU when the headset shows the desktop
  (`docs/BENCHMARK-GPU-ENGINE-ACTIVITY.md`). Nothing in the repo lists
  NVIDIA Control Panel settings; low-latency mode and power management
  affect latency and clocks, not compositor work.
- **The game's own window.** The mod forces windowed mode, so the desktop
  compositor also presents the game's 1280x768 window each desktop refresh;
  small at that size, and the capture proxy needs the swapchain either way.

## What is not available

VDXR 1.0.10 reports `XR_FB_space_warp` and `XR_EXT_frame_synthesis` as
unavailable (`docs/handoffs/2026-09-03-development-session.md:285-295`);
its developer page lists no foveation extension and no
`XR_FB_composition_layer_settings`; depth is accepted and ignored. So the
viewer cannot hand the runtime motion vectors, foveated layers or a cheaper
composition mode: the viewer's side is already as lean as this runtime
allows (two layers, sRGB 8-bit, recommended size, no upscaling, no depth).

## The options, ranked by expected return on the PC's GPU

1. **Refresh 90 Hz** in the Quest client: a quarter off both the
   composition and the encode per second, with the game's fresh pairs
   unchanged. Not yet measured; one Hub launch with the day's instruments
   (the recipe in the profile doc) says how much of the 23.5 ms comes back.
2. **Hardware GPU scheduling on**, then retry the two priority flags. The
   only untested arbitration change; needs a reboot per arm.
3. **Confirm the headset's own state** during measurements: a dozing headset
   idles the encoder and inflates the result by about a fifth; the runner's
   midpoint sample now records it.
4. **Boost Game Priority** in the streamer: cheap to try, CPU-side only,
   may cut both ways.
5. Everything else the guides list (bitrate, buffering, sharpening, SSW) is
   either measured as marginal or runs on the headset, not the PC.

What is already at its cheapest and should not be touched: the runtime's
registry (absent, all defaults), the codec (H.264+), the resolution step
(2112x2304), the runtime (VDXR), the viewer's layers and formats.

## Sources

- VDXR source, `mbucchia/VirtualDesktop-OpenXR`: `runtime.h` (`RegPrefix`,
  member defaults), `session.cpp` (`sharpen`, `mirror_window`,
  `quirk_use_depth`, `quirk_disable_async_submission`,
  `quirk_disable_running_start`, `visibility_mask_scale`), `system.cpp`
  (`upscaling`, `RenderResolution`), `precompositor.cpp` (EASU and CAS
  passes and their conditions), `frame.cpp` (`xrWaitFrame` on
  `ovr_WaitToBeginFrame`, asynchronous `ovr_EndFrame`, running start,
  `AppGpuTime`), `swapchain.cpp` (fast and slow paths), `mirror_window.cpp`;
  wiki Developers page (supported extensions).
- [VR Discord community: Virtual Desktop guide](https://vrdiscord.com/guides/quest-wireless/virtualdesktop.html)
- [Aboleth's Deep Dives: More on EZ + VD setup](https://abolethvr.substack.com/p/more-on-ez-vd-setup)
- [VirtualDesktop-OpenXR wiki](https://github.com/mbucchia/VirtualDesktop-OpenXR/wiki) and
  [Developers](https://github.com/mbucchia/VirtualDesktop-OpenXR/wiki/Developers)
- [Hardware-Accelerated GPU Scheduling: On or Off? (2026)](https://techfuelhq.com/gaming/hardware-accelerated-gpu-scheduling-on-or-off-2026/)
- Repository: `docs/handoffs/2026-09-11-end-of-day.md`,
  `docs/FRAME-PRODUCTION-2026-09-11.md`, `docs/PHYSICAL-STREAMING-GAP-2026-09-11.md`,
  `docs/VDXR-SUBMISSION-SLOWDOWN.md`, `docs/XR-FRAME-STAGE-TIMING.md`,
  `docs/BENCHMARK-GPU-ENGINE-ACTIVITY.md`, `docs/LUA-FRAME-PROFILE-2026-09-16.md`.
