# Billboard investigation, 8 September

The launch/install/package checks are complete offline. Remaining feature and
worn acceptance checks remain open. The current interpretation of the user's
ordering is to investigate billboarding next; clarification of whether
"pre-launch" also includes unfinished features was requested.

## Shader ownership evidence

The production replacement targets VS `42e436fb1ef1b392` with PS
`6020f2548f29fd47`. Its raw-particle layout uses `c_per_object:384` and has an
existing world-Z cylindrical correction. Preserve this proven target and its
production shader guard.

The retained 31 August census also contains VS `f1f1510767c58664` with PS
`e977841939553e76`, a different interface using `c_billboard:128`. Inspection of
the original captured `.bin` with DXC shows that its world corner position is
the input center plus `view[0].xyz * (TEXCOORD7.x * POSITION1.x / 2)` plus
`view[2].xyz * (TEXCOORD7.y * POSITION1.y / 2)`, before its view-projection
transform. This proves a view-basis quad construction in that shader; it does
not identify it as the character-select smoke. The 398 census rows are PSO
observations, not draw frequency or visible pixel coverage.

Do not apply one replacement to all `c_billboard` interfaces. The census also
contains tangent/ribbon families with different geometry inputs.

The 1 September character-select comparison's scene-specific pair
`3744e7b93c3085b0/80a9194fe7024bdc` was a pretransformed mesh. Its exact magenta
probe applied but did not color the smoke. It is ruled out by that observation;
do not repeat it as a newly discovered candidate. The remaining smoke owner is
unconfirmed. A specific observation was requested about character-select versus
gameplay effects; no new synthetic visual experiment has been run.

## Capture correction

The identity writer opened its append file with `FILE_SHARE_READ` on every
callback and silently returned on an open failure. Creation callbacks can log
under the PSO metadata lock, but first-bind callbacks release that lock before
logging. Concurrent first-bind/creation writers could therefore reject each
other's open requests and lose records.

The candidate serializes the entire open/write/close interval with a dedicated
append lock, verifies the write length and close result, and emits one debugger
message on a failed append. It also rejects a truncated formatted line. The
lock does not call back into PSO metadata handling. This is a diagnostic
correctness fix, not proof that this race caused any specific missing capture.
The existing production restriction on broad first-bind diagnostics is intact.

The regression writes 1,024 uniquely identified records from eight concurrent
threads and checks the complete record set. It also verifies incompatible
external access reports failure and that a later append recovers. Native build
and test results are recorded in the workday handoff.

Use launcher-scoped identity slices for the next capture. The historical temp
file is append-only across runs and has no process/run identity; neither it nor
the shader dump directory alone establishes scene ownership. A bounded focused
capture and restoration have now completed, as recorded below.

## Cached pipeline probe correction

`ID3D12PipelineLibrary1::LoadPipeline` passed only the vertex-replacement flag
to stream inspection. A pixel-only candidate was copied into a temporary stream
but that stream was never submitted. The candidate now handles pixel selection,
direct creation, success/rejection counters and fallback the same way as the
existing graphics and stream-creation paths. A failed replacement returns to the
original library entry and original descriptor.

An isolated Windows/D3D12 regression creates a real stock pipeline and library
entry, then loads the native capture module from its own artifact directory.
It enables a generated, interface-matching pixel probe and calls the actual
hooked `LoadPipeline`. Before the correction, both application and fallback
cases fail with `attempts=1 applied=0 validation=0 creation_rejected=0`.
Afterward both pass: the valid probe also works with a never-stored cache name;
a probe requiring an absent root binding is rejected by D3D12 and the cached
stock pipeline loads successfully. This test neither starts Darktide nor submits
an XR scene, and does not establish visual ownership of the smoke.

Release native/test builds and all **144 CTests pass in 31.15 s**. Evidence is
`artifacts/unattended/pipeline-probe-before-20260908.log`,
`pipeline-probe-after-20260908.log`, and `pipeline-probe-144-20260908.log`.
The cached-probe candidate was included in the bounded capture below, then
restored to the accepted native binary.

## Fresh eager character-select capture

Ready passed 600/600 submitted frames with zero unrendered frames. The focused
PR #32 candidate was deployed through a seven-file backup transaction, with
diagnostic and shader-dump flags armed before startup. Native bootstrap and
Lua both requested diagnostics/dump/substitution, and initialization succeeded.
The existing character-select presentation is a flat panel; no gameplay
shared-stereo or worn visual acceptance is inferred from this run.

The final run-scoped slice is
`artifacts/unattended/billboard-scene-identities/character-select-20260908-113255.tsv`.
It contains 237 first-bind rows and one target-load-stream row: 201 classified
rows, 142 unique VS/PS pairs and 131 unique VS files, all available for reflection.
Eleven billboard rows cover ten shader families. The production raw-particle
target and the view-basis `f1f1510767c58664` family both occur. This establishes
their presence in the run, not ownership of visible smoke or draw frequency.
Full reflection output is `billboard-character-select-final-families-20260908.csv`
under `artifacts/unattended`.

The game exited with code 0. A subsequent Ready check passed, the complete
transaction was restored with original hashes, and temporary flags were removed.
The accepted melee-preview Psykhanium session now has fresh nonzero shared-eye
delivery. No color probe or synthetic tracking experiment was performed.
