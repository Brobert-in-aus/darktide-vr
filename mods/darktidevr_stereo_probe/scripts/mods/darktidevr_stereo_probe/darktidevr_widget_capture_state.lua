-- Separate GUI-owned pass caches for immediate popup capture. Stock materials
-- and retained IDs never move between renderers. Not a live hook.
local State={}
State.__index=State
local supported={texture=true,texture_uv=true,rotated_texture=true,text=true,rect=true}
local function pack(...) return {n=select('#',...),...} end

function State.new(renderer,pass_types)
    assert(renderer and pass_types)
    return setmetatable({renderer=renderer,pass_types=pass_types,entries={}},State)
end

function State:admit(widgets,settings)
    if self.destroyed or self.failed or self.drawing then return nil,'unavailable' end
    if type(widgets)~='table' or type(settings)~='table' then return nil,'invalid_input' end
    if settings.force_retained_mode or (self.renderer.render_settings and
        self.renderer.render_settings.force_retained_mode) then return nil,'retained_mode' end
    local list,seen={},{}
    for _,widget in ipairs(widgets) do
        if type(widget)~='table' or type(widget.passes)~='table' or
            type(widget.style)~='table' or type(widget.content)~='table' then return nil,'invalid_widget' end
        for _,pass in ipairs(widget.passes) do
            if #list>=128 then return nil,'too_many_passes' end
            if seen[pass] then return nil,'duplicate_pass' end
            if type(pass)~='table' then return nil,'invalid_pass' end
            local kind=pass.pass_type
            if not supported[kind] or not self.pass_types[kind] or
                type(self.pass_types[kind].init)~='function' then return nil,'unsupported_pass' end
            local data=pass.data
            if type(data)~='table' then return nil,'invalid_pass_data' end
            if pass.retained_mode or data.retained_id or data.retained_ids then return nil,'retained_mode' end
            local style=pass.style_id and widget.style[pass.style_id] or widget.style
            local content=pass.content_id and widget.content[pass.content_id] or widget.content
            if type(style)~='table' or type(content)~='table' then return nil,'invalid_pass_input' end
            if style.material~=nil and type(style.material)~='string' then return nil,'foreign_material' end
            if kind=='texture' or kind=='texture_uv' or kind=='rotated_texture' then
                local value=content[pass.value_id or 'value_id']
                if value~=nil and type(value)~='string' then return nil,'foreign_material' end
            end
            seen[pass]=true
            list[#list+1]={pass=pass,widget=widget}
        end
    end
    if #list==0 then return nil,'empty_widgets' end
    return list,seen
end

function State:release(entry)
    -- Cleanup receives a detached descriptor; even a failing stock destructor
    -- cannot leave source pass.data bound to capture-owned state.
    local descriptor={}
    for key,value in pairs(entry.pass) do descriptor[key]=value end
    descriptor.pass_type=entry.kind
    descriptor.data=entry.data
    local destroy=self.pass_types[entry.kind].destroy
    if destroy then destroy(descriptor,self.renderer) end
end

function State:draw(widgets,settings,draw,...)
    local list,seen=self:admit(widgets,settings)
    if not list then return false,seen end
    assert(type(draw)=='function','invalid capture draw')
    self.drawing=true
    local swaps={}
    local args=pack(...)
    local result=pack(pcall(function()
        for pass,entry in pairs(self.entries) do
            if not seen[pass] or entry.kind~=pass.pass_type or entry.value_id~=pass.value_id then
                self.entries[pass]=nil
                self:release(entry)
            end
        end
        for _,item in ipairs(list) do
            local pass=item.pass
            local entry=self.entries[pass]
            if not entry then
                local kind=pass.pass_type
                local data=self.pass_types[kind].init(pass,item.widget.content,item.widget.style) or {}
                assert(type(data)=='table','invalid capture pass initialization')
                entry={pass=pass,kind=kind,value_id=pass.value_id,data=data}
                self.entries[pass]=entry
            end
            swaps[#swaps+1]={pass=pass,data=pass.data}
            pass.data=entry.data
        end
        return draw(unpack(args,1,args.n))
    end))
    for i=#swaps,1,-1 do swaps[i].pass.data=swaps[i].data end
    self.drawing=nil
    if not result[1] then self.failed=true;error(result[2],0) end
    return true,unpack(result,2,result.n)
end

-- Call before destroying the capture renderer/GUI. An entry is retired before
-- its destructor, and all later entries still get a cleanup attempt.
function State:destroy()
    if self.destroyed then return end
    assert(not self.drawing,'cannot destroy active capture state')
    self.destroyed=true
    local errors={}
    for pass,entry in pairs(self.entries) do
        self.entries[pass]=nil
        local ok,err=pcall(self.release,self,entry)
        if not ok then errors[#errors+1]=tostring(err) end
    end
    if #errors>0 then error(table.concat(errors,'; '),0) end
end

return State
