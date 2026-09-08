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
the shader dump directory alone establishes scene ownership. The current
focused melee-preview session remains running with its accepted native binary.
This candidate is not deployed.
