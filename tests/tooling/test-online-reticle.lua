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
        native_gameplay_aim_target=function(...) packet={...}; return 0 end,
        -- The zoom correction has a slice and a stub of its own below: it
        -- needs a real quaternion, and the anchor frame here deliberately
        -- uses a fake one.
        zoom_corrected_aim_point=function(point) return point end,
        projection_math=dofile(assert(arg[3]))}
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
    -- The publisher hands the point through the zoom correction before it
    -- converts to the anchor frame, and publishes exactly what comes back.
    p.native_gameplay_aim_target=function(...) packet={...}; return 0 end
    local corrected=nil
    p.zoom_corrected_aim_point=function(point) corrected=point; return vec(9,23,32) end
    assert(p.publish_gameplay_aim_state(true,true,12,vec(8,22,31)))
    assert(corrected and corrected[1]==8,'the raw world point goes to the correction')
    assert(math.abs(packet[3]-1.5)<1e-9 and math.abs(packet[4]-1)<1e-9 and
        math.abs(packet[5]+0.5)<1e-9,'the corrected point is what is published')
    p.zoom_corrected_aim_point=function(point) return point end
    print('PASS online reticle native seam: exact target, basis, character scale, pose identity and old-DLL clear')

    -- The zoom correction, with a real quaternion. The magnification is about
    -- the EYE's forward: a target dead centre in the view needs no correction
    -- at all, whatever direction the head is facing. Correcting in the frame
    -- the point is published in -- the recentre pose -- displaced exactly
    -- those targets, by more than the error it was meant to remove (review,
    -- 18 September).
    local zfirst = assert(source:find('function presentation.zoom_corrected_aim_point(', 1, true))
    local zlast = assert(source:find('\nfunction presentation.publish_gameplay_aim_state(', zfirst, true))
    local vmt = {}
    local function v3(x, y, z) return setmetatable({x, y, z}, vmt) end
    vmt.__add = function(a, b) return v3(a[1]+b[1], a[2]+b[2], a[3]+b[3]) end
    vmt.__sub = function(a, b) return v3(a[1]-b[1], a[2]-b[2], a[3]-b[3]) end
    local V3 = setmetatable({x=function(v) return v[1] end, y=function(v) return v[2] end,
        z=function(v) return v[3] end}, {__call=function(_, x, y, z) return v3(x, y, z) end})
    local Q = {}
    function Q.from_elements(x, y, z, w) return {x, y, z, w} end
    function Q.inverse(q) return {-q[1], -q[2], -q[3], q[4]} end
    function Q.rotate(q, v)
        local x, y, z, w = q[1], q[2], q[3], q[4]
        local dot = x*v[1] + y*v[2] + z*v[3]
        local cx, cy, cz = y*v[3]-z*v[2], z*v[1]-x*v[3], x*v[2]-y*v[1]
        local k = w*w - (x*x + y*y + z*z)
        return v3(2*dot*x + k*v[1] + 2*w*cx, 2*dot*y + k*v[2] + 2*w*cy,
            2*dot*z + k*v[3] + 2*w*cz)
    end
    -- A rotation of `angle` about `axis`, normalised.
    local function axis_angle(ax, ay, az, angle)
        local half = angle * 0.5
        local sn = math.sin(half)
        return {ax*sn, ay*sn, az*sn, math.cos(half)}
    end
    local eye = v3(3, -4, 1.7)
    local zp = {eye_pose = function() return eye end,
        projection_math = dofile(assert(arg[3]))}
    local zobs = {}
    local zenv = setmetatable({presentation = zp, controller_observation = zobs,
        Vector3 = V3, Quaternion = Q}, {__index = _G})
    setfenv(assert(loadstring(source:sub(zfirst, zlast - 1))), zenv)()

    local function set_head(yaw, pitch)
        -- Darktide: +z up, +x right, +y forward. Yaw about z, then pitch about
        -- the yawed right axis, which for these tests is x at yaw 0.
        local qz = axis_angle(0, 0, 1, yaw)
        local qx = axis_angle(math.cos(yaw), math.sin(yaw), 0, pitch)
        local x1, y1, z1, w1 = qz[1], qz[2], qz[3], qz[4]
        local x2, y2, z2, w2 = qx[1], qx[2], qx[3], qx[4]
        local q = {w1*x2 + x1*w2 + y1*z2 - z1*y2, w1*y2 - x1*z2 + y1*w2 + z1*x2,
            w1*z2 + x1*y2 - y1*x2 + z1*w2, w1*w2 - x1*x2 - y1*y2 - z1*z2}
        zobs.head_aim_qx, zobs.head_aim_qy, zobs.head_aim_qz, zobs.head_aim_qw =
            q[1], q[2], q[3], q[4]
        return q
    end
    local function forward_point(q, metres)
        local f = Q.rotate(q, v3(0, 1, 0))
        return v3(eye[1] + f[1]*metres, eye[2] + f[2]*metres, eye[3] + f[3]*metres)
    end
    local function distance(a, b)
        local dx, dy, dz = a[1]-b[1], a[2]-b[2], a[3]-b[3]
        return math.sqrt(dx*dx + dy*dy + dz*dz)
    end

    -- OFF, the hit point is published untouched -- which is the whole point
    -- of the switch: a reticle that marks geometry has to stay on it, and
    -- turning it about the eye takes it off the surface it was measured on.
    zp.zoom_aim_correction_flag = false
    zp.ads_zoom_applied = 1.12
    for _, yaw in ipairs({0, 0.9, -2.0}) do
        for _, pitch in ipairs({0, 0.35, -0.4}) do
            local q = set_head(yaw, pitch)
            local ahead_v = forward_point(q, 10)
            local right_v = Q.rotate(q, v3(1, 0, 0))
            local off_axis = v3(ahead_v[1] + right_v[1]*2.5,
                ahead_v[2] + right_v[2]*2.5, ahead_v[3] + right_v[3]*2.5)
            assert(distance(zp.zoom_corrected_aim_point(off_axis), off_axis) < 1e-9,
                'off, a target well off the view axis is published exactly as measured')
        end
    end
    zp.zoom_aim_correction_flag = true

    zp.ads_zoom_applied = 1.12
    -- Dead ahead of the head, at every orientation: the DIRECTION is
    -- untouched. This is the assertion the wrong frame failed, by over a
    -- degree at ten degrees of pitch and three at forty-five, and it is
    -- checked here as "still on the same ray from the eye" rather than "in
    -- the same place" -- which is stronger about direction, and leaves room
    -- for the range, which now deliberately moves.
    --
    -- The range comes IN by the magnification (19 September). The sights
    -- render through a narrowed frustum and submit the field of view
    -- unchanged, so the world in them appears at D/m while the reticle's quad
    -- layer is composited at the submitted field of view and stays at D. A
    -- target dead ahead is exactly the case that has no angular correction at
    -- all and the full radial one, so it is the cleanest place to state it.
    for _, yaw in ipairs({0, 0.3, 1.2, -2.0, 3.0}) do
        for _, pitch in ipairs({0, 0.17, 0.35, 0.52, 0.79, -0.4}) do
            local q = set_head(yaw, pitch)
            local target = forward_point(q, 10)
            local moved = zp.zoom_corrected_aim_point(target)
            local wanted = forward_point(q, 10 / 1.12)
            assert(distance(moved, wanted) < 1e-4,
                string.format('a target dead ahead is not at 10/m: off by %.4f m at yaw %.2f pitch %.2f',
                    distance(moved, wanted), yaw, pitch))
            -- Said again as a range, so a change that moved the point along
            -- some OTHER ray of the right length could not pass the line
            -- above and this one together.
            assert(math.abs(distance(moved, eye) - 10 / 1.12) < 1e-4,
                string.format('the range is not 10/m at yaw %.2f pitch %.2f', yaw, pitch))
            assert(distance(moved, target) > 1.0,
                'the correction has to actually move it, or this proves nothing')
        end
    end
    -- Off the view's centre the RAY turns outward by the magnification, and
    -- then the whole thing comes IN by it.
    --
    -- The comment here used to say "the range from the eye is kept... scaling
    -- across and holding depth moved the point off the surface it was
    -- measured on, which worn put the reticle underneath the ground". That
    -- read the symptom right and the cause backwards. Preserving the range is
    -- what LEFT the reticle too far away: the sights render through a
    -- narrowed frustum and submit the field of view unchanged, so the world in
    -- them appears at D/m while the reticle's quad layer is composited at the
    -- submitted field of view and stays at D. The user settled it on 19
    -- September -- the error is proportional to the distance aimed, and it is
    -- not there outside the sights, neither of which a preserved range can
    -- explain and both of which this does.
    local q = set_head(0.9, -0.3)
    local right = Q.rotate(q, v3(1, 0, 0))
    local ahead = forward_point(q, 10)
    local off = v3(ahead[1] + right[1]*0.7, ahead[2] + right[2]*0.7, ahead[3] + right[3]*0.7)
    local moved = zp.zoom_corrected_aim_point(off)
    local delta = moved - eye
    local forward = Q.rotate(q, v3(0, 1, 0))
    local depth = delta[1]*forward[1] + delta[2]*forward[2] + delta[3]*forward[3]
    local across = delta[1]*right[1] + delta[2]*right[2] + delta[3]*right[3]
    -- The tangent is what has to be magnified, and it still is exactly.
    assert(math.abs((across / depth) - (0.7 / 10) * 1.12) < 1e-6,
        'the tangent across the view is the magnified one: ' .. (across / depth))
    -- The range is divided by the magnification, which is the half of the
    -- correction the angular one could never do: magnified_target renormalises
    -- to the original length by construction.
    local range_before = math.sqrt(0.7 * 0.7 + 10 * 10)
    local range_after = math.sqrt(depth * depth + across * across)
    assert(math.abs(range_after - range_before / 1.12) < 1e-4,
        'the range comes in by the magnification: ' .. range_after ..
        ' vs ' .. (range_before / 1.12))
    -- Stated twice over, because the tangent above is invariant under any
    -- uniform scale and would pass whatever the range did: the point is on
    -- the magnified ray AND at the shortened range, not one or the other.
    assert(depth < 10 / 1.12 + 1e-4 and depth > 10 / 1.12 - 0.01,
        'the depth comes in with it: ' .. depth)
    assert(across > 0.7 / 1.12, 'and the point still moves outward across the view: ' .. across)
    assert(range_after < range_before - 1.0, 'the correction has to actually shorten it')
    -- No zoom, no movement; and nothing to work with is not an error.
    zp.ads_zoom_applied = 1
    assert(distance(zp.zoom_corrected_aim_point(off), off) < 1e-9, 'no zoom, no correction')
    zp.ads_zoom_applied = 1.12
    zobs.head_aim_qw = nil
    assert(distance(zp.zoom_corrected_aim_point(off), off) < 1e-9, 'no head rotation: unchanged')
    set_head(0, 0)
    zp.eye_pose = function() return nil end
    assert(distance(zp.zoom_corrected_aim_point(off), off) < 1e-9, 'no eye: unchanged')
    assert(zp.zoom_corrected_aim_point(nil) == nil, 'no point: nothing to do')
    print('PASS online reticle zoom frame: centred targets untouched at every head angle')
end
