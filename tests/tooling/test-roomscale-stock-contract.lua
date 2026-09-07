-- Optional integration against the inspected stock walking implementation.
-- Vector math and quantization are fixtures; no native collision/network/XR.
local Roomscale=dofile(assert(arg[1]))
local root=assert(arg[2])
local mt={}
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x,y,z},mt) end})
mt.__mul=function(v,n) return Vector3(v[1]*n,v[2]*n,v[3]*n) end
Vector3.x=function(v) return v[1] end; Vector3.y=function(v) return v[2] end
Vector3.to_elements=function(v) return unpack(v) end
Vector3.dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
Vector3.length_squared=function(v) return Vector3.dot(v,v) end
Vector3.length=function(v) return math.sqrt(Vector3.length_squared(v)) end
Vector3.normalize=function(v) local n=Vector3.length(v); return n>0 and v*(1/n) or Vector3(0,0,0) end
Vector3.flat=function(v) return Vector3(v[1],v[2],0) end
Vector3.up=function() return Vector3(0,0,1) end
Vector3.zero=function() return Vector3(0,0,0) end
Quaternion={identity=function() return 0 end,inverse=function(q) return -q end,
    forward=function(q) return Vector3(-math.sin(q),math.cos(q),0) end,
    look=function(v) return math.atan2(-v[1],v[2]) end,
    rotate=function(q,v) return Vector3(math.cos(q)*v[1]-math.sin(q)*v[2],
        math.sin(q)*v[1]+math.cos(q)*v[2],v[3]) end}
math.lerp=function(a,b,t) return a+(b-a)*t end
local path='scripts/extension_systems/character_state_machine/character_states/utilities/accelerated_local_space_movement'
local movement=dofile(root..'/'..path..'.lua')
package.loaded[path]=movement
local now=0
Managers={time={time=function() return now end}}
local unit={}
local constants={acceleration=19,deceleration=6,backward_move_scale=.5,
    move_speed=5,crouch_move_speed=2,slide_move_speed_threshold=3}
local ext={_constants=constants,_use_drag=true,_inair_state_component={on_ground=true},
    _locomotion_force_translation_component={use_force_translation=false},
    _locomotion_force_rotation_component={use_force_rotation=false},
    _locomotion_push_component={velocity=Vector3.zero(),new_velocity=Vector3.zero()},
    _movement_settings_component={player_speed_scale=1},_movement_state_component={is_crouching=false},
    _character_state_component={state_name='walking'}}
local speed_modifier=1
ScriptUnit={has_extension=function(_,name)
    if name=='locomotion_system' then return ext end
    if name=='character_state_machine_system' then return {current_state_name=function() return ext._character_state_component.state_name end} end
    if name=='buff_system' then return {stat_buffs=function() return {movement_speed=1} end} end
    if name=='weapon_system' then return {move_speed_modifier=function() return speed_modifier end} end
end}
local mod={warning=function(_,_,message) error(message) end}
local presentation={flat_movement_rotation=function(yaw) return yaw end,
    online_rules={simulation_aim_active=function() return true end}}
local function quantize(x,y)
    local function q(v) return math.floor(math.abs(v)*255+.5)/255*(v<0 and -1 or 1) end
    return q(x),q(y)
