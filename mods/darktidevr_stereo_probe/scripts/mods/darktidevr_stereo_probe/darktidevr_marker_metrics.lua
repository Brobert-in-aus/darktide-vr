-- Bounded, opt-in comparison of GUI input geometry, not rendered pixel extents.
local Metrics = {}
local state = {budget=0, pending={}, scope=nil}
local specs = {
    script_draw_bitmap = {position=2,size=3,token=1,color=4},
    script_draw_bitmap_uv = {position=2,size=3,token=1,color=5},
    script_draw_bitmap_3d = {position=3,size=5,transform=2,token=1,color=6,layer=4},
    script_draw_text = {position=4,size=5,font=2,token=1,secondary=3,color=6,options=7},
    script_draw_text_3d = {position=5,size=7,font=2,transform=4,token=1,secondary=3,color=8,options=9,layer=6},
    draw_rect = {position=1,size=2,logical=true,color=3},
    draw_rect_rotated = {position=2,size=1,angle=3,pivot=4,logical=true,color=5},
    draw_slug_icon = {position=3,size=4,logical=true,token=1,secondary=2,color=5},
    draw_slug_icon_rotated = {position=4,size=3,angle=5,pivot=6,logical=true,token=1,secondary=2,color=7},
    draw_slug_picture = {position=2,size=3,logical=true,token=1,color=4},
    draw_triangle = {unsupported=true},
    draw_circle = {unsupported=true},
    draw_video = {unsupported=true},
}
local function pack(...) return {n=select('#',...),...} end
local function component(value, index)
    return value and tonumber(value[index]) or 0
end
local function finite(value)
    return value == value and value ~= math.huge and value ~= -math.huge
