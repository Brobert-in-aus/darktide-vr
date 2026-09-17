-- Teammate status (option "vr_teammate_status", default off; backlog,
-- 15 September evening): each teammate's name, toughness and health bars,
-- and a disabled state (downed, netted, ...) float above their head instead
-- of the team panel, whose teammate panels are hidden while it is on (the
-- local player's own panel stays). Drawn on the hand overlay's panels
-- (darktidevr_hand_overlay), so they show through walls like stock
-- nameplates, at a constant apparent size.
local Status = {}

Status.ABOVE_HEAD = 0.35
-- Panel scale per metre of distance: a constant angular size.
Status.METRES_PER_PIXEL_PER_METRE = 0.0006
Status.MIN_DISTANCE, Status.MAX_DISTANCE = 1, 40
Status.HIDE_NEARER_THAN = 0.8
Status.BAR_WIDTH, Status.BAR_HEIGHT, Status.BAR_GAP = 180, 11, 16 -- pixels
Status.NAME_SIZE, Status.STATE_SIZE = 30, 28
Status.HEALTH_COLOR = {255, 255, 255}
Status.TOUGHNESS_COLOR = {108, 187, 196}
Status.STATE_COLOR = {255, 90, 70}
Status.STATE_LABELS = {
    knocked_down = "DOWNED", hogtied = "NEEDS RESCUE", ledge_hanging = "LEDGE", netted = "NETTED",
    pounced = "POUNCED", catapulted = "GRABBED", consumed = "CONSUMED", grabbed = "GRABBED",
    mutant_charged = "GRABBED", warp_grabbed = "GRABBED",
}

local function finite(x) return type(x) == "number" and x == x and math.abs(x) < math.huge end
local function clamp01(x) return finite(x) and math.max(0, math.min(1, x)) or nil end

-- The label for a character state, or nil when not disabled. Pure.
function Status.state_label(state_name)
    return type(state_name) == "string" and Status.STATE_LABELS[state_name] or nil
end

-- Panel scale for a distance, or nil when too near to show. Pure.
-- The overlay anchor key for one teammate, stable across a frame's iteration
-- order. `unique_id` is asked first on purpose: it is peer id, local player id
-- and a counter, so it differs for every player INCLUDING bots, which are
-- added with no account id at all and carry the *host's* peer id. Asking for
-- those first gave all three of solo play's bots one key, which is two panels
-- fighting over one bot's head and none over the others, every frame (review,
-- 18 September). A field that is really the class method is refused, because
-- every player shares that one function address. Falls back to the unit, which
-- is stable while they live. Pure.
function Status.anchor_key(player, unit)
    local id
    if type(player) == "table" then
        local function try(value)
            if id ~= nil then return end
            if type(value) == "function" then
                local ok, result = pcall(value, player)
                value = ok and result or nil
            end
            if type(value) == "string" or type(value) == "number" then id = value end
        end
        try(player.unique_id)
        try(player.account_id)
        try(player.peer_id)
    end
    return "teammate_" .. tostring(id or unit)
end

function Status.metres_per_pixel(distance)
    if not finite(distance) or distance < Status.HIDE_NEARER_THAN then return nil end
    return math.max(Status.MIN_DISTANCE, math.min(Status.MAX_DISTANCE, distance)) * Status.METRES_PER_PIXEL_PER_METRE
end

