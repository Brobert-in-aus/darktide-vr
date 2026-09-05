local CombatDirection = {}
local function packed(...) return {n=select("#", ...), ...} end

function CombatDirection.install(mod, aim)
    local scope
    local writes = 0
    local function with_left_block(func, target_unit, ...)
        local player = Managers.player and Managers.player:local_player(1)
        if not player or target_unit ~= player.player_unit then
            return func(target_unit, ...)
        end
        local _, rotation = aim.target("left")
        if not rotation then return func(target_unit, ...) end
        local previous = scope
        scope = {unit=target_unit, rotation=rotation}
        local result = packed(pcall(func, target_unit, ...))
        scope = previous
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    -- Both eligibility and block cost read first_person through unit data.
    -- Substitute only that read during the local player's block calculation;
    -- never modify the movement/camera component or other players' headings.
    mod:hook(require("scripts/extension_systems/unit_data/player_unit_data_extension"),
        "read_component", function(func, self, name)
            local component = func(self, name)
            if scope and self._unit == scope.unit and name == "first_person" then
                writes = writes + 1
                if writes == 1 then
                    mod:info("DARKTIDEVR_BLOCK direction=left_hand stock_angles_and_cost=true")
                end
                return setmetatable({rotation=scope.rotation}, {__index=component})
            end
            return component
        end)
    local block = require("scripts/utilities/attack/block")
    mod:hook(block, "is_blocking", with_left_block)
    mod:hook(block, "attempt_block_break", with_left_block)
end

return CombatDirection
