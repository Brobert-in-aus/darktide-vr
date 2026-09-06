# Hub-to-Psykhanium HUD material cleanup

The user's manual transition from a populated hub crashed on 6 September.
The console's script error was `ui_renderer.lua:278: bad argument #2 to
'destroy_material' (Material expected, got userdata)`. Its stack runs through
texture pass destruction, UIWidget, HudElementMissionSpeakerPopup, UIHud and
HumanGameplay's HUD removal. This is distinct from the previously documented
remote-husk `parent_unit_id` teardown race. The new NGX diagnostic was not
deployed in this run.

The HUD panel's renderer transfer only visited elements marked retained. Stock
immediate-mode texture passes also keep `pass.data.material` and
`material_value` caches. Destroying the capture GUI while those widgets survive
leaves invalid material references for later stock HUD destruction or redraw.
The base element's `set_visible` may also be a no-op, so its existence is not
proof that retained resources were released.

The candidate keeps retained visibility callbacks, then explicitly destroys
every fixed element's `_widgets` through its source renderer before switching
ownership or destroying the renderer. Stock pass destructors clear material and
retained caches; widgets are marked dirty for recreation. Spatial elements are
excluded. Destruction errors still contribute to the existing transfer failure
count rather than being overwritten by later successful widgets.

Validation: `hud_panel`, `hud_options` and the pinned LuaJIT gate (31 chunks)
pass. The new regression uses immediate speaker-popup, retained/no-op visibility
and spatial widgets with explicit material owners. It requires fixed materials
to be released before their renderer dies, leaves spatial materials alone until
stock cleanup, and preserves the stock destructor's return values.

This is a source-supported candidate, not live crash-resolution acceptance.
Next worn check: enter the Psykhanium manually from the hub after hearing a
mission-speaker popup; verify the transition and HUD reconstruction. Keep the
separate historical remote-husk signature distinguishable if another crash
occurs. The user's new hand-offset, turning, handedness and menu-hint requests
are recorded in REMAINING-DEVELOPMENT.md rather than claimed as implemented.
