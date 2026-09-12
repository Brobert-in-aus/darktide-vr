-- Local presentation follows tracking immediately. The collider follows only
-- through stock, recorded movement inputs; collision and replay stay stock.
local Roomscale = {}
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function length(x,y) return math.sqrt(x*x+y*y) end

function Roomscale.new()
    local s = {x=0,y=0,z=0,cx=0,cy=0,render_cx=0,render_cy=0,
        rows={},automatic=false,deadzone=.10,max_speed=1.5}
    function s.reset()
        s.owner,s.epoch,s.sequence,s.sample_time=nil,nil,nil,nil
        s.x,s.y,s.z,s.rows,s.automatic=0,0,0,{},false
        s.cx,s.cy,s.render_cx,s.render_cy,s.last_frame=0,0,0,0,nil
    end
    function s.sample(owner,epoch,sequence,now,bx,bz,raw_y,floor,scale,yaw)
        if not finite(bx) or not finite(bz) or not finite(raw_y) or
                not finite(sequence) or sequence<=0 or not finite(now) or
                not finite(scale) or scale<=0 or not finite(yaw) then return false end
        if owner~=s.owner or epoch~=s.epoch or (s.sequence and sequence<s.sequence) then
            s.reset()
            s.owner,s.epoch,s.bx,s.bz=owner,epoch,bx,bz
            s.floor_base=finite(floor) and floor>0 and floor-raw_y or nil
        end
        if sequence==s.sequence then return true end
        local dx,dy=(bx-s.bx)*scale,-(bz-s.bz)*scale
        s.x=s.x+math.cos(yaw)*dx-math.sin(yaw)*dy
        s.y=s.y+math.sin(yaw)*dx+math.cos(yaw)*dy
        -- Stage height retains vertical travel beyond the sliding camera box.
        -- If STAGE tracking disappears, hold its extra offset, never jump to 0.
        if finite(floor) and floor>0 then
            s.floor_base=s.floor_base or floor-raw_y-s.z/scale
            s.z=(floor-s.floor_base-raw_y)*scale
        end
        s.bx,s.bz,s.sequence,s.sample_time=bx,bz,sequence,now
        return true
    end
    function s.record(frame,automatic)
        local slot=frame%600
        local previous=s.rows[slot]
        if previous and previous.frame==frame then return end
        s.rows[slot]={frame=frame,automatic=automatic,dx=0,dy=0}
        s.last_frame=math.max(s.last_frame or frame,frame)
        s.automatic=automatic
    end
    function s.moved(frame,dx,dy)
        local row=s.rows[frame%600]
        if not row or row.frame~=frame or not row.automatic or
                not finite(dx) or not finite(dy) then return end
        if length(dx,dy)>1 then s.reset(); return end -- teleport/invalid step
        -- Correction replay replaces a frame's contribution instead of paying
        -- for the same physical movement a second time.
        s.x,s.y=s.x-(dx-row.dx),s.y-(dy-row.dy)
        s.cx,s.cy=s.cx+(dx-row.dx),s.cy+(dy-row.dy)
        row.dx,row.dy=dx,dy
    end
    function s.capture_base(frame)
        -- First-person position is sampled BEFORE locomotion in stock fixed
        -- update. Cancel only travel represented in that camera anchor. During
        -- replay the later rows still exist; exclude those until replay reaches
        -- them rather than showing a one-frame reverse lurch while chasing.
        s.render_cx,s.render_cy=s.cx,s.cy
        if s.last_frame and frame<=s.last_frame then
            for _,row in pairs(s.rows) do
                if row.frame>=frame then
                    s.render_cx,s.render_cy=s.render_cx-row.dx,s.render_cy-row.dy
                end
            end
        end
    end
    function s.render_offset() return s.x+s.cx-s.render_cx,s.y+s.cy-s.render_cy,s.z end
    return s
end

-- predict(x,y) returns the displacement through the first requested step and
-- subsequent stock neutral-input braking, plus maximum speed along that path.
function Roomscale.choose(s,yaw,predict,quantize)
    local distance=length(s.x,s.y)
    if distance<=s.deadzone then return 0,0 end
    local c,sn=math.cos(yaw),math.sin(yaw)
    local dx,dy=(c*s.x+sn*s.y)/distance,(-sn*s.x+c*s.y)/distance
    local tx,ty=dx*(distance-s.deadzone),dy*(distance-s.deadzone)
    local best_x,best_y,best_cost=0,0,math.huge
    for _,amount in ipairs({0,1/256,1/128,1/64,1/32,1/16,1/8,1/4,1/2,1}) do
        local x,y=quantize(dx*amount,dy*amount)
        local stop_x,stop_y,speed=predict(x,y)
        if finite(stop_x) and finite(stop_y) and finite(speed) then
            local cost=(stop_x-tx)^2+(stop_y-ty)^2
            -- Prefer a comfortable catch-up speed even for a large separation.
            cost=cost+math.max(0,speed-s.max_speed)^2*100
            if cost<best_cost then best_x,best_y,best_cost=x,y,cost end
        end
    end
    return best_x,best_y
end

