local Layout={}
local function pack(...) return {n=select('#',...),...} end

function Layout.resize(view,height)
    local scene=view._ui_scenegraph
    local layout=view._settings_grid_layout
    if not scene or not layout or type(height)~='number' or height~=height or height==math.huge or height<400 then return false end
    local bottom=height-70
    if layout.bottom==bottom then return false end
    layout.bottom=bottom
    local background=scene.background
    if background then
        local old=background.size[2]
        local size=math.max(100,bottom-background.world_position[2])
        for _,name in ipairs({'grid_mask','grid_interaction','scrollbar'}) do
            local node=scene[name]
            if node then view:_set_scenegraph_size(name,nil,size+node.size[2]-old) end
        end
        view:_set_scenegraph_size('background',nil,size)
    end
    return true
end

function Layout.install(mod)
    local Scenegraph=require('scripts/managers/ui/ui_scenegraph')
    local function resize(view)
        if not view._ui_scenegraph or not view._ui_scenegraph.screen then return false end
        local size=Scenegraph.size_scaled(view._ui_scenegraph,'screen',view._render_scale)
        return Layout.resize(view,size[2])
    end
    local function refresh(view)
        for _,name in ipairs({'_category_content_grid','_settings_content_grid'}) do
            local grid=view[name]
            if grid then grid:on_resolution_modified(view._render_scale) end
        end
    end
    local function update_layout(view)
        if view._settings_grid_layout and view._settings_header_height and resize(view) then
            view:_set_options_header_layout(view._settings_header_height,
                view._settings_header_spacing,view._options_tab_indicator~=nil)
            refresh(view)
            if mod.info then mod:info('DARKTIDEVR_OPTIONS layout_bottom=%.1f scale=%.3f',
                view._settings_grid_layout.bottom,view._render_scale) end
        end
    end
    -- DMF can construct this persistent view before XR changes the render
    -- extent, without receiving a resolution callback when it opens later.
    mod:hook_safe('DMFOptionsView','update',update_layout)
    mod:hook('DMFOptionsView','_set_options_header_layout',function(func,self,...)
        local changed=resize(self)
        local result=pack(func(self,...))
        if changed then refresh(self) end
        return unpack(result,1,result.n)
    end)
    mod:hook('DMFOptionsView','on_resolution_modified',function(func,self,...)
        local result=pack(func(self,...))
        update_layout(self)
        return unpack(result,1,result.n)
    end)
end
return Layout
