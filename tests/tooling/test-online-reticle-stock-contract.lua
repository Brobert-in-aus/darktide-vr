-- Actual stock recoil/sway, isolated numeric rotations. No engine/random spread.
local root=assert(arg[2])
Script={new_array=function() return {} end}
package.loaded['scripts/settings/buff/buff_settings']={}
package.loaded['scripts/extension_systems/weapon/utilities/weapon_movement_state']={
    translate_movement_state_component=function() return 'still' end}
Vector3={right=function() return 'pitch' end,up=function() return 'yaw' end}
Quaternion=setmetatable({multiply=function(a,b) return a+b end,
    from_yaw_pitch_roll=function(y,p,r) return y+p+r end},
    {__call=function(_,axis,angle) assert(axis=='pitch' or axis=='yaw'); return angle end})
local recoil=dofile(root..'/scripts/utilities/recoil.lua')
local sway=dofile(root..'/scripts/utilities/sway.lua')
package.loaded['scripts/utilities/recoil']=recoil
package.loaded['scripts/utilities/sway']=sway
Managers={input={is_using_gamepad=function() return false end}}
DevParameters={disable_aim_assist=false}
local template={actions={fire={kind='shoot_hit_scan'}}}
local settings={still={camera_recoil_percentage=0}}
local ext={_unit='local',_first_person_component={position=1,rotation=0},
    _recoil_component={pitch_offset=.2,yaw_offset=.3},
    _sway_component={offset_x=.04,offset_y=.05},
    _weapon_extension={weapon_template=function() return template end,
        running_action_settings=function() return template.actions.fire end,
        recoil_template=function() return settings end,sway_template=function() return {} end}}
local module=dofile(assert(arg[1])).install({warning=function() error('unexpected fallback') end},
    {online_rules={simulation_aim_active=function() return true end}})
for _,camera_fraction in ipairs({0,.2,.5,.8,1}) do
    settings.still.camera_recoil_percentage=camera_fraction
    local pitch,yaw=recoil.first_person_offset(settings,ext._recoil_component,{},{},{})
    ext._first_person_component.rotation=pitch+yaw
    local position,rotation=module.pose(ext,0)
    assert(position==1 and math.abs(rotation-(.2+.3+.04+.05))<1e-9,
        'camera recoil was double applied or weapon recoil omitted')
end
print('PASS actual stock recoil/sway: five camera/weapon recoil splits produce the same shot centre')
print('LIMIT: additive rotation fixture; random spread, native raycasts and worn alignment remain live checks')
