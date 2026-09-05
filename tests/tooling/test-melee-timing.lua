local Timing = dofile(arg[1])
local actions = {
    light = {kind="sweep", allowed_chain_actions={
        start_attack={action_name="windup",chain_time=.55},
        block={action_name="block",chain_time=.45}}},
    windup = {kind="windup", allowed_chain_actions={
        light_attack={action_name="light",chain_time=0},
        heavy_attack={action_name="heavy",chain_time=.5}}},
    heavy = {}, block = {},
}
local normal = {{action="light",input="start_attack"},
    {action="windup",input="light_attack"}}
local function scale(value) return function() return value end end
local seconds, target = Timing.resolve(actions,normal,scale(1))
assert(seconds == .55 and target == "light") -- Not the earlier block chain.
assert(Timing.resolve(actions,normal,scale(2)) == .275)
assert(Timing.resolve(actions,normal,scale(.5)) == 1.1)
assert(Timing.resolve(actions,normal,scale(.5),{sweep=true}) == .275)
local heavy = {{action="windup",input="heavy_attack",input_ready_after=.35}}
assert(Timing.resolve(actions,heavy,scale(1)) == .5)
assert(Timing.resolve(actions,heavy,scale(2)) == .35) -- Unscaled input hold floor.
assert(Timing.resolve(actions,heavy,scale(.5)) == 1)
actions.windup.allowed_chain_actions.light_attack.chain_time = .1
assert(Timing.resolve(actions,normal,scale(1)) == .65) -- Include intermediate action.
normal[2].action = "light"
assert(not Timing.resolve(actions,normal,scale(1)))
normal[2].action = "windup"
actions.light.allowed_chain_actions.start_attack.chain_until = .2
assert(not Timing.resolve(actions,normal,scale(1)))
actions.light.allowed_chain_actions.start_attack.chain_until = nil
assert(not Timing.resolve(actions,normal,scale(0)))
assert(not Timing.resolve(actions,normal,scale(0/0)))
print("melee_timing=pass")
