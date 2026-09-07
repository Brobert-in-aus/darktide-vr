local Roomscale=dofile(assert(arg[1]))
local function near(a,b) assert(math.abs(a-b)<1e-8,tostring(a)..' != '..tostring(b)) end
local s=Roomscale.new()
s.sample('player','bridge:1',1,0,10,20,0,1.7,1,0)
s.sample('player','bridge:1',2,.01,10.4,19.8,.2,1.9,1,0)
near(s.x,.4); near(s.y,.2); near(s.z,0)
s.record(1,true); s.moved(1,.1,.05)
near(s.x,.3); near(s.y,.15)
near(s.render_offset(),.4) -- stock camera still represents before frame 1
s.capture_base(2); near(s.render_offset(),.3)
s.capture_base(1); near(s.render_offset(),.4) -- replay anchor excludes future rows
s.moved(1,.1,.05); near(s.x,.3) -- same correction replay
s.moved(1,.08,.04); near(s.x,.32); near(s.y,.16)
s.capture_base(2); near(s.render_offset(),.32)
s.record(2,false); s.moved(2,.2,.2); near(s.x,.32)
s.sample('player','bridge:1',3,.02,10.4,19.8,1.2,3.7,1,math.pi/2)
near(s.x,.32); near(s.y,.16); near(s.z,.8) -- turn does not orbit the residual
s.sample('player','bridge:1',4,.03,10.5,19.8,1.2,0,1,math.pi/2)
near(s.x,.32); near(s.y,.26); near(s.z,.8) -- lost STAGE retains extra height
s.sample('player','bridge:2',5,.04,10.5,19.8,0,1.7,1,0)
near(s.x,0); near(s.y,0); near(s.z,0); assert(next(s.rows)==nil)
s.sample('new-player','bridge:2',6,.05,20,30,0,1.7,1,0); near(s.x,0)
assert(not s.sample('new-player','bridge:2',7,.06,0/0,30,0,1.7,1,0))
s.sample('new-player','bridge:2',1,.07,25,30,0,1.7,1,0); near(s.x,0)
s.record(600,true); s.moved(600,.1,0); near(s.x,-.1)
s.record(1200,false); s.moved(600,.5,0); near(s.x,-.1) -- expired frame
s.record(1201,true); s.moved(1201,5,0); assert(s.owner==nil)
print('PASS roomscale: tracking basis, vertical envelope, recenter, owner, replay, history expiry, teleport')

-- Execute the registered production locomotion hook. Core-state tests alone
-- missed the real input-extension boundary: HumanUnitInput owns the frame.
local main=assert(io.open(assert(arg[2]),'rb'))
local source=main:read('*a'); main:close()
local hook_source=assert(source:match('(mod:hook%(%s*require%(%s*"scripts/extension_systems/locomotion/player_unit_locomotion_extension".-)%s*function presentation.scan_named_nodes'))
Vector3={x=function(v) return v.x end,y=function(v) return v.y end,
    length_squared=function(v) return v.x*v.x+v.y*v.y+v.z*v.z end}
local hook
local mod={warning=function(_,_,message) error(message) end,
    hook=function(_,_,method,callback) assert(method=='_update_script_driven_movement'); hook=callback end}
local presentation={online_rules={simulation_aim_active=function() return true end},
    apply_body_follow_translation=function() return nil end}
presentation.roomscale=Roomscale.install(mod,presentation)
local chunk=assert(loadstring(hook_source))
setfenv(chunk,setmetatable({mod=mod,presentation=presentation,require=function() return {} end},{__index=_G}))
chunk()
local unit={}
local instance=presentation.roomscale
local state=instance.state
instance.offset(unit,'live',1,0,0,0,0,1.7,1,0)
instance.offset(unit,'live',2,.01,.4,0,0,1.7,1,0)
local ext={_input_extension={_human_unit_input={_frame=0}},
    _character_state_component={state_name='walking'},_inair_state_component={on_ground=true},
    _locomotion_push_component={velocity={x=0,y=0,z=0},new_velocity={x=0,y=0,z=0}}}
local body=0
local function simulate(frame,delta,automatic)
    ext._input_extension._human_unit_input._frame=frame
    instance.record(frame,automatic)
    instance.capture_base(unit,frame)
    near(body+state.render_offset(),.4)
    local current={x=body,y=0,z=0}
    local returned=hook(function(_,_,dt,t,loc,steering,position)
        -- Also exercise an engine-like aliased position result.
        position.x=position.x+delta
        return position
    end,ext,unit,1/60,frame/60,{}, {},current,false,true,{})
    assert(returned==current)
    body=body+delta
end
simulate(1,.1,true); near(state.x,.3)
simulate(2,.1,true); near(state.x,.2)
simulate(3,.1,true); near(state.x,.1)
simulate(4,0,false); near(state.x,.1)
-- Replaying a frame replaces its repayment, without consuming it twice.
body=.1; simulate(2,.1,true); near(state.x,.1)
instance.capture_base(unit,5); near(.3+state.render_offset(),.4)
-- A pushed correction removes the old automatic attribution.
ext._locomotion_push_component.velocity.x=1
body=.1
hook(function() return {x=.2,y=0,z=0} end,ext,unit,1/60,2/60,{}, {},{x=.1,y=0,z=0},false,true,{})
near(state.x,.2)
print('PASS roomscale production hook: nested input frame, collider repayment, fixed visual head, replay and push')
