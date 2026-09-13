local Reticle=dofile(assert(arg[1]))
local calls={}
local function called(name) calls[#calls+1]=name end
package.loaded['scripts/utilities/recoil']={apply_weapon_recoil_rotation=function(_,_,_,_,_,rotation)
    called('weapon_recoil'); return rotation+2 end}
package.loaded['scripts/utilities/sway']={apply_sway_rotation=function(_,_,rotation)
    called('sway'); return rotation+3 end}
package.loaded['scripts/utilities/smart_targeting']={smart_targeting_template=function(t)
    assert(t==12); called('targeting'); return 'targeting' end}
local gamepad,auto,admitted=false,false,true
Managers={input={is_using_gamepad=function() return gamepad end}}
DevParameters={disable_aim_assist=false}
local instance=Reticle.install({warning=function() called('warning') end},
    {online_rules={simulation_aim_active=function(unit) return admitted and unit=='local' end}})
local settings,template
local ext={_unit='local',_first_person_component={position=99,rotation=10},
    _buff_extension={has_keyword=function() return auto end},
    _weapon_extension={weapon_template=function() return template end,
        running_action_settings=function() return settings end,
        recoil_template=function() return {} end,sway_template=function() return {} end},
    assisted_hitscan_trajectory=function(_,targeting,weapon,rotation)
        assert(targeting=='targeting' and weapon==template); called('assist'); return rotation+7 end}
for _,kind in ipairs({'shoot_hit_scan','shoot_pellets','shoot_projectile'}) do
    template={actions={fire={kind=kind}}}
    for _,active in ipairs({kind,'aim','reload','wield'}) do
        settings={kind=active}
        for _,assist in ipairs({'none','gamepad','auto','disabled'}) do
            calls={}; gamepad=assist=='gamepad'; auto=assist=='auto' or assist=='disabled'
            DevParameters.disable_aim_assist=assist=='disabled'
            local pos,rotation=instance.pose(ext,12)
            assert(pos==99 and rotation==((gamepad or auto) and assist~='disabled' and 22 or 15))
            assert(calls[1]=='weapon_recoil' and calls[2]=='sway')
            assert(ext._first_person_component.rotation==10,'preview wrote shared simulation aim')
        end
    end
end
for _,kind in ipairs({'spawn_projectile','flamer_gas','flamer_gas_burst','chain_lightning'}) do
    calls={}; settings={kind=kind}; template={keywords={'force_staff'},actions={fire=settings}}
    local pos,rotation=instance.pose(ext,12)
    assert(pos==99 and rotation==10 and #calls==0,'direct route inherited gun recoil')
    settings={kind='aim'}; assert(select(2,instance.pose(ext,12))==10)
end
admitted=false; assert(instance.pose(ext,12)==nil)
admitted=true; ext._unit='remote'; assert(instance.pose(ext,12)==nil)
ext._unit='local'; template={actions={fire={kind='shoot_hit_scan'}}}; settings=nil
ext._weapon_extension.sway_template=function() error('retired weapon') end
local pos,rotation=instance.pose(ext,12)
assert(pos==99 and rotation==10 and instance.failures==1)
print('PASS online reticle: gun/idle/ADS/reload routes, recoil/sway/assist order, direct staff/flame routes, ownership and fallback')
if arg[2] then
    local file=assert(io.open(arg[2],'r')); local source=file:read('*all'); file:close()
    local first=assert(source:find('function presentation.publish_gameplay_aim_state(',1,true))
    local last=assert(source:find('\nfunction presentation.body_ik_calibrated_wrist_target(',first,true))
    local mt={}
    local vec=setmetatable({x=function(v) return v[1] end,y=function(v) return v[2] end,z=function(v) return v[3] end},
        {__call=function(_,x,y,z) return setmetatable({x,y,z},mt) end})
    mt.__sub=function(a,b) return vec(a[1]-b[1],a[2]-b[2],a[3]-b[3]) end
    mt.__div=function(v,n) return vec(v[1]/n,v[2]/n,v[3]/n) end
    local quat={from_elements=function() return math.pi/2 end,inverse=function(q) return -q end,
        rotate=function(q,v) return vec(math.cos(q)*v[1]-math.sin(q)*v[2],math.sin(q)*v[1]+math.cos(q)*v[2],v[3]) end}
    local legacy,packet={},nil
    local keyboard_mouse=false
    local online=true
    local p={online_rules={enabled=function() return online end},calibrated_character_scale=function() return 2 end,
        keyboard_mouse_enabled=function() return keyboard_mouse end,keyboard_mouse_view_pitch=function() return 0 end,
        native_gameplay_aim_target=function(...) packet={...}; return 0 end}
    local obs={body_anchor_x=10,body_anchor_y=20,body_anchor_z=30,body_anchor_pose_sequence=42,
        body_anchor_pose_generation=3,body_anchor_recenter_generation=8}
    local env=setmetatable({presentation=p,controller_observation=obs,Vector3=vec,Quaternion=quat,
        ui_native_capture={dtvr_set_gameplay_aim_state=function(...) legacy={...}; return 0 end},
        Managers={player={local_player=function() return {} end}}},{__index=_G})
    setfenv(assert(loadstring(source:sub(first,last-1))),env)()
    assert(p.publish_gameplay_aim_state(true,true,12,vec(8,22,31)))
    assert(packet[1]==1 and packet[2]==6 and math.abs(packet[3]-1)<1e-9 and
        math.abs(packet[4]-.5)<1e-9 and math.abs(packet[5]+1)<1e-9 and
        packet[6]==42 and packet[7]==3 and packet[8]==8,'world target basis/scale/reference changed')
    assert(p.publish_gameplay_aim_state(false,false,0) and legacy[1]==0)
    -- Keyboard and mouse aim has no hand ray: even outside online rules it sends
    -- the world-depth target point, never the controller-extended distance.
    keyboard_mouse,online,packet,legacy=true,false,nil,{}
    assert(p.publish_gameplay_aim_state(true,true,12,vec(8,22,31)) and packet and packet[1]==1 and
        packet[6]==42 and legacy[1]==nil,'keyboard and mouse mode fell back to the hand-ray reticle')
    keyboard_mouse,online=false,true
    p.native_gameplay_aim_target=function() return 3 end
    assert(not p.publish_gameplay_aim_state(true,true,12,vec(8,22,31)) and legacy[1]==0,
        'failed target packet left an older reticle active')
    p.native_gameplay_aim_target=nil
    assert(not p.publish_gameplay_aim_state(true,true,12,vec(8,22,31)) and legacy[1]==0,
        'old DLL displayed the wrong ray as if it were the stock target')
    print('PASS online reticle native seam: exact target, basis, character scale, pose identity and old-DLL clear')
end
