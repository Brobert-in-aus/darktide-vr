-- Artificial yaw only. Rendering and gameplay consume the same scene heading;
-- this module never emits mouse input or replaces physical head orientation.
local Turning = {}

function Turning.widgets()
    return {setting_id="vr_turning",type="group",sub_widgets={
        {setting_id="vr_turn_mode",type="dropdown",default_value="smooth",options={
            {text="vr_turn_smooth",value="smooth"},
            {text="vr_turn_snap45",value="snap45"},
            {text="vr_turn_snap90",value="snap90"},
            {text="vr_turn_off",value="off"},
        }},
        {setting_id="vr_turn_speed",type="numeric",default_value=90,range={30,180},
            decimals_number=0,step_size_value=15},
    }}
end

function Turning.install(mod)
    local state = {armed=false}
    local api = {}
    function api.sample(enabled, x, y, usable, generation, recenter, context, t)
        local mode=mod:get("vr_turn_mode")
        if mode~="off" and mode~="snap45" and mode~="snap90" then mode="smooth" end
        local speed=mod:get("vr_turn_speed")
        if type(speed)~="number" or not (speed>=30 and speed<=180) then speed=90 end
        local valid=enabled==true and usable==true and mode~="off" and
            type(x)=="number" and x>=-1 and x<=1 and
            type(y)=="number" and y>=-1 and y<=1 and
            type(t)=="number" and t==t and t>-math.huge and t<math.huge
        local changed=state.mode~=mode or state.speed~=speed or
            state.generation~=generation or state.recenter~=recenter or state.context~=context
        local dt=state.t and valid and t-state.t or 0
        state.mode,state.speed,state.generation,state.recenter,state.context=mode,speed,generation,recenter,context
        if not valid or changed or dt<0 or dt>0.1 then state.armed=false end
        -- Repeated callbacks at the same time cannot repeat a snap or integrate
        -- smooth turn twice. A pause never accumulates deferred rotation.
        if valid and state.t==t and not changed then return 0 end
        state.t=valid and t or nil
        if not valid then return 0 end
        if math.max(math.abs(x),math.abs(y))<=0.25 then state.armed=true; return 0 end
        -- Only the horizontal 90-degree sectors turn. Exact diagonals belong
        -- to vertical shortcuts, so the two routes cannot fire together.
        -- Moving through up/down does not rearm a snap without neutral.
        if math.abs(x)<=math.abs(y) or math.abs(x)<=0.25 then return 0 end
        if not state.armed then return 0 end
        local sign=x<0 and -1 or 1
        if mode=="smooth" then
            if dt<=0 or dt>0.1 then return 0 end
            return -sign*((math.abs(x)-0.25)/0.75)*speed*math.pi/180*dt
        end
        if math.abs(x)<0.65 then return 0 end
        state.armed=false
        return -sign*(mode=="snap90" and math.pi/2 or math.pi/4)
    end
    return api
end

return Turning
