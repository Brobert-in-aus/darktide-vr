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
actions.heavy.kind = "sweep"
local template = {actions=actions,action_inputs={heavy_attack={input_sequence={
    {input="action_one_hold",value=true,duration=.35},{input="action_one_hold",value=false}}}}}
local cycle = assert(Timing.from_windup(template,"windup",scale(2),nil,function() return true end))
assert(cycle.light_action == "light" and cycle.heavy_action == "heavy")
assert(cycle.light_interval == .325 and cycle.heavy_charge == .35)
assert(not Timing.from_windup(template,"windup",scale(1),nil,function(a) return a ~= actions.heavy end))
template.action_inputs.heavy_attack.input_sequence[1].input = "unknown_input"
local missing, why = Timing.from_windup(template,"windup",scale(1),nil,function() return true end)
assert(not missing and why == "unsupported_heavy_input")
template.action_inputs.heavy_attack.input_sequence[1].input = "action_one_hold"
actions.light.allowed_chain_actions.start_attack = {{action_name="windup",chain_time=.55}}
assert(not Timing.from_windup(template,"windup",scale(1),nil,function() return true end))
print("melee_timing=pass")
