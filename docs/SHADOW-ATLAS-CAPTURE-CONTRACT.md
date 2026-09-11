# Next shadow-atlas diagnostic

11 September 2026. The [cascade observer](CASCADE-STAGE-OBSERVER.md) establishes
repeated CPU execution with matching selected inputs. It cannot establish GPU
cost or whether atlas storage can be retained between stereo renders. This is
an implementation contract for the next diagnostic, not evidence of safe reuse.

## Existing capture gaps

Source audit of `src/producer/native_capture.cpp` found:

- `CreateDepthStencilView` metadata is installed only with diagnostic render
  hooks. Normal menu/RTV tracking does not populate depth-resource identities.
- Focused `ResourceBarrier` and enhanced `Barrier` tracing counts barriers but
  does not retain their complete ordering or atlas identities. The separate
  cluster trace filters to its linked-list buffer, not the shadow atlas.
- `BeginRenderPass` records target handles and flags, but omits beginning and
  ending depth/stencil access operations. A clear can therefore be missed by
  looking only for `ClearDepthStencilView`.
- Successful command-list Reset establishes a new recording; failed Reset must
  preserve the previous recording. A reused list pointer is not a unique batch.
- Placed-resource observation has heap identity and offset, but raw resource
  addresses alone cannot prove lifetime, allocation extent or non-overlap.
- Named final-eye output identity exists at queue submission. A CPU Present tag
  or cascade-call order alone is insufficient to associate worker lists with an eye.

Re-enabling the broad focused trace would change descriptor bookkeeping and
produce large per-draw logs without closing these gaps. Keep it disabled for
performance controls.

## Bounded capture requirements

Identify the actual sun atlas and companion color resource through an established
engine resource identity or debug name, then validate their description and
observed quadrant sequence. Size or depth format alone must not identify a sun
atlas: local and static shadow resources also exist. Start metadata observation
before allocation; an already-live untracked allocation remains unknown.

For a short settled capture, retain resource identities with allocation epochs,
heap ranges where applicable, descriptor copies for only the required heap
types, command-list recording generations, ordered submissions and queue
synchronization. Capture target binds, render-pass access operations, explicit
clears, atlas writes and transitions, including legacy aliasing barriers and
enhanced discard/global operations. Include potentially overlapping allocations
and global operations even when they do not name the atlas directly.

Record enough execution coverage to detect unsupported writes or missing list
history. Bundles, indirect work, copies, resolves, resource recreation and
unobserved queues must produce an explicit unknown result unless covered.
Recording order on different threads is not execution order on the GPU.

Use a fixed-capacity buffer, explicit admission/overflow status and a completion
record. Write after capture rather than per draw. Preserve original API results,
arguments and error state; do not alter resources or skip work. Default-off
installation must leave the clean-launch descriptor fast path intact.

First establish identity and ordering. GPU timestamps can then bracket confirmed
atlas work on its executing queue, with query lifetime, completion and frequency
handled explicitly. Do not infer GPU duration from the 0.21 ms CPU cascade call
or sum overlapping queue durations into an alleged frame-time saving.

## Acceptance before a reuse candidate

Require two complete stereo renders with stable pose/world generation, matching
complete cascade inputs and exported transforms, and uninterrupted atlas
ownership through the second eye's reads. Reject incomplete captures, resource
identity reuse, overflow and uncovered writes. Preserve per-eye screen-space
shadow masks, which consume each eye's depth. A later candidate still needs
matched performance controls and worn visual acceptance.
