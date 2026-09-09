# Focused diagnostic trials — staged, not deployed

Three independent payloads are staged under ignored `artifacts/focused-trials`.
Each `trial-plan.json` contains relative source/destination paths and exact
candidate/baseline hash preconditions. They use transaction support from
`b515e72` (PR #139). No payload is an installer or a complete runtime.
The source revision names the reviewed candidate; binary provenance is not
embedded. Native build evidence remains in the focused source handoff.

| Trial | Reviewed source | Payload | Installation destinations |
| --- | --- | --- | --- |
| `native-ui-a4ec84c` | `a4ec84c`, PR #133 | One native DLL | Existing DLL in `binaries` and in the mod's `bin` directory |
| `marker-metrics-8178c5f` | `8178c5f`, PR #138 | Main Lua and measurement module | Existing main Lua plus new marker module |
| `communication-29b30bd` | `29b30bd`, PR #158 | Fifteen Lua files | Eight existing files plus seven new modules |

The native trial supports owned UI readback while the optional DLSS UI tag
remains disabled. The marker trial measures inputs to both eyes' draws without
changing sizing. Keep them separate during initial trials so their effects can
be attributed. Preserve accepted Lua `3341afb`, native `23345e5`, viewer
`6688841`, saved bindings and display settings outside the chosen payload.
The communication candidate includes wheel and push-to-talk ownership guards;
both new physical bindings remain unassigned. It and the marker candidate both
replace the main Lua file, so their staged payloads cannot be stacked blindly.

The native candidate hash is
`3FD7B9100009002F851EB17EBA559EACFB3F378E50F11CBEF35F3F1C49552446`.
Both installed native copies still hash to
`FCCDD0DE699F9D50D2BD316792829D4EE5700843D925D194BE4DF1F3EEB02369`.
The marker plan requires the installed main Lua's observed baseline hash and
requires the new module to be absent. A changed baseline needs review rather
than silently replacing these preconditions with newly observed hashes.

## Rehearsal evidence

The native and marker plans were applied to separate temporary copies of the relevant installed
files, then restored through `Restore-DarktideDeploymentTransaction`. Every
candidate destination matched its payload hash after installation. Both native
locations and the Lua entry point returned to their exact original hashes;
the newly introduced module was removed. An unrelated sentinel remained intact.

Receipt (ignored):
`artifacts/unattended/trial-rehearsal-977a0c377b844396924144d7bf4ad960/rehearsal.json`.
These are filesystem rehearsals, not live deployment or render acceptance.
The actual game installation was subsequently checked against all four plan
preconditions and remains unchanged. The accepted viewer hash is unchanged.

The communication plan was separately rehearsed against a copy of the complete
installed Lua directory and descriptor. All eight replaced files matched accepted
`3341afb` after line-ending normalization before staging; all seven additions
were absent. Installation compiled 57 chunks. Rollback restored all 51 original
fixture files by hash, removed all seven additions, and compiled 50 chunks.
The fixture includes an unrelated sentinel and the installation's existing extra
`darktidevr_gun_alignment.lua`, which the plan preserves. The focused source gate
compiles 56 chunks; the extra installed module explains the different count.
All fifteen real-installation preconditions remained unchanged after rehearsal.
Recovery used the strengthened hash checks from `0b99afd` (PR #141).

Initial communication receipt for `2dded96` (ignored):
`artifacts/unattended/communication-trial-rehearsal-dd7302238e3b408786e832624590d39d/rehearsal.json`.
Its focused source passes 64/64 Lua checks in 1.048 seconds, plus cached stock
wheel/chat contracts with communication and microphone effects mocked.

The preceding communication payload is `96292b4` (PR #153). It adds the retiring
inventory/tag/tactical service guard, changing exactly one of the fifteen payload
files. All destination hash/absence preconditions remain the original accepted
baseline values. The previous `communication-2dded96` staging is retained as
historical evidence, not the current trial candidate.

The refreshed copied-install transaction and rollback both pass: 57 candidate
chunks compile, 50 restored chunks compile, all 51 original fixture hashes match,
and all seven new modules are removed. These gates compile the copied descriptor
along with its copied Lua files. The fifteen actual installed preconditions are
still unchanged. Its focused source passes 64/64 Lua checks in 1.203 seconds.
Its receipt (ignored):
`artifacts/unattended/communication-trial-refresh-e4bd9a80ff834baca290663659d0d007/rehearsal.json`.

The current payload is `communication-29b30bd` (PR #158), adding same-view menu
null-service recovery. Exactly one payload file changes from `96292b4`; all
accepted destination preconditions are unchanged. The focused suite passes
64/64 Lua checks in 0.895 seconds and its own package gate compiles 56 chunks.

Its fresh copied-install rehearsal passes with 57 chunks installed and 50 after
rollback, using the corrected source gate on each copied package's descriptor.
All 51 original fixture files return to their original hashes and all seven new
modules are removed. Actual installed preconditions remain unchanged. Earlier
communication payload directories are historical versions, not additional trials.
Latest receipt (ignored):
`artifacts/unattended/menu-trial-refresh-32f98d42f6524f51a7aab8e978c43f0d/rehearsal.json`.

## Live trial boundary

Fresh default Ready is required before a live deployment/session. The latest
read-only inventory found the Quest asleep and Darktide closed, so no trial was
started. Compile installed Lua, preserve proximity cleanup and use the accepted
launcher with deployment sync skipped. Never use the accumulated main-tree
runtime sync for these focused trials.

Resolve plan source paths under the selected staging directory and destination
paths under the verified game root, then pass their hash preconditions to the
transaction helper. Both native destinations belong to one transaction. Retain
its backup/manifest for rollback; for Lua, rollback must also remove the new
modules. The native diagnostic flags are separate from this file payload and
must retain their own original-state record before any trial.

Require fresh stereo initialization and advancing `shared_ready`. For native
readback, require `ui_alpha=0`, `ui_capture=1`, owned positive-pose input records,
matching NGX output metadata and verified checksums. For marker measurement,
use the bounded `/dtvr_marker_metrics` command on the relevant visible popup.
Input equality and checksums do not establish a visual fix. Record the user's
worn result in both eyes, during motion and at screen edges. Stop the observer,
close the game, restore the transaction and original flags, then verify hashes
and restore normal proximity automation.
