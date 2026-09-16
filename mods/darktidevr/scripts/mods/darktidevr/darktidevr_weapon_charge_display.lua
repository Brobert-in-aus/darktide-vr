-- The weapon counter's charge bars drawn at the weapon (todo-2026-09-14,
-- diegetic HUD: "the shock maul and force sword charge arcs ... drawn at the
-- weapon or the off-hand rather than the panel centre").
--
-- The stock element builds its bars as material passes on a widget per weapon
-- slot (`HudElementWeaponCounter._slot_widgets`, style ids `charge_bar_N`).
-- Those passes are rebuilt in the world the same way the crosshair's charge
-- and hit pieces are, by `darktidevr_crosshair_feedback`'s `Feedback.quad`,
-- which owns the pivot and rotation handling; this module only decides which
-- passes to take and where to put them.
--
-- The bars face the viewer rather than lying on the weapon: a bar edge-on is
-- unreadable, and the stock art is a flat overlay.
local Charge = {}

-- Metres per widget pixel. The stock bars are 400 units long, so this is a
-- bar about 10 cm across, sitting above the weapon.
Charge.PIXEL_METRES = 0.00026
-- Where the bars sit relative to the gun's attach point: a little forward,
-- and above the barrel so they do not cover the sights.
Charge.FORWARD, Charge.UP = 0.06, 0.09
-- The element's own charge bars, and nothing else it draws (its background,
-- its text). The crosshair's filter happens to match these ids too, since both
-- start "charge_"; being explicit is what keeps the two elements' rules apart
-- rather than one inheriting the other's.
function Charge.accept(id)
    return type(id) == "string" and id:match("^charge_") ~= nil
end

-- Whether a captured element is still the live one for this frame. Pure:
-- `now` and `stamp` are main-clock seconds, `max_age` the staleness limit.
function Charge.fresh(stamp, now, max_age)
    if type(stamp) ~= "number" or type(now) ~= "number" then return false end
    if now < stamp then return false end
    return now - stamp <= (max_age or 0.1)
end

Charge.TEST_FLAG = "./../mods/darktidevr/darktidevr_weapon_charge_test.flag"

function Charge.install(mod, presentation, tracking)
    local api = {}
    local Feedback = presentation.crosshair_feedback_module
    local source, source_t, world, gui, failed

    local test_poll, test_enabled = 0, false
    local function test_flag()
        test_poll = test_poll - 1
        if test_poll > 0 then return test_enabled end
        test_poll = 120
        local io_api = Mods and Mods.lua and Mods.lua.io
        local file = io_api and io_api.open(Charge.TEST_FLAG, "r")
        if not file then test_enabled = false; return false end
        local value = file:read("*all"); file:close()
        test_enabled = type(value) == "string" and value:match("^%s*enabled%s*$") ~= nil
        return test_enabled
    end

    function api.enabled()
        return mod:get("vr_weapon_charge") == true or test_flag()
    end

    function api.destroy()
        if gui then pcall(World.destroy_gui, world, gui) end
        world, gui, source, source_t = nil, nil, nil, nil
    end
    local function hide() if gui then Gui.set_visible(gui, false) end end

    mod:hook_safe("HudElementWeaponCounter", "update", function(self)
        source, source_t = self, Managers.time:time("main")
    end)
    mod:hook_safe("HudElementWeaponCounter", "destroy", function(self)
        if source == self then api.destroy(); failed = nil end
    end)

    -- The widget of the slot the player is holding, or nil.
    local function wielded_widget()
        if not source or not source._slot_widgets then return nil end
        local player = Managers.player and Managers.player:local_player_safe(1)
        local unit = player and player.player_unit
        local data = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "unit_data_system")
        local inventory = data and data:read_component("inventory")
        local slot = inventory and inventory.wielded_slot
        local widget = slot and source._slot_widgets[slot]
        if not widget or widget.visible == false then return nil end
        if widget.content and widget.content.visible == false then return nil end
        return widget
    end

    local function draw(game_world, eye, rotation)
        local hud = Managers.ui and Managers.ui._hud
        local now = Managers.time:time("main")
        if failed or not api.enabled() or not source or source._parent ~= hud or
                not Charge.fresh(source_t, now) or presentation.mode ~= 1 or
                not tracking.authoring_enabled or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then
            hide(); return
        end
        local widget = wielded_widget()
        if not widget or not widget.passes then hide(); return end
        local gun_position, gun_rotation = presentation.gun_aim.gun_pose()
        if not gun_position then hide(); return end
        local position = gun_position +
            Quaternion.forward(gun_rotation) * Charge.FORWARD +
            Quaternion.up(gun_rotation) * Charge.UP
        if world ~= game_world then
            local owner, stamp = source, source_t
            api.destroy(); world = game_world; source, source_t = owner, stamp
        end
        if not gui then gui = World.create_world_gui(world, Matrix4x4.identity(), 1, 1, "immediate") end
        Gui.set_visible(gui, true)
        local pixels = Charge.PIXEL_METRES
        local right, up, forward = Quaternion.right(rotation), Quaternion.up(rotation), Quaternion.forward(rotation)
        local drawn = 0
        for _, pass in ipairs(widget.passes) do
            local q = Feedback.quad(pass, widget, Charge.accept)
            if q then
                drawn = drawn + 1
                local tm = Matrix4x4.identity()
                Matrix4x4.set_right(tm, -right * q.c + up * q.s)
                Matrix4x4.set_up(tm, right * q.s + up * q.c)
                Matrix4x4.set_forward(tm, -forward)
                Matrix4x4.set_translation(tm, position + right * (q.x * pixels) - up * (q.y * pixels))
                Gui2.bitmap_3d(gui, q.material, nil, tm, q.layer,
                    {position_offset = Vector3(-q.w * pixels * 0.5, -q.h * pixels * 0.5, 0),
                    size = Vector3(q.w * pixels, q.h * pixels, 0),
                    color = Color(q.color[1], q.color[2], q.color[3], q.color[4]),
                    uv00 = Vector2(q.uvs[2][1], q.uvs[2][2]),
                    uv11 = Vector2(q.uvs[1][1], q.uvs[1][2]), snap_pixel_positions = false})
            end
        end
        if drawn > 0 and not api.logged then
            api.logged = true
            mod:info("DARKTIDEVR_WEAPON_CHARGE drawn=%d", drawn)
        end
    end

    function api.draw(...)
        local ok, err = pcall(draw, ...)
        if not ok then
            api.destroy(); failed = true
            mod:warning("DARKTIDEVR_WEAPON_CHARGE error=%s", tostring(err))
        end
    end
    return api
end

return Charge