end
local cases=0
for _,dt in ipairs({1/30,1/60,1/90}) do
    for _,yaw in ipairs({0,math.pi/4,math.pi/2,math.pi,math.pi*1.5}) do
        for _,modifier in ipairs({.35,1,1.4}) do
            speed_modifier=modifier
            ext._locomotion_steering_component={local_move_x=0,local_move_y=0}
            ext._locomotion_component={velocity_current=Vector3.zero()}
            local instance=Roomscale.install(mod,presentation)
            local s=instance.state
            now=0; instance.offset(unit,'epoch',1,now,0,0,0,1.7,1,0)
            local body_x,body_y=0,0
            local max_speed=0
            for frame=1,math.floor(5/dt) do
                now=frame*dt
                -- A 60 cm physical step, followed by stationary head tracking.
                instance.offset(unit,'epoch',frame+1,now,.6,0,0,1.7,1,0)
                local desired,automatic=instance.plan(unit,frame,dt,now,yaw,Vector3.zero(),quantize)
                instance.record(frame,automatic)
                instance.capture_base(unit,frame)
                local camera_base_x,camera_base_y=body_x,body_y
                local local_input=Quaternion.rotate(-yaw,desired)
                local x,y=quantize(local_input[1],local_input[2])
                local direction,speed,nx,ny=movement.wanted_movement(constants,
                    {get=function() return Vector3(x,y,0) end},ext._locomotion_steering_component,
                    ext._movement_settings_component,{rotation=yaw},false,
                    ext._locomotion_component.velocity_current,dt)
                speed=speed*modifier
                max_speed=math.max(max_speed,speed)
                local velocity=direction*(speed-.00855*speed*speed*dt)
                ext._locomotion_steering_component.local_move_x=nx
                ext._locomotion_steering_component.local_move_y=ny
                ext._locomotion_component.velocity_current=velocity
                -- Blocked mover for the first half second; no phantom repayment.
                local dx,dy=0,0
                if now>.5 then dx,dy=velocity[1]*dt,velocity[2]*dt end
                body_x,body_y=body_x+dx,body_y+dy
                instance.moved(ext,unit,frame,dx,dy)
                instance.moved(ext,unit,frame,dx,dy) -- correction repeats this step
                local render_x,render_y=s.render_offset()
                assert(math.abs(camera_base_x+render_x-.6)<1e-7,'stock camera phase lurch')
                assert(math.abs(camera_base_y+render_y)<1e-7,'stock camera phase drift')
                assert(math.abs(body_x+s.x-.6)<1e-7,'camera was carried twice')
                assert(math.abs(body_y+s.y)<1e-7,'lateral camera drift')
            end
            assert(math.sqrt(s.x*s.x+s.y*s.y)<.102,'failed to settle: '..s.x..','..s.y)
            assert(math.sqrt(s.x*s.x+s.y*s.y)>.065,'excessive overshoot')
            assert(max_speed<1.6,'catch-up speed exceeded limit')
            local desired,automatic=instance.plan(unit,999,dt,now,yaw,Vector3(1,0,0),quantize)
            assert(desired[1]==1 and not automatic,'manual movement lost priority')
            now=now+1
            desired,automatic=instance.plan(unit,1000,dt,now,yaw,Vector3.zero(),quantize)
            assert(Vector3.length_squared(desired)==0 and not automatic,'stale tracking drove movement')
            cases=cases+1
        end
    end
end
print('PASS roomscale stock walking: '..cases..' combinations; acceleration/braking, aim bases, weapon speed, blocked mover, replay, manual priority, stale tracking')
-- A walking physical target followed by a turn of the aim basis and a stop.
speed_modifier=1
ext._locomotion_steering_component={local_move_x=0,local_move_y=0}
ext._locomotion_component={velocity_current=Vector3.zero()}
local live=Roomscale.install(mod,presentation)
now=0; live.offset(unit,'dynamic',1,now,0,0,0,1.7,1,0)
local body_x,body_y=0,0
for frame=1,420 do
    local dt=1/60
    now=frame*dt
    local target_x=.5*math.min(now,2)
    local yaw=math.min(now,3)*.5
    live.offset(unit,'dynamic',frame+1,now,target_x,0,0,1.7,1,0)
    local desired,automatic=live.plan(unit,frame,dt,now,yaw,Vector3.zero(),quantize)
    live.record(frame,automatic); live.capture_base(unit,frame)
    local input=Quaternion.rotate(-yaw,desired)
    local ix,iy=quantize(input[1],input[2])
    local direction,speed,nx,ny=movement.wanted_movement(constants,
        {get=function() return Vector3(ix,iy,0) end},ext._locomotion_steering_component,
        ext._movement_settings_component,{rotation=yaw},false,
        ext._locomotion_component.velocity_current,dt)
    local velocity=direction*(speed-.00855*speed*speed*dt)
    ext._locomotion_steering_component.local_move_x=nx
    ext._locomotion_steering_component.local_move_y=ny
    ext._locomotion_component.velocity_current=velocity
    live.moved(ext,unit,frame,velocity[1]*dt,velocity[2]*dt)
    local rx,ry=live.state.render_offset()
    assert(math.abs(body_x+rx-target_x)<1e-7 and math.abs(body_y+ry)<1e-7,'moving target displaced view')
    body_x,body_y=body_x+velocity[1]*dt,body_y+velocity[2]*dt
end
assert(Vector3.length(Vector3(live.state.x,live.state.y,0))<.102,'moving target failed to settle')
live.record(421,true); live.moved(ext,unit,421,.01,0)
local prior=live.state.x
ext._locomotion_push_component.velocity=Vector3(1,0,0)
live.moved(ext,unit,421,.2,0)
assert(math.abs(live.state.x-prior-.01)<1e-8,'push correction retained old chase repayment')
local _,automatic=live.plan(unit,422,1/60,now,0,Vector3.zero(),quantize)
assert(not automatic,'chase fought external push')
print('PASS roomscale dynamic target: physical walking, changing aim, stop and push correction')
print('LIMIT: fixture 8-bit quantization, collision displacement stub, no worn/render or official server acceptance')
