# Action-first controller bindings

Final status, 8 September night: deployed changes are accepted for the checks
performed in tonight's session (user: "All checks passed"). Subsequent corrections
and the final mixed deployment are recorded in the
[night handoff](handoffs/2026-09-08-night.md). Earlier candidate, restart and
pending-acceptance statements below describe the implementation chronology;
physical melee, remote-server and broader mission acceptance remain separate.

Each individual gameplay action now labels the left side of a dropdown; the
dropdown contains controller inputs and Unbound. Hub rows additionally offer
Same as combat. Combined legacy actions appear as separate rows sharing the
same control (interact/reload on X, jump/dodge on A).

The widget builder migrates missing action settings from saved physical-control
settings, preserving duplicate aliases and hub overrides. A saved multi-control
assignment has a readable combined option rather than silently losing an alias.
Choosing a single input replaces that action's assignment; other actions sharing
the input remain unchanged. Factory reset still uses the original layout.
Legacy settings remain intact for fallback and rollback. Existing action settings
are not migrated again when reopening the menu.

Runtime mapping keeps the existing neutral-before-rearm behavior, generation and
tracking-loss cancellation, support-grip ownership, spectator inputs and prompt
resolution. The action-to-control result is cached by settings revision/context.
Smooth turning continues to reserve horizontal right-stick movement.

Validation: controller bindings, controller prompts, spectator input, two-hand
pose and support tests pass (5/5, 0.15 s). Migration tests cover combined actions,
multiple aliases, both contexts, live remap cancellation, shared controls,
explicit Unbound and reopening without another migration. Main LuaJIT source
gate passes all 52 chunks. No live menu validation or deployment yet.

The lower-half report is addressed by the subsequent menu-height patch. DMF's
grid bottom remains at authored Y=1010 even when the fitted VR canvas is much
taller than 1080. Both grids now follow the actual scaled canvas height while
preserving footer clearance. See MENU-HEIGHT-WEAPON-STABILITY-2026-09-08.md for
validation and the remaining worn check.

Staff charge HUD disappearance is recorded in the active TODO. Stock charge-up
graphics are part of the crosshair template, while the VR HUD suppresses the
stock aiming widget. That is a candidate cause, not yet a tested fix. The prior
hit-marker stereo report remains open too.

Focused deployment preparation keeps the installed mapper's existing input
semantics; main's separate support-grip changes are not included in that focused
patch. Its own binding fixture passes against the focused source. The focused
source gate compiles 45 chunks. No game files or user settings have been changed.