function Roomscale.install(mod,presentation)
    local s=Roomscale.new()
    local instance={state=s,failures=0}
    local movement
    local function warn(message)
        instance.failures=instance.failures+1
        if instance.failures==1 then mod:warning("DARKTIDEVR_ROOMSCALE fallback=%s",tostring(message)) end
    end
    function instance.offset(unit,epoch,sequence,now,bx,bz,raw_y,floor,scale,yaw)
        if not presentation.online_rules.simulation_aim_active(unit) then s.reset(); return 0,0,0 end
        s.sample(unit,epoch,sequence,now,bx,bz,raw_y,floor,scale,yaw)
        return s.render_offset()
    end
    local function plan(unit,frame,dt,t,yaw,desired,quantize)
        if unit~=s.owner or not s.sample_time or not finite(dt) or dt<=0 or dt>.05 or
                Managers.time:time("main")-s.sample_time>.15 then return desired,false end
        if Vector3.length_squared(desired)>1e-8 then return desired,false end
        local ext=ScriptUnit.has_extension(unit,"locomotion_system")
        local machine=ScriptUnit.has_extension(unit,"character_state_machine_system")
        if not ext or not machine or machine:current_state_name()~="walking" or
                not ext._inair_state_component.on_ground or
                ext._locomotion_force_translation_component.use_force_translation or
                ext._locomotion_force_rotation_component.use_force_rotation or
                ext._locomotion_component.parent_unit~=nil or
                Vector3.length_squared(ext._locomotion_push_component.velocity)>1e-8 or
                Vector3.length_squared(ext._locomotion_push_component.new_velocity)>1e-8 then return desired,false end
        local steering=ext._locomotion_steering_component
        -- Let a released manual stick finish its stock braking before assuming
        -- ownership of motion; otherwise that tail would be hidden from view.
        if not s.automatic and length(steering.local_move_x,steering.local_move_y)>.001 then return desired,false end
        movement=movement or require("scripts/extension_systems/character_state_machine/character_states/utilities/accelerated_local_space_movement")
        local buff=ScriptUnit.has_extension(unit,"buff_system")
        local weapon=ScriptUnit.has_extension(unit,"weapon_system")
        if not buff or not weapon then return desired,false end
        local multiplier=buff:stat_buffs().movement_speed
        local action_scale=weapon:move_speed_modifier(t)
        if not finite(multiplier) or not finite(action_scale) then return desired,false end
        local fp={rotation=Quaternion.identity()}
        local scratch={local_move_x=0,local_move_y=0}
        local requested=Vector3.zero()
        local source={get=function() return requested end}
        local current=Quaternion.rotate(Quaternion.inverse(presentation.flat_movement_rotation(yaw)),
            ext._locomotion_component.velocity_current)
        local crouching=ext._movement_state_component.is_crouching
        local function predict(x,y)
            scratch.local_move_x,scratch.local_move_y=steering.local_move_x,steering.local_move_y
            local px,py,max_speed=0,0,0
            local velocity=current
            for step=1,64 do
                requested=step==1 and Vector3(x,y,0) or Vector3.zero()
                local direction,speed,nx,ny,_,stopped,_,slide=movement.wanted_movement(
                    ext._constants,source,scratch,ext._movement_settings_component,fp,
                    crouching,velocity,dt,multiplier)
                if slide then return 0,0,math.huge end
                speed=speed*multiplier*action_scale
                max_speed=math.max(max_speed,speed)
                if ext._use_drag then speed=math.max(0,speed-.00855*speed*speed*dt) end
                velocity=direction*speed
                px,py=px+Vector3.x(velocity)*dt,py+Vector3.y(velocity)*dt
                scratch.local_move_x,scratch.local_move_y=nx,ny
                if stopped then return px,py,max_speed end
            end
            return 0,0,math.huge -- unbounded braking is not a valid prediction
        end
        local x,y=Roomscale.choose(s,yaw,predict,quantize)
        local automatic=x~=0 or y~=0 or (s.automatic and
            length(steering.local_move_x,steering.local_move_y)>.001)
        return Quaternion.rotate(presentation.flat_movement_rotation(yaw),Vector3(x,y,0)),automatic
    end
    function instance.plan(unit,frame,dt,t,yaw,desired,quantize)
        local ok,result,automatic=pcall(plan,unit,frame,dt,t,yaw,desired,quantize)
        if ok then return result,automatic end
        warn(result)
        return desired,false
    end
    function instance.record(frame,automatic) s.record(frame,automatic) end
    function instance.capture_base(unit,frame)
        if unit==s.owner and finite(frame) then s.capture_base(frame) end
    end
    function instance.moved(ext,unit,frame,dx,dy)
        if unit~=s.owner or not finite(frame) then return end
        -- State changes/pushes after input capture must remain visible motion.
        if ext._character_state_component.state_name~="walking" or
                not ext._inair_state_component.on_ground or
                Vector3.length_squared(ext._locomotion_push_component.velocity)>1e-8 or
                Vector3.length_squared(ext._locomotion_push_component.new_velocity)>1e-8 then
            s.moved(frame,0,0)
            return
        end
        s.moved(frame,dx,dy)
    end
    return instance
end

return Roomscale
