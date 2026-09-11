# Removing duplicate native mailbox copies

11 September 2026 source investigation. The successful native ring still copies
both eye finals through the legacy mailbox. The viewer acknowledges those
mailbox images without copying their pixels while it presents queued originals.
Removing duplicate transport remains a useful target, but a direct skip would
also stop metadata that the viewer currently requires.

## Dependencies found

`execute_command_lists_hook` publishes the ring independently, then invokes
`capture_eye_from_resource`. Only a completed legacy pair advancing `ready_value`
publishes `SharedRenderedPair`: matching eye pose sequences, gameplay generation,
vertical FOV and aspect for that pair. Ring slot metadata carries poses and
generation, but not the full legacy rendered-pair record.

The viewer opens ring resources against `shared_eye_width` and
`shared_eye_height`, learned from the shared-eye connection. Detaching that
connection also resets original/generated surfaces and queued originals.
Menu-to-world projection settling still compares the committed generation with
the rendered generation read through a matching legacy ready value.

The viewer's legacy advancement clock also supplies the 500 ms freshness
threshold, wait deadline and five-second cached-pair grace. Ring images have
their own 250 ms age gate and ready/consumed fences, but these do not replace
every legacy dependency. An original-ring object existing is not sufficient:
the ring can fail, become busy, reject changed dimensions/queue identity or
carry the outgoing gameplay generation.

## Required implementation boundary

Separate authoritative metadata from pixel ownership before stopping copies.
An independently readable, versioned record needs ring transport identity,
dimensions/format, completed pair sequence, matching pose/generation and the
projection information required by the consumer. Validate it against the same
ready fence and actual ring slot, never against an unrelated legacy sequence.

Teach the viewer to attach and maintain ring delivery, projection settling and
freshness from this record. Preserve legacy behavior for older producers/viewers,
startup, menus and an unavailable ring. Producer suppression requires explicit
consumer capability/ownership evidence; a generic consumed acknowledgement can
also mean discard and does not prove that a viewer supports metadata-only mode.

Fallback must resume real legacy pixel copies and publish their own matching
metadata before selecting them. Never advance legacy readiness over unchanged
pixels to keep a liveness counter moving. Keep resize, device loss, interrupted
pairs and generation changes explicit. A shared projection generation cannot
be silently treated as proof that all projection parameters stayed fixed.

Tests must cover old/new endpoint combinations, startup attach, menu resume,
ring timeout, resize/rejection, fence failure and stale metadata, alongside the
existing GPU pixel/slot ownership tests. Measure an isolated producer/viewer
pair against the current ring baseline. The earlier direct-viewer-copy test
saved one intermediate copy but did not establish a throughput gain; duplicate
copy removal likewise needs measurement rather than a bandwidth-based claim.

No suppression or protocol change was deployed by this investigation. Physical
and worn acceptance of the existing ring remain pending.
