local Feedback=dofile(assert(arg[1]))
local function near(a,b) assert(math.abs(a-b)<1e-8,string.format('%g != %g',a,b)) end
local widget={content={charge='stock_charge',hit='stock_hit'},style={
    charge_left={size={24,56},offset={-32,0,1}},
    charge_mask_left={size={24,26},offset={-32,13,2},uvs={{1,.5},{0,1}}},
    hit_top_left={size={15,3},offset={-12,-12,1},pivot={7.5,1.5},angle=-math.pi/4,color={128,255,0,0}},
    center={size={4,4},offset={0,0,1}}}}
local bar=Feedback.quad({style_id='charge_left',value_id='charge'},widget)
near(bar.x,-32);near(bar.y,0);assert(bar.material=='stock_charge')
local mask=Feedback.quad({style_id='charge_mask_left',value_id='charge'},widget)
near(mask.x,-32);near(mask.y,13);near(mask.h,26);assert(mask.uvs[1][2]==.5)
local hit=Feedback.quad({style_id='hit_top_left',value_id='hit'},widget)
near(hit.x,-12);near(hit.y,-12);near(hit.c,math.sqrt(.5));near(hit.s,-math.sqrt(.5))
assert(hit.color[1]==128 and Feedback.quad({style_id='center'},widget)==nil)
widget.style.hit_top_left.visible=false;assert(Feedback.quad({style_id='hit_top_left'},widget)==nil)
widget.style.charge_mask_left.size[2]=0;assert(Feedback.quad({style_id='charge_mask_left'},widget)==nil)
near(Feedback.pixel_scale(10,1),.49/41*.7)
near(Feedback.pixel_scale(.1,1),.105/41*.7)
near(Feedback.pixel_scale(100,1),.84/41*.7)
near(Feedback.pixel_scale(20,2),.98/41*.7)
-- Both eyes consume one world-plane description; no screen-edge coordinate
-- enters either the scale or stock layout calculation.
local left,right=Feedback.quad({style_id='charge_left',value_id='charge'},widget),
    Feedback.quad({style_id='charge_left',value_id='charge'},widget)
near(left.x,right.x);near(left.w,right.w)
local hooks,destroyed={},0
World={destroy_gui=function() destroyed=destroyed+1 end}
Managers={ui={_hud={_currently_visible_elements={HudElementCrosshair=true}}},time={time=function() return 1 end}}
local presentation={mode=1,gameplay_context={ui_blocks_gameplay=function() return false end}}
local api=Feedback.install({hook_safe=function(_,class,method,fn) assert(class=='HudElementCrosshair');hooks[method]=fn end,
    warning=function(_,message) error(message) end},presentation,{authoring_enabled=true})
-- Missing/stale/foreign HUD ownership must produce no world draw or failure.
api.draw({},nil,nil)
hooks.update({_parent={}},0,1,nil,{})
api.draw({},nil,nil)
api.destroy();api.destroy();assert(destroyed==0)
local mt={}
local function vec(x,y,z) return setmetatable({x,y,z},mt) end
mt.__add=function(a,b) return vec(a[1]+b[1],a[2]+b[2],a[3]+b[3]) end
mt.__sub=function(a,b) return vec(a[1]-b[1],a[2]-b[2],a[3]-b[3]) end
mt.__unm=function(a) return vec(-a[1],-a[2],-a[3]) end
mt.__mul=function(a,b) return vec(a[1]*b,a[2]*b,a[3]*b) end
Vector3=vec;Vector2=function(...) return {...} end;Color=Vector2
Quaternion={right=function() return vec(1,0,0) end,up=function() return vec(0,0,1) end,
    forward=function() return vec(0,1,0) end}
Matrix4x4={identity=function() return {} end,set_right=function(m,v) m.right=v end,
    set_up=function(m,v) m.up=v end,set_forward=function(m,v) m.forward=v end,
    set_translation=function(m,v) m.position=v end}
local created,visible,draws=0,false,{}
World.create_world_gui=function(_,_,_,_,mode) assert(mode=='immediate');created=created+1;return {} end
Gui={set_visible=function(_,value) visible=value end}
Gui2={bitmap_3d=function(_,material,_,tm,layer,args)
    draws[#draws+1]={material=material,tm=tm,layer=layer,args=args}
end}
local point=vec(0,10,0)
presentation.controller_aim={reticle_distance=10,cached_reticle_target=function()
    return {unbox=function() return point end}
end}
presentation.calibrated_character_scale=function() return 1 end
Managers.player={local_player_safe=function() return {} end}
widget.passes={{style_id='charge_left',value_id='charge'}}
local owner={_parent=Managers.ui._hud,_widget=widget}
local world={}
hooks.update(owner,0,1,nil,{alpha_multiplier=.5})
api.draw(world,vec(0,0,0),{})
assert(created==1 and #draws==1 and visible)
near(draws[1].tm.position[1],-32*.49/41*.7)
near(draws[1].tm.position[2],10);near(draws[1].args.color[1],127.5)
assert(draws[1].args.uv00[1]==1 and draws[1].args.uv11[1]==0)
point=vec(2,10,0);api.draw(world,vec(0,0,0),{})
near(draws[2].tm.position[1],2-32*.49/41*.7);assert(created==1)
presentation.mode=5;api.draw(world,vec(0,0,0),{});assert(not visible and #draws==2)
hooks.destroy(owner);api.destroy();assert(destroyed==1)
print('Stock charge masks, rotated hit offsets/alpha, reticle scale caps and absent-owner lifetime pass')
