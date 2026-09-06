local Roles=dofile(arg[1])
local file=assert(io.open(arg[2])); local source=file:read('*all'); file:close()
local first=assert(source:find('function presentation.weapon_aim_target(role)',1,true))
local last=assert(source:find('\nfunction presentation.publish_gameplay_aim_state',first,true))
local physical={left={aim=11,grip=12},right={aim=21,grip=22}}
presentation={controller_aim_target=function() return physical.right.aim,'right_aim' end,
    left_controller_aim_target=function() return physical.left.aim,'left_aim' end,
    controller_grip_target=function() return physical.right.grip,'right_grip' end,
    left_controller_grip_target=function() return physical.left.grip,'left_grip' end}
assert(loadstring(source:sub(first,last-1)))()
for _,dominant in ipairs({'right','left','invalid',false}) do
    local policy=Roles.new(dominant)
    local side=dominant=='left' and 'left' or 'right'
    local support=side=='left' and 'right' or 'left'
    assert(policy.physical('dominant')==side and policy.physical('support')==support)
    assert(policy.physical('left')=='left' and policy.physical('right')=='right')
    assert(policy.physical('unknown')==nil and policy.physical(nil)==nil)
    presentation.weapon_hand_roles=policy
    assert(presentation.weapon_aim_target('dominant')==physical[side].aim)
    assert(presentation.weapon_grip_target('support')==physical[support].grip)
    assert(presentation.weapon_aim_target('left')==11 and presentation.weapon_grip_target('right')==22)
    assert(presentation.weapon_aim_target('unknown')==nil)
end
-- Tracking loss stays on the chosen physical hand; no opposite-hand fallback.
presentation.weapon_hand_roles=Roles.new('left')
physical.left.aim=nil; physical.left.grip=nil
assert(presentation.weapon_aim_target('dominant')==nil and presentation.weapon_grip_target('dominant')==nil)
assert(presentation.weapon_aim_target('support')==21)
assert(physical.right.aim==21 and physical.right.grip==22)
print('PASS: fixed weapon roles preserve physical identity and per-hand tracking fallback')
