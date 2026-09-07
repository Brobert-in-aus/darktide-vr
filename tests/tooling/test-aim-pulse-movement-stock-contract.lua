-- Optional source-only probe of stock movement with supplied cardinal inputs.
-- No engine serialization, collision, body integration or live headset input.
local meta={}
Vector3=setmetatable({}, {__call=function(_,x,y,z) return setmetatable({x,y,z},meta) end})
meta.__mul=function(a,b) return Vector3(a[1]*b,a[2]*b,a[3]*b) end
Vector3.to_elements=function(v) return unpack(v) end
Vector3.dot=function(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
Vector3.length_squared=function(v) return Vector3.dot(v,v) end
Vector3.length=function(v) return math.sqrt(Vector3.length_squared(v)) end
Vector3.normalize=function(v) local n=Vector3.length(v); return n>0 and v*(1/n) or Vector3(0,0,0) end
Vector3.flat=function(v) return Vector3(v[1],v[2],0) end
Vector3.up=function() return Vector3(0,0,1) end
Quaternion={forward=function(yaw) return Vector3(-math.sin(yaw),math.cos(yaw),0) end,
    look=function(v) return math.atan2(-v[1],v[2]) end,
    rotate=function(yaw,v) return Vector3(math.cos(yaw)*v[1]-math.sin(yaw)*v[2],
        math.sin(yaw)*v[1]+math.cos(yaw)*v[2],v[3]) end}
math.lerp=function(a,b,t) return a+(b-a)*t end
local path=assert(arg[1])..'/scripts/extension_systems/character_state_machine/character_states/utilities/accelerated_local_space_movement.lua'
local movement=dofile(path)
local constants={acceleration=19,deceleration=6,backward_move_scale=.5,
    move_speed=5,crouch_move_speed=2,slide_move_speed_threshold=3}
local dt=1/60
print('degrees,pulse_frames,first_heading_error,first_desired_speed,reverse_after_return')
for _,degrees in ipairs({90,180}) do
    for _,pulse in ipairs({1,6}) do
        local steering={local_move_x=0,local_move_y=1}
        local first_error,first_speed,reverse_after_return
        local direction,speed
        for frame=1,pulse+8 do
            local active=frame<=pulse
            local yaw=active and math.rad(degrees) or 0
            -- Exact cardinal values supplied after aim-basis conversion.
            -- Actual wire quantization and near-zero rounding are not modeled.
            local requested=not active and Vector3(0,1,0) or
                degrees==90 and Vector3(1,0,0) or Vector3(0,-1,0)
            local x,y
            direction,speed,x,y=movement.wanted_movement(constants,
                {get=function(_,name) assert(name=='move'); return requested end},
                steering,{player_speed_scale=1},{rotation=yaw},false,Vector3(0,5,0),dt)
            steering.local_move_x,steering.local_move_y=x,y
            if frame==1 then
                first_error=math.abs(math.deg(math.atan2(direction[1],direction[2])))
                first_speed=speed
            elseif not active and direction[2]<-.99 then reverse_after_return=true end
        end
        assert(first_error>60,'Reaudit changed movement response to an aim-basis pulse')
        assert(math.abs(direction[1])<1e-9 and direction[2]>.999 and math.abs(speed-5)<1e-9,
            'Movement did not settle after returning to head aim')
        if degrees==180 and pulse==6 then assert(reverse_after_return) end
        print(string.format('%d,%d,%.5f,%.5f,%s',degrees,pulse,first_error,first_speed,tostring(not not reverse_after_return)))
    end
end
print('PASS: supplied aim pulses expose stock local-axis smoothing; recovery settles')
print('LIMIT: fixture constants 60Hz exact_cardinal_inputs wanted_movement_only no_wire_collision_or_worn_acceptance')
