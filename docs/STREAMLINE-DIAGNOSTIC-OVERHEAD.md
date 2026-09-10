# Stop preparing exhausted Streamline diagnostics

Continuous FG keeps the constants and resource-tag hooks active because those
hooks also retain the eye-associated input resources. The bounded log already
stops writing after its budget, but previously each subsequent call still
prepared diagnostic arguments, queried resource descriptions and incremented
shared log counters.

The change checks the remaining budget before preparing constants and tag
records. Once exhausted, it skips log-only timestamps, matrix arguments,
resource descriptions and QueryInterface calls for tags that are not retained
FG inputs. It preserves input resource ownership, state, frame and pose
association, constants history and the API's original return value. Writer
admission still uses an atomic increment below the limit to enforce the bound
when callers race; exhausted callers only read. Terminal submission records
retain their existing exemption from the total budget.

Windows x64 Release builds pass in the main checkout and focused baseline.
Seven related main-checkout tests pass. The focused checkout initially lacked
three test executables; after building those targets, all five relevant tests
pass. These cover Streamline readiness, continuous observation, resource
lifetime, submission and ABI behavior; they do not quantify performance gains.

The focused candidate is `37e2cde`, based on clear/FG baseline `0214f7d`.
Its DLL SHA-256 is
`fb244186961a176179a5172b6fb0c5be752346d1a242876c4e0c3c9a44b3f58f`.
The prior DLL is preserved locally as
`artifacts/native-baselines/B052535-diagnostic-baseline.dll` for controls.
Mission trials retain the same 120 Hz clock, resolution, cap and SoloPlay
settings. Throughput or power differences require comparison evidence; simply
skipping work does not establish a measurable frame-rate gain.
