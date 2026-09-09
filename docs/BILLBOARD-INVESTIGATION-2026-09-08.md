# Billboard investigation, 8 September

## Guarded diagnostic samples, 10 September

Both CBV loggers previously formatted floats directly from borrowed mapped or
staging memory. They now copy only their bounded sample (at most 33 or 128 floats)
into local storage using the existing SEH-guarded copy routine, then format that
copy. A failed copy is discarded; no partial sample is written. Temporary maps
still unmap on the failure path, and failed attempts consume the existing sample
reservation rather than introducing retries or changing the logging budget.

The existing guarded-copy implementation moved unchanged into a small shared
header so its actual code can be exercised independently. A Windows memory test
uses owned pages with PAGE_NOACCESS protection: exact byte copies at 0/132/512
bytes, an exact page edge, wholly inaccessible and cross-page sources, and
recovery to a readable source all pass. Failed destinations may be partially
modified and must be discarded. This does not guarantee pointer lifetime,
freshness or a coherent sample during concurrent writes.

Native Release and test executables build. `guarded_diagnostic_copy` and
`native_capture_hooks` pass 2/2 in 0.44 seconds. Logger cleanup/selection is
source-reviewed; the fixture does not drive either shader-specific logging path.
No live capture, shader change or deployment. Receipts:
`artifacts/unattended/guarded-billboard-sample-{build,tests}-20260910.log`.

## Target-CBV staging selection follow-up, 10 September

The separate `log_target_billboard_cbv` reader also selected any non-null staging
pointer without checking its recorded extent. It now uses the same complete-range
predicate as the general reader. Its later byte pointer comes from the selected
mapping, so a short staging region cannot override the persistent/temporary Map
fallback. Staging remains preferred when it contains the request; sample limits,
formatting and temporary-map cleanup are unchanged.

Native Release builds; existing staging-boundary and native-hook checks pass
2/2 in 2.44 seconds. The target logger's fallback selection is reviewed in source,
not directly driven by these fixtures, and no live diagnostic was run. Receipts:
`artifacts/unattended/target-cbv-staging-{build,tests}-20260910.log`.
No installed/staged files or shader behaviour changed. Pointer lifetime and
concurrent mapping validity remain separate from these extent checks.

## Diagnostic copy address correction, 10 September

The recorded-copy lookup used `delta + byte_count <= copy.bytes`, which can
wrap: a delta of `UINT64_MAX - 3` plus eight bytes becomes four and can falsely
match a small copy. The source-address calculation then added the GPU base,
source offset and destination delta without checking representability.

The source candidate uses subtraction-based containment and checked source
translation, including a nonzero GPU base and representable last requested
byte. Invalid copies cannot redirect a diagnostic read into another address.
Newest-copy selection, locking and valid source preference are unchanged.
This affects cluster diagnostic constant reads, not the actual game buffer copy
or lighting patch operation. It does not establish that overflow occurred live.

The actual helpers pass 25,600 ordinary range comparisons against the prior
predicate, valid-address equality and explicit underflow/overflow/end-byte cases.
Native Release and both affected executables build; buffer lookup/native hooks
pass 2/2 in 2.41 seconds. The first build caught a shadowed fixture variable,
corrected before the successful final build. No game, headset or GPU submission
was used to validate these address calculations. No deployed/staged bytes change.
Receipts: `artifacts/unattended/copy-address-bounds-final-build-20260910.log`
and `copy-address-bounds-tests-20260910.log`. Build/test commands are the same
three native targets and two CTests listed in the staging correction below.

## Staging bounds correction, 10 September

The diagnostic CBV reader selected staging memory when the requested range fit
the GPU resource, ignoring the smaller recorded staging extent. For example,
offset 60 plus 8 bytes fits a 4,096-byte GPU buffer but exceeds a 64-byte staging
region. Its later float logging reads that selected memory directly.

The source candidate now requires the entire range to fit `staging_size`, using
subtraction to avoid unsigned wrap. If staging is insufficient it retains the
existing persistent-mapping or Map fallback. The general tracked-buffer copy
uses the same predicate while preserving its original mapped-first preference.
This does not establish pointer lifetime, freshness, allocation ownership or the
visible cause of the smoke problem; it closes the extent-selection error.

The buffer fixture covers missing pointers, exact edges, an oversized read,
zero-length endpoints and overflowing ranges. Native Release and affected
executables build; `buffer_address_lookup` and `native_capture_hooks` pass 2/2
in 2.43 seconds. These checks do not invoke the live version-gated upload target
or establish scene ownership. No shader, installed DLL or staged payload changes.
Receipts: `artifacts/unattended/billboard-staging-bounds-{build,tests}-20260910.log`.

Commands: build `darktidevr_native_capture`,
`darktidevr-buffer-address-lookup-tests` and `darktidevr-native-capture-tests`
in `build/xr-frame-stage-timing` Release, then run CTest with
`-R '^(buffer_address_lookup|native_capture_hooks)$' --output-on-failure`.

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
