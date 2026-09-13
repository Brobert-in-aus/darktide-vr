-- Diegetic ammo readout: values from the stock slot component fields, text
-- and warning levels, and its wiring after the hand pose.
local Readout = dofile(assert(arg[1]))

local Ammo = {
    clips_in_use = function(slot, out)
        local any = false
        for i = 1, 2 do out[i] = slot.current_ammunition_clips_in_use[i] == true; any = any or out[i] end
        return any
    end,
    current_ammo_in_clips = function(slot, i) return slot.current_ammunition_clip[i] end,
    max_ammo_in_clips = function(slot, i) return slot.max_ammunition_clip[i] end,
}
local function gun(clip, reserve)
    return {max_ammunition_reserve = 400, current_ammunition_reserve = reserve,
        current_ammunition_clips_in_use = {true, false},
        current_ammunition_clip = {clip, 99}, max_ammunition_clip = {40, 99}}
end

local v = assert(Readout.values(gun(12, 180), Ammo, 2))
assert(v.clip == 12 and v.clip_max == 40 and v.reserve == 180 and v.reserve_max == 400 and not v.heat, "unused clip counted")
local text, level = Readout.text(v)
assert(text == "12 | 180" and level == "normal", text)
-- Stock low-ammo threshold: 20 % of clip plus reserve.
text, level = Readout.text(Readout.values(gun(10, 78), Ammo, 2))
assert(level == "low", level)
text, level = Readout.text(Readout.values(gun(0, 300), Ammo, 2))
assert(text == "0 | 300" and level == "critical")
-- Heat-only weapons (plasma, some staffs report heat without reserve).
v = assert(Readout.values({overheat_current_percentage = 0.5}, Ammo, 2))
text, level = Readout.text(v)
assert(text == "50%" and level == "normal", text)
assert(select(2, Readout.text({heat = 0.8})) == "low")
assert(select(2, Readout.text({heat = 0.95})) == "critical")
-- Both: ammo and heat side by side.
local both = gun(5, 100); both.overheat_current_percentage = 0.3
assert(Readout.text(Readout.values(both, Ammo, 2)) == "5 | 100  30%")
-- Nothing to show: melee slot fields, no reserve, no clips in use, cold.
assert(Readout.values({}, Ammo, 2) == nil)
assert(Readout.values({max_ammunition_reserve = 0, overheat_current_percentage = 0}, Ammo, 2) == nil)
local idle = gun(5, 5); idle.current_ammunition_clips_in_use = {false, false}
assert(Readout.values(idle, Ammo, 2) == nil)
assert(Readout.values(nil, Ammo, 2) == nil and Readout.text(nil) == nil)

-- Drawn after the hand pose, and released with the other GUI resources.
local file = assert(io.open(assert(arg[2]), "rb")); local main = file:read("*a"); file:close()
local ik = assert(main:find("presentation.gun_aim.update(self._world, player_unit)", 1, true))
local draw = assert(main:find("presentation.ammo_readout.draw(self._world, player_unit)", 1, true))
assert(draw > ik, "readout drawn before the hand pose")
local state = assert(main:find("mod.on_game_state_changed = function", 1, true))
assert(main:find("presentation.ammo_readout.destroy", state, true), "readout GUI survives loading")
print("ammo_readout=pass values text levels heat_only nothing_to_show after_hand_pose")