end
local function capture(name, spec, renderer, ...)
    local scope = state.scope
    scope.total = scope.total + 1
    if spec.unsupported then scope.unsupported = scope.unsupported + 1 end
    if #scope.rows >= 128 then scope.truncated = true; return end
    local args = {...}
    local scale = spec.logical and (renderer.scale or 1) or 1
    local position, size = args[spec.position], args[spec.size]
    local row = {name=name, x=component(position,1)*scale,
        y=component(position,2)*scale, width=component(size,1)*scale,
        height=component(size,2)*scale, font=spec.font and args[spec.font] or 0,
        angle=spec.angle and args[spec.angle] or 0,
        scale=renderer.scale or 1, alpha=renderer.render_settings and
            renderer.render_settings.alpha_multiplier or 1}
    row.color_alpha=args[spec.color] and component(args[spec.color],1) or 255
    -- Compare ordering inputs separately from geometry. The 3D APIs have an
    -- explicit layer; position[3] is not their layer. Do not apply XY scale or
    -- predict primitive-specific clamps/native GUI behavior here.
    if spec.layer then
        row.layer=assert(tonumber(args[spec.layer]),'missing explicit GUI layer')
    else
        row.layer=component(position,3)
    end
    row.start_layer=renderer.render_settings and renderer.render_settings.start_layer or 0
    if spec.font then
        -- Query stock layout at the final script-call font/box scale, not the
        -- logical widget size. This is still not proof of final shaded pixels.
        local width,height,minimum=assert(state.text_size,'text layout API unavailable')(
            renderer,args[spec.token],args[spec.secondary],args[spec.font],size,args[spec.options],true)
        assert(type(width)=='number' and type(height)=='number' and width>=0 and height>=0 and
            minimum and tonumber(minimum[1]) and tonumber(minimum[2]),'invalid text layout')
        row.text_width,row.text_height=width,height
        row.text_min_x,row.text_min_y=tonumber(minimum[1]),tonumber(minimum[2])
    end
    if spec.pivot then
        row.pivot_x=component(args[spec.pivot],1)*scale
        row.pivot_y=component(args[spec.pivot],2)*scale
    end
    if spec.transform and args[spec.transform] then
        local tm = args[spec.transform]
        local x, z = Matrix4x4.x(tm), Matrix4x4.z(tm)
        row.xx,row.xy,row.xz = assert(x.x),assert(x.y),assert(x.z)
        row.zx,row.zy,row.zz = assert(z.x),assert(z.y),assert(z.z)
        local translation=Matrix4x4.translation(tm)
        row.tx,row.ty,row.tz=assert(translation.x),assert(translation.y),assert(translation.z)
    end
    for key,value in pairs(row) do
        if key ~= 'name' and (type(value) ~= 'number' or not finite(value)) then
            error('Non-finite GUI metric')
        end
    end
    -- Keep exact call identity only for this bounded in-memory comparison.
    -- Text, material names and resource identifiers are never logged.
    row.token,row.secondary=args[spec.token],args[spec.secondary]
    scope.rows[#scope.rows+1] = row
end
local function changed(a,b,key)
    return math.abs((a[key] or 0)-(b[key] or 0)) > 0.001
end
local function compare(left,right)
    local summary = {matched=0,shape=0,font=0,scale=0,alpha=0,color_alpha=0,kind=0,text_layout=0,text_measured=0,
        layer=0,start_layer=0,maximum_layer_delta=0,
        maximum_anchor_delta=0,left=left.total,right=right.total,
        incomplete=left.truncated or right.truncated or left.errors>0 or
            right.errors>0 or left.unsupported>0 or right.unsupported>0}
    for index=1,math.min(#left.rows,#right.rows) do
        local a,b = left.rows[index],right.rows[index]
        if a.name ~= b.name or a.token ~= b.token or a.secondary ~= b.secondary then
            summary.kind=summary.kind+1
            summary.incomplete=true
        else
            summary.matched=summary.matched+1
            if changed(a,b,'width') or changed(a,b,'height') or
                    changed(a,b,'angle') or changed(a,b,'pivot_x') or changed(a,b,'pivot_y') or
                    changed(a,b,'xx') or changed(a,b,'xy') or changed(a,b,'xz') or
                    changed(a,b,'zx') or changed(a,b,'zy') or changed(a,b,'zz') then summary.shape=summary.shape+1 end
            if changed(a,b,'font') then summary.font=summary.font+1 end
            if changed(a,b,'scale') then summary.scale=summary.scale+1 end
            if changed(a,b,'alpha') then summary.alpha=summary.alpha+1 end
            if changed(a,b,'color_alpha') then summary.color_alpha=summary.color_alpha+1 end
            if changed(a,b,'layer') then summary.layer=summary.layer+1 end
            if changed(a,b,'start_layer') then summary.start_layer=summary.start_layer+1 end
            summary.maximum_layer_delta=math.max(summary.maximum_layer_delta,math.abs(a.layer-b.layer))
            if a.text_width~=nil and b.text_width~=nil then
                summary.text_measured=summary.text_measured+1
                if changed(a,b,'text_width') or changed(a,b,'text_height') or
                    changed(a,b,'text_min_x') or changed(a,b,'text_min_y') then
                    summary.text_layout=summary.text_layout+1
                end
            end
            summary.maximum_anchor_delta=math.max(summary.maximum_anchor_delta,
                math.abs(a.x-b.x),math.abs(a.y-b.y),
                math.abs((a.tx or 0)-(b.tx or 0)),math.abs((a.ty or 0)-(b.ty or 0)),
                math.abs((a.tz or 0)-(b.tz or 0)))
        end
    end
    if left.total ~= right.total then summary.incomplete=true end
    return summary
end
local function invoke(wrapper, renderer, draw, ...)
    if wrapper then return wrapper(renderer,draw,...) end
    return draw(...)
end
function Metrics.start(budget)
    budget=tonumber(budget) or 60
    if not finite(budget) then budget=60 end
    state.budget=math.min(240,math.max(2,math.floor(budget)))
    state.pending={}
end
function Metrics.stop() state.budget=0; state.pending={} end
function Metrics.draw(renderer,kind,owner,t,eye,wrapper,draw,...)
    if state.budget <= 0 then return invoke(wrapper,renderer,draw,...) end
    state.budget=state.budget-1
    local previous=state.scope
    local scope={renderer=renderer,rows={},total=0,errors=0,unsupported=0}
    state.scope=scope
    local result=pack(pcall(invoke,wrapper,renderer,draw,...))
    state.scope=previous
    if not result[1] then
        state.pending[owner]=nil
        if state.budget==0 then state.pending={} end
        error(result[2],0)
    end
    if eye==1 then
        state.pending[owner]={kind=kind,t=t,scope=scope}
    else
        local primary=state.pending[owner]
        state.pending[owner]=nil
        if primary and primary.kind==kind and primary.t==t then
            local summary=compare(primary.scope,scope)
            if state.report then pcall(state.report,kind,summary) end
        elseif state.unmatched then pcall(state.unmatched,kind) end
    end
    if state.budget==0 then
        state.pending={}
        if state.finished then pcall(state.finished) end
    end
    return unpack(result,2,result.n)
end
function Metrics.install(mod,renderer_class)
    state.text_size=renderer_class.text_size
    for name,spec in pairs(specs) do
        if renderer_class[name] then
            mod:hook(renderer_class,name,function(func,renderer,...)
                if state.scope and state.scope.renderer==renderer then
                    local ok=pcall(capture,name,spec,renderer,...)
                    if not ok then state.scope.errors=state.scope.errors+1 end
                end
                return func(renderer,...)
            end)
        end
    end
    state.report=function(kind,s)
        mod:info('DARKTIDEVR_MARKER_METRICS kind=%s left=%d right=%d matched=%d shape=%d font=%d scale=%d alpha=%d color_alpha=%d kind_mismatch=%d max_anchor_delta=%.3f incomplete=%s text_layout=%d text_measured=%d layer=%d start_layer=%d max_layer_delta=%.3f input_geometry_only=true',
            kind,s.left,s.right,s.matched,s.shape,s.font,s.scale,s.alpha,s.color_alpha,s.kind,
            s.maximum_anchor_delta,tostring(s.incomplete),s.text_layout,s.text_measured,
            s.layer,s.start_layer,s.maximum_layer_delta)
    end
    state.unmatched=function(kind)
        mod:info('DARKTIDEVR_MARKER_METRICS kind=%s unmatched=true input_geometry_only=true',kind)
    end
    state.finished=function() mod:info('DARKTIDEVR_MARKER_METRICS complete=true') end
    mod:command('dtvr_marker_metrics','Compare the next 60 stereo marker draws',function()
        Metrics.start(60)
        mod:info('DARKTIDEVR_MARKER_METRICS started=true pass_budget=60')
    end)
    mod:command('dtvr_marker_metrics_off','Stop marker geometry measurements',Metrics.stop)
    return Metrics
end
return Metrics
