# Native original-frame ring candidate

The [descriptor-copy candidate](DESCRIPTOR-COPY-DEMAND-2026-09-11.md) raises game
Present rate from about 75 to 93 per second, but the single-slot native handoff
publishes only about 53 stereo pairs. A 72 FPS cap restores roughly 72 delivered
pairs. This candidate gives native stereo its own three-slot original-frame ring.

It uses the existing original-frame texture names, shared fences and metadata
protocol already read by the viewer. It does not enable frame generation. Enable
only for an isolated native trial with `darktidevr_native_original_ring.flag`
beside the loaded DLL, containing `[probe]` and `enabled=1`. Configure it before
launch and remove/restore the flag after the run. Persistent FG launches do not
construct this publisher. It remains absent from normal launches.

The publisher copies each identified eye final into its half of a packed slot.
It publishes only after matching left/right pose and gameplay generation tags,
with a ready-fence signal ordered after both GPU copies. Reuse requires consumer
acknowledgement and completion of the slot's command allocators. Partial pairs
never advance metadata. Queue changes, incompatible dimensions/formats and
poisoned fences are rejected. Sources stay owned until their copy completes.

The legacy mailbox remains populated for dimensions, menu transitions and fallback;
the viewer acknowledges unused legacy pairs without reading their pixels after
the ring becomes active. The prototype therefore adds copies rather than removing
legacy transport immediately. At 2496x2688, its three producer textures occupy
about 154 MiB, with approximately another 154 MiB for the viewer's queued originals.
Allocator/driver overhead is additional. A resize or queue change falls back to
legacy delivery rather than recreating the live ring; restart the trial to reset.

Root commits `3507a93`, `41dade8`; focused commit `10550a4` on descriptor candidate `87ed0d0`.
Focused DLL SHA-256:
`D4AB131A16C30143AEDFC4296CD5846E60C9CB6ED4C32BCC320C8A0578BE10AE`.
Build location: `build/focused-descriptor-demand`. The previous descriptor-only
DLL is preserved at `artifacts/native-baselines/3AFEB3AF-descriptor-demand.dll`.

Windows x64 Release builds pass. `native_original_ring` passes on WARP using
actual shared textures and pixel readback: both eyes retain their expected colour,
recycling slot zero preserves an unconsumed slot, mismatched poses/generations
cannot publish, and a held GPU fence prevents allocator reuse. It also checks
partial-pair recovery, queue rejection and poisoned acknowledgements. A second
case verifies typeless RGBA8 input with typed shared output. SRGB RGBA8 retains
its format; incompatible format families remain rejected. The first 32 capture
outcomes are logged under `%TEMP%/darktidevr-native-original-ring-<pid>.log`.
`native_capture_hooks` passes with the flag absent. Commands:

```
cmake --build build/xr-window-capture-demand --config Release --target darktidevr_native_capture darktidevr-native-original-ring-tests
ctest --test-dir build/xr-window-capture-demand -C Release -R '^(native_original_ring|native_capture_hooks)$' --output-on-failure
```

The first trial (`ring-a`, original SHA `083B5BC0...`) did not attach an original
ring; it continued through the legacy mailbox. The initial publisher accepted
only typed RGBA8, while game resources also use typeless RGBA8. The expanded
format handling and bounded startup outcomes are under test in `ring-b`.
Offline pixel tests do not
establish world-space HUD appearance or worn acceptance. Do not promote this
publisher until live transport results and required visual checks are recorded.
