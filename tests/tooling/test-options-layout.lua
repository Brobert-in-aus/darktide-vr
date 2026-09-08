local Layout=dofile(assert(arg[1]))
local hooks={}
local height=1080
package.loaded['scripts/managers/ui/ui_scenegraph']={size_scaled=function(_,_,scale)
    assert(scale==1.1);return {1920,height}
end}
local function hook(_,class,method,fn)
    assert(class=='DMFOptionsView');assert(not hooks[method]);hooks[method]=fn
end
Layout.install({hook=hook,hook_safe=hook})
local scene={screen={},background={size={500,774},world_position={0,236}},
    grid_mask={size={516,790}},grid_interaction={size={516,790}},scrollbar={size={10,774}},
    settings_grid_background={size={1000,790}}}
local refreshes=0
local grid={on_resolution_modified=function(_,scale) assert(scale==1.1);refreshes=refreshes+1 end}
local view={_ui_scenegraph=scene,_settings_grid_layout={bottom=1010},_render_scale=1.1,
    _category_content_grid=grid,_settings_content_grid=grid,_settings_header_height=140,
    _settings_header_spacing=20}
function view:_set_scenegraph_size(name,width,h) assert(width==nil);scene[name].size[2]=h end
local function stock_header(self,h,spacing,tabs)
    scene.settings_grid_background.size[2]=self._settings_grid_layout.bottom-60-h-spacing-(tabs and 48 or 0)
    return 'stock',nil,3
end
function view:_set_options_header_layout(...)
    return hooks._set_options_header_layout(stock_header,self,...)
end
local function check(expected,settings_top)
    assert(view._settings_grid_layout.bottom==expected-70)
    assert(scene.background.size[2]==expected-70-236)
    assert(scene.grid_mask.size[2]==scene.background.size[2]+16)
    assert(scene.grid_interaction.size[2]==scene.grid_mask.size[2])
    assert(scene.scrollbar.size[2]==scene.background.size[2])
    assert(scene.settings_grid_background.size[2]==expected-70-settings_top)
end
view:_set_options_header_layout(140,20,false);check(1080,220)
height=2094
local a,b,c=view:_set_options_header_layout(140,20,false)
assert(a=='stock' and b==nil and c==3)
check(2094,220);assert(refreshes==2,'both grid caches need refreshing')
view:_set_options_header_layout(140,20,true);check(2094,268)
view:_set_options_header_layout(140,20,true);check(2094,268) -- no cumulative padding growth
view._options_tab_indicator={}
height=1080
local stock_called=false
hooks.on_resolution_modified(function() stock_called=true end,view)
assert(stock_called);check(1080,268);assert(refreshes==4)
height=2160
hooks.on_resolution_modified(function() end,view);check(2160,268)
height=2400
hooks.update(view);check(2400,268) -- persistent view opened after XR resize
local prior=refreshes
hooks.update(view);assert(refreshes==prior,'unchanged updates must not rebuild grids')
for _,invalid in ipairs({0,-1,0/0,math.huge}) do assert(not Layout.resize(view,invalid)) end
assert(not Layout.resize({},2094))
print('Desktop/tall canvas, both scroll regions, footer clearance, tabs and resolution changes pass')
