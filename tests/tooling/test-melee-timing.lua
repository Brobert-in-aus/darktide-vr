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
assert(cycle.heavy_auto_complete_after == nil and cycle.heavy_damage_charge == "constant_one")
local release = template.action_inputs.heavy_attack.input_sequence[2]
release.auto_complete, release.time_window = true, 1
cycle = assert(Timing.from_windup(template,"windup",scale(2),nil,function() return true end))
assert(cycle.heavy_auto_complete_after == 1.35 and cycle.heavy_charge == .35)
actions.heavy.use_charge = true
cycle = assert(Timing.from_windup(template,"windup",scale(.25),nil,function() return true end))
assert(cycle.heavy_auto_complete_after == 2 and cycle.heavy_damage_charge == "module")
release.time_window = math.huge
cycle = assert(Timing.from_windup(template,"windup",scale(1),nil,function() return true end))
assert(cycle.heavy_auto_complete_after == nil)
assert(not Timing.from_windup(template,"windup",scale(1),nil,function(a) return a ~= actions.heavy end))
template.action_inputs.heavy_attack.input_sequence[1].input = "unknown_input"
local missing, why = Timing.from_windup(template,"windup",scale(1),nil,function() return true end)
assert(not missing and why == "unsupported_heavy_input")
template.action_inputs.heavy_attack.input_sequence[1].input = "action_one_hold"
actions.light.allowed_chain_actions.start_attack = {{action_name="windup",chain_time=.55}}
assert(not Timing.from_windup(template,"windup",scale(1),nil,function() return true end))
-- Chainsword p1 m1's ordinary light loop, from the inspected stock template.
-- Keeping all four transitions catches accidental reuse of the opening timing.
local combo = {actions={}, action_inputs={heavy_attack={input_sequence={
    {input="action_one_hold",value=true,duration=.35},
    {input="action_one_hold",value=false,auto_complete=true,time_window=1}}}}}
local intervals, heavy_thresholds = {.55,.6,.45,.55}, {.5,.4,.5,.45}
for i=1,4 do
    combo.actions['w'..i] = {kind="windup",allowed_chain_actions={
        light_attack={action_name='l'..i,chain_time=0},
        heavy_attack={action_name='h'..i,chain_time=heavy_thresholds[i]}}}
    combo.actions['l'..i] = {kind="sweep",allowed_chain_actions={
        start_attack={action_name='w'..(i%4+1),chain_time=intervals[i]}}}
    combo.actions['h'..i] = {kind="sweep"}
end
for i=1,4 do
    local result = assert(Timing.from_windup(combo,'w'..i,scale(1),nil,function() return true end))
    assert(result.light_interval==intervals[i] and result.heavy_charge==heavy_thresholds[i])
    assert(result.heavy_auto_complete_after==1.35 and result.next_light_action=='l'..(i%4+1))
end
local graph=assert(Timing.light_combo(combo,'w1',scale(1),nil,function() return true end,4))
assert(#graph.steps==4 and graph.cycle_start==1 and graph.entry_duration==0)
assert(math.abs(graph.cycle_duration-2.15)<1e-9)
for i,step in ipairs(graph.steps) do
    assert(step.light_action=='l'..i and step.interval==intervals[i])
end
-- A separate opening route can enter a loop without itself recurring.
combo.actions.entry={kind='windup',allowed_chain_actions={
    light_attack={action_name='opening',chain_time=0},heavy_attack={action_name='h1',chain_time=.5}}}
combo.actions.opening={kind='sweep',allowed_chain_actions={
    start_attack={action_name='w1',chain_time=.7}}}
graph=assert(Timing.light_combo(combo,'entry',scale(2),nil,function() return true end))
assert(#graph.steps==5 and graph.cycle_start==2 and graph.entry_duration==.35)
assert(math.abs(graph.cycle_duration-1.075)<1e-9)
-- Each action gets its own live effective scale, rather than the entry's scale.
graph=assert(Timing.light_combo(combo,'w1',function(a)
    return a==combo.actions.l2 and 2 or 1
end,nil,function() return true end))
assert(graph.steps[1].interval==.55 and graph.steps[2].interval==.3)
local failed,reason,at=Timing.light_combo(combo,'w1',scale(1),nil,function() return true end,3)
assert(not failed and reason=='combo_limit' and at=='w4')
assert(not Timing.light_combo(combo,'w1',scale(1),nil,function() return true end,0))
combo.actions.l3.allowed_chain_actions.start_attack.running_action_state_requirement={done=true}
failed,reason,at=Timing.light_combo(combo,'w1',scale(1),nil,function() return true end)
assert(not failed and reason=='unsupported_route' and at=='w3')
combo.actions.l3.allowed_chain_actions.start_attack.running_action_state_requirement=nil
combo.actions.l2.allowed_chain_actions.start_attack.action_name='missing'
assert(not Timing.light_combo(combo,'w1',scale(1),nil,function() return true end))
print("melee_timing=pass combo=variable graph=bounded heavy_minimum_distinct_from_auto_complete=true")
