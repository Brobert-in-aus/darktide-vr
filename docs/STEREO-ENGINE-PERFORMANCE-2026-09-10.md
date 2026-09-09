# Stereo, DLSS and engine performance

The user's 10 September priorities are more efficient stereo, better DLSS
implementation, and investigating engine internals for overlooked optimisations.
These take precedence over further diagnostic micro-optimisations. Continue
development between checkpoints; no further basic-gameplay verification.

## Where the current implementation spends work

`render_eye_from_prepared_frame` already bypasses the second Lua shading setup,
but calls `Application.render_world` again. Earlier corrected-cull observations
put pair-wrapper CPU average/p95 at 0.324/0.582 ms while summed eye GPU work was
33.773 ms. Those historical measurements are not today's settings benchmark.
Keep the tracked shared cull camera: removing geometry was responsible for an
earlier apparent speedup and broke parity.

The 1 September direct-queue trace was reprocessed using the current analyzer:
24 complete batches, 6.959 ms total, adjacent render segments 2.947/4.012 ms,
144 shared PSOs out of 154. Only 15 of 47 lists match generation-aware PSO
records. The old trace omits work counters; zeros rendered by the current report
must not be interpreted as no draws or dispatches. Shared shader identity does
not establish reusable visibility, constants, outputs, or temporal history.

Saved 6 September input-copy timing rows are approximately 0.12–0.15 ms per eye
plus 0.20–0.28 ms for packing/publication in the initial inspected rows. Saved
FG evaluation samples in a separate file are roughly 2 ms per eye. These are
unmatched historical samples, not an additive frame budget or controlled trial.
Prioritise engine preparation and reconstruction before redesigning copies.

The continuous input path copies depth, motion, HUDless colour and final colour
into independently retired owners, packs final colour into the real backbuffer,
then copies that packed image into the original-frame XR ring. Eliminating a
copy requires preserving both Streamline input lifetime and XR consumer lifetime;
aliasing the current ring textures without a retirement redesign is insufficient.

## Installed engine map

Read-only inspection found useful profiling labels in the installed x64 engine.
SHA-256: `6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3`.
The version string remains `1.3.770.210`, but its hash differs from the historical
phase-0 map. Never transfer addresses using version text alone.

| Profiling label | Containing unwind range RVA |
| --- | --- |
| `RI::render_world` | `2d9a6d–2da3aa` |
| `render_culled_scene`, `render_kernel_culled` | `37b240–37c599` |
| Sphere cull kickoff/wait; light culling and sort | `384c30–389198` |
| `prepare render shadows` | `41d6ce–41d93c` |
| `prepare rendering work` | `41d951–41e3df` |
| Static/non-static sphere culling | `451bab–457bdc` |

These are string-reference locations within PE unwind ranges, **not validated
function entries or hook targets**. Some ranges start inside a chained function.
They establish where to inspect dependencies and job scheduling, not costs or
safe work suppression. No game was launched, attached to, patched or deployed.

The reusable `tools/renderer_probe/map-engine-render-scopes.py` requires an exact
input hash and emits label references, containing ranges, and direct call targets.
It uses pefile 2024.8.26 and Capstone 5.0.9, installed locally under ignored
`build/dependencies/engine-inspection`. Example:

```powershell
$env:PYTHONPATH = (Resolve-Path build/dependencies/engine-inspection).Path
python tools/renderer_probe/map-engine-render-scopes.py PATH_TO_DARKTIDE_EXE --expected-sha256 6fce8db87a77a412b22ef9f33f74fa16ef85126cc0fbb24187d78b85fc7a19d3 --output artifacts/unattended/engine-render-scopes-20260910.json
```

The installed binary yields 31 references in 18 unwind ranges; Python compilation
passes. Raw disassembly, binary content and local reports remain ignored.

### Following the Lua render entry

The `render_world` registration sequence points to candidate Lua C entry RVA
`51f660`. Manual inspection shows four argument checks, lookup of the
`shadow_cull_camera` viewport key, copying a camera matrix into world-associated
storage, then calls to `2d5a40` and `2d5740`. The latter references the
`RenderInterface::render_world` label and queues a 48-byte type-8 command.

`2d5a40` references `RenderInterface::update_world`. It conditionally bypasses
its preparation/queue path when state counters and a frame comparison pass
(`2d5b0c–2d5b6a`); otherwise it can queue type 9. This is evidence of an existing
reuse guard, not proof that both eyes execute or bypass preparation. Do not
suppress the second update call based only on the two Lua render invocations.
The render command and world-update command are distinct investigation points.

The shadow-preparation range depends on registers and stack state established
outside its unwind fragment. It is not independently callable. Any subsequent
timing seam must resolve its parent control flow and observe job completion;
blindly hooking the beginning of that fragment would be incorrect.

### Resolved unwind ownership

The schema-2 mapper follows aligned x64 `UNW_FLAG_CHAININFO` records to their
primary range, groups all owned fragments, and reports direct calls and callers.
It rejects truncated, cyclic and conflicting handler/chained records. Five
isolated decoder checks pass, including odd unwind-code alignment and multiple
chain levels. Mapping the installed executable still finds 31 references in 18
label-bearing ranges, now grouped into 12 primary owners.

| Work | Primary RVA | Owned fragments |
| --- | --- | --- |
| Render command dispatch, including `RI::render_world` | `2d9a40` | 4 |
| Render/cull preparation | `384c30` | 1 |
| Cascaded culling, shadow and rendering preparation | `419910` | 14 |
| Shadow culling and atlas-related waits | `41f5e0` | 9 |
| Static/non-static geometry culling | `451940` | 5 |

In particular, both `41d6ce` and `41d951` chain through `419946` and `41993c`
to `419910`. Their shared parent spans considerably more work than either
label. Whole-function sampling must not be reported as shadow-only time.
One direct caller of `419910` is at `418156`, owned by `417f50`; one direct
caller of `41f5e0` is at `374858`, owned by `3746c0`. Indirect paths remain open.

Manual inspection of the dispatch jump table at `2da96c` maps command 8 to
`2d9aa0` and command 9 to `2d9a89`. The former builds a render context and calls
`384c30` at `2d9bfe`; the latter calls `2d5be0`. This connects the separate queue
packets to distinct dispatch paths. These are static, hash-scoped observations,
not measured execution frequency or a validated hook ABI.

Local evidence: `engine-render-ownership-20260910.json`,
`engine-preparation-functions-20260910.txt`, and
`engine-unwind-tests-20260910.log` under `artifacts/unattended`.
The [bounded CPU capture](ENGINE-CPU-SAMPLING.md) is prepared, but its live trial
was deferred after the new Ready checks failed. No engine patch was deployed.

## Next development targets

1. Follow the preparation/culling call graph and classify mutable world updates,
   per-eye visibility and reusable scene preparation before selecting a bounded
   timing seam. Avoid repeating or suppressing animation/job side effects.
2. Establish SR eye/pose ownership and full motion conventions independently of
   FG. The [10 September SR capture](handoffs/2026-09-10-sr-input-capture.md)
   contains complete resource/scalar observations for 64 evaluations: two
   alternating feature lifetimes, matched pair jitter and no observed resets.
   Call-order pairing alone does not establish correct per-eye history.
3. Keep FG's two eye evaluations distinct until independent history and viewport
   requirements are accounted for. A single wide image does not establish that
   one evaluation can replace two without cross-eye temporal contamination.
4. Retain the surrounding-HUD blur investigation and user-worn visual acceptance.
   Offline mapping does not resolve that symptom.
