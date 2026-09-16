-- Reuse stock charge/hit styles, placing their pixels around the shared
-- hand-aim target. No charge simulation, damage inference or eye-edge scaling.
local Feedback={}
-- accept(id) chooses which of a widget's passes to rebuild; without it, the
-- crosshair's own charge and hit passes. The weapon counter reuses this for
-- its charge bars, which are the same kind of material pass with the same
-- pivot and rotation handling.
function Feedback.accept_crosshair(id)
    return id:match('^charge_')~=nil or id:match('^hit_')~=nil
end
function Feedback.quad(pass,widget,accept)
    local id=pass.style_id
    if type(id)~='string' or not (accept or Feedback.accept_crosshair)(id) then return end
    local style=widget.style and widget.style[id]
    local content=pass.content_id and widget.content[pass.content_id] or widget.content
    if not style or not content or style.visible==false or content.visible==false or
            (pass.visibility_function and not pass.visibility_function(content,style)) then return end
    local size,offset=style.size,style.offset or {0,0,0}
    if not size or size[1]<=0 or size[2]<=0 then return end
    local material=content[pass.value_id or 'value_id'] or pass.value
    if not material then return end
    local w,h=size[1],size[2]
    local x,y=offset[1] or 0,offset[2] or 0
    -- Stock crosshair pivot has zero area; all feedback passes align centrally.
    x,y=x-w*.5,y-h*.5
    local pivot=style.pivot or {w*.5,h*.5}
    local px,py=pivot[1] or w*.5,pivot[2] or h*.5
    local angle=style.angle or 0
    local c,s=math.cos(angle),math.sin(angle)
    local cx=x+px+c*(w*.5-px)-s*(h*.5-py)
    local cy=y+py+s*(w*.5-px)+c*(h*.5-py)
    return {x=cx,y=cy,w=w,h=h,c=c,s=s,layer=offset[3] or 1,
        material=material,uvs=style.uvs or {{0,0},{1,1}},color=style.color or {255,255,255,255}}
end
function Feedback.scale(percent)
    if type(percent)~='number' or percent~=percent or math.abs(percent)==math.huge then percent=70 end
    return math.max(25,math.min(150,percent))/100
end
function Feedback.pixel_scale(distance,character_scale,percent)
    -- Match the accepted XR reticle's 41-pixel atlas, including its size caps.
    return math.max(.105,math.min(.84,distance/character_scale*.049))*character_scale/41*Feedback.scale(percent)
end
function Feedback.install(mod,presentation,tracking)
    local api={}
    local scale_percent,published,hidden
    function api.update_scale()
        scale_percent=Feedback.scale(mod.get and mod:get('vr_crosshair_scale'))*100
        -- A stereo cinematic publishes zero so the viewer draws no reticle.
        if hidden then scale_percent=0 end
        if published==scale_percent then return end
        local io_api=Mods and Mods.lua and Mods.lua.io
        if not io_api then return end
        local file=io_api.open('./../mods/darktidevr/darktidevr_crosshair_scale.flag','w')
        if not file then return end
        local ok,result=pcall(file.write,file,string.format('%.0f\n',scale_percent))
        file:close()
        if ok and result then published=scale_percent end
    end
    local previous_setting_changed=mod.on_setting_changed
    mod.on_setting_changed=function(id,...)
        if previous_setting_changed then previous_setting_changed(id,...) end
        if id=='vr_crosshair_scale' then api.update_scale() end
    end
    function api.set_hidden(value)
        hidden=value==true
        api.update_scale()
    end
    api.update_scale()
    local source,source_t,alpha,world,gui,failed
    function api.destroy()
        if gui then pcall(World.destroy_gui,world,gui) end
        world,gui,source,source_t=nil,nil,nil,nil
    end
    local function hide() if gui then Gui.set_visible(gui,false) end end
    mod:hook_safe('HudElementCrosshair','update',function(self,dt,t,renderer,settings)
        source,source_t,alpha=self,Managers.time:time('main'),settings and settings.alpha_multiplier or 1
    end)
    mod:hook_safe('HudElementCrosshair','destroy',function(self)
        if source==self then api.destroy();failed=nil end
    end)
    local function draw(game_world,eye,rotation)
        local hud=Managers.ui and Managers.ui._hud
        local t=Managers.time:time('main')
        if failed or not source or source._parent~=hud or not source_t or t<source_t or t-source_t>.1 or
                presentation.mode~=1 or not tracking.authoring_enabled or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) or
                not hud._currently_visible_elements or not hud._currently_visible_elements.HudElementCrosshair then hide();return end
        local widget=source._widget
        if not widget or widget.visible==false or widget.content.visible==false then hide();return end
        local point=presentation.controller_aim.cached_reticle_target()
        if not point then hide();return end
        local position=point:unbox()
        local player=Managers.player:local_player_safe(1)
        if not player then hide();return end
        local scale=presentation.calibrated_character_scale(player)
        local distance=presentation.controller_aim.reticle_distance or Vector3.distance(eye,position)
        local pixels=Feedback.pixel_scale(distance,scale,scale_percent)
        if world~=game_world then
            local owner,stamp,opacity=source,source_t,alpha
            api.destroy();world=game_world;source,source_t,alpha=owner,stamp,opacity
        end
        if not gui then gui=World.create_world_gui(world,Matrix4x4.identity(),1,1,'immediate') end
        Gui.set_visible(gui,true)
        local right,up,forward=Quaternion.right(rotation),Quaternion.up(rotation),Quaternion.forward(rotation)
        for _,pass in ipairs(widget.passes) do
            local q=Feedback.quad(pass,widget)
            if q then
                local tm=Matrix4x4.identity()
                Matrix4x4.set_right(tm,-right*q.c+up*q.s)
                Matrix4x4.set_up(tm,right*q.s+up*q.c)
                Matrix4x4.set_forward(tm,-forward)
                Matrix4x4.set_translation(tm,position+right*(q.x*pixels)-up*(q.y*pixels))
                Gui2.bitmap_3d(gui,q.material,nil,tm,q.layer,
                    {position_offset=Vector3(-q.w*pixels*.5,-q.h*pixels*.5,0),
                    size=Vector3(q.w*pixels,q.h*pixels,0),
                    color=Color(q.color[1]*(alpha or 1),q.color[2],q.color[3],q.color[4]),
                    uv00=Vector2(q.uvs[2][1],q.uvs[2][2]),
                    uv11=Vector2(q.uvs[1][1],q.uvs[1][2]),snap_pixel_positions=false})
            end
        end
    end
    function api.draw(...)
        if not published then api.update_scale() end
        local ok,err=pcall(draw,...)
        if not ok then
            api.destroy();failed=true
            mod:warning('DARKTIDEVR_CROSSHAIR feedback_error=%s',tostring(err))
        end
    end
    return api
end
return Feedback