-- Bar fractions from sampled values, toughness above health. Pure.
function Status.bars(values)
    local bars = {}
    if type(values) ~= "table" then return bars end
    local toughness = clamp01(values.toughness)
    if toughness then bars[#bars + 1] = {id = "toughness", fraction = toughness, color = Status.TOUGHNESS_COLOR} end
    local health = finite(values.health) and finite(values.max_health) and values.max_health > 0 and
        clamp01(values.health / values.max_health) or nil
    if health then bars[#bars + 1] = {id = "health", fraction = health, color = Status.HEALTH_COLOR} end
    return bars
end

function Status.install(mod, presentation)
    local api = {}
    local failed, logged = false, false
    local function enabled() return mod.get and mod:get("vr_teammate_status") == true end
    api.enabled = enabled
    -- The team panel's teammate panels, hidden while the status floats above
    -- the teammates instead.
    if mod.hook then
        mod:hook("HudElementTeamPlayerPanel", "draw", function(func, self, ...)
            if enabled() and presentation.mode == 1 then return end
            return func(self, ...)
        end)
    end
    local function field(read) local ok, value = pcall(read); return ok and value or nil end
    local function values_for(unit)
        local health = ScriptUnit.has_extension(unit, "health_system")
        local toughness = ScriptUnit.has_extension(unit, "toughness_system")
        local unit_data = ScriptUnit.has_extension(unit, "unit_data_system")
        return {
            health = health and field(function() return health:current_health() end),
            max_health = health and field(function() return health:max_health() end),
            toughness = toughness and field(function() return toughness:current_toughness_percent() end),
            state = unit_data and field(function() return unit_data:read_component("character_state").state_name end),
        }
    end
    local function draw(world, local_unit)
        if not enabled() or presentation.mode ~= 1 or not local_unit or
                (presentation.current_game_mode_name and presentation.current_game_mode_name() == "hub") then
            return
        end
        local overlay = presentation.hand_overlay
        local eye = presentation.eye_pose and presentation.eye_pose(local_unit)
        if not overlay or not eye then return end
        local players = Managers.player and Managers.player:players() or {}
        -- The cell an anchor claims shows one frame late, so an anchor's key
        -- must belong to the player, not to their place in an unordered
        -- iteration: keyed by index, a join, a death or a respawn re-orders
        -- `pairs` and draws one teammate's bars and name over another's head
        -- for a frame.
        for _, player in pairs(players) do
            local unit = player.player_unit
            if unit and unit ~= local_unit and Unit.alive(unit) then
                local visibility = ScriptUnit.has_extension(unit, "player_visibility_system")
                local visible = not visibility or field(function() return visibility:visible() end) ~= false
                local head = Unit.has_node(unit, "j_head") and Unit.world_position(unit, Unit.node(unit, "j_head")) or
                    Unit.world_position(unit, 1) + Vector3(0, 0, 1.7)
                local anchor = head + Vector3(0, 0, Status.ABOVE_HEAD)
                local mpp = Status.metres_per_pixel(Vector3.distance(anchor, eye))
                if visible and mpp then
                    local canvas = overlay.canvas(world, Status.anchor_key(player, unit), anchor, mpp)
                    if canvas then
                        local values = values_for(unit)
                        local y = 0
                        local label = Status.state_label(values.state)
                        if label then
                            canvas.text(label, Status.STATE_SIZE, 0, (y + Status.BAR_GAP * 2.2) * mpp,
                                {255, Status.STATE_COLOR[1], Status.STATE_COLOR[2], Status.STATE_COLOR[3]})
                        end
                        local name = field(function() return player:name() end)
                        if type(name) == "string" then
                            canvas.text(name, Status.NAME_SIZE, 0, (y + Status.BAR_GAP * 1.1) * mpp, {235, 235, 235, 235})
                        end
                        for i, bar in ipairs(Status.bars(values)) do
                            local by = (y - (i - 1) * Status.BAR_GAP) * mpp
                            local w, h = Status.BAR_WIDTH * mpp, Status.BAR_HEIGHT * mpp
                            canvas.rect(0, by, w, h, {130, 20, 20, 20})
                            local filled = w * bar.fraction
                            if filled > 0 then
                                canvas.rect(-w * 0.5 + filled * 0.5, by, filled, h, {230, bar.color[1], bar.color[2], bar.color[3]})
                            end
                        end
                        if not logged then
                            logged = true
                            mod:info("DARKTIDEVR_TEAMMATE_STATUS first_draw name=%s state=%s distance_m=%.1f",
                                tostring(name), tostring(values.state), Vector3.distance(anchor, eye))
                        end
                    end
                end
            end
        end
    end
    function api.draw(world, local_unit)
        if failed then return end
        local ok, err = pcall(draw, world, local_unit)
        if not ok then
            failed = true
            mod:warning("DARKTIDEVR_TEAMMATE_STATUS error=%s", tostring(err))
        end
    end
    return api
end

return Status
