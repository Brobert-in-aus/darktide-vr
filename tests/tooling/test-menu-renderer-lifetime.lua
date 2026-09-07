-- Execute the actual optional crafting/system draw hooks without game rendering.
local file=assert(io.open(arg[1],"r"))
local source=file:read("*all"); file:close()
local first=assert(source:find("-- CraftingView.init and CraftingView.draw",1,true))
local last=assert(source:find("\n-- Keep controller/menu back semantic",first,true))
local hooks={}
local resource={base_render_pass="resource",render_pass_flag="resource_flag"}
local active=true
presentation={world_menu_active=function() return active end,
    ensure_menu_resource=function() return resource end,
    menu_resource_invalidated_views=setmetatable({}, {__mode="k"}),
    menu_resource_pass_states=setmetatable({}, {__mode="k"}),
    invalidate_retained_widgets=function() return 0 end}
ui_menu_resource_redirect_requested=true
UIRenderer={clear_render_pass_queue=function() end,add_render_pass=function() end}
mod={info=function() end,hook=function(_,class,name,fn)
    hooks[class]=hooks[class] or {}; hooks[class][name]=fn
end}
local crafting="scripts/ui/views/crafting_view/crafting_view"
local system="scripts/ui/views/system_view/system_view"
package.loaded[crafting]=crafting; package.loaded[system]=system
assert(loadstring(source:sub(first,last-1)))()
for class,field in pairs({[crafting]="_ui_renderer",[system]="_ui_default_renderer"}) do
    local original={}
    local view={[field]=original}
    local failure={reason="stock draw failed"}
    local ok,err=pcall(hooks[class].draw,function(self,dt,t,input,layer)
        assert(self==view and self[field]==resource)
        assert(dt==.1 and t==2 and input=="input" and layer==9)
        error(failure)
    end,view,.1,2,"input",9)
    assert(not ok and err==failure,"Stock draw error was replaced or hidden")
    assert(view[field]==original,"Failed draw retained temporary renderer: "..class)
    -- A subsequent draw starts with the real source and nesting restores the
    -- enclosing renderer before the outer hook restores the original one.
    local calls=0
    local value=hooks[class].draw(function(self)
        calls=calls+1; assert(self[field]==resource)
        hooks[class].draw(function(inner)
            calls=calls+1; assert(inner==self and inner[field]==resource)
        end,self,.1,3,"input",9)
        assert(self[field]==resource,"Nested draw retired its enclosing renderer")
        return 17
    end,view,.1,3,"input",9)
    assert(value==17 and calls==2 and view[field]==original)
    for _,gate in ipairs({"flag","inactive","unavailable"}) do
        ui_menu_resource_redirect_requested=gate~="flag"
        active=gate~="inactive"
        presentation.ensure_menu_resource=function() return gate~="unavailable" and resource or nil end
        local result=hooks[class].draw(function(self)
            assert(self[field]==original,"Bypassed draw changed renderer")
            return 23
        end,view,.1,4,"input",9)
        assert(result==23 and view[field]==original)
    end
    ui_menu_resource_redirect_requested=true; active=true
    presentation.ensure_menu_resource=function() return resource end
end
local renderer={name="crafting",base_render_pass="original",render_pass_flag="original_flag"}
Managers={time={time=function() return 10 end}}
local begin_pass,end_pass=hooks[UIRenderer].begin_pass,hooks[UIRenderer].end_pass
local function restored()
    assert(renderer.base_render_pass=="original" and renderer.render_pass_flag=="original_flag",
        "Failed pass retained temporary renderer fields")
    assert(#presentation.menu_resource_pass_states[renderer]==0,"Failed pass retained stack entry")
end
local failure={reason="pass failed"}
local ok,err=pcall(begin_pass,function(self,value)
    assert(self==renderer and value==7 and self.base_render_pass=="resource")
    error(failure)
end,renderer,7)
assert(not ok and err==failure); restored()
local function begin()
    assert(begin_pass(function(self) assert(self.base_render_pass=="resource"); return 11 end,renderer)==11)
end
begin()
ok,err=pcall(end_pass,function(self,value)
    assert(self==renderer and value==8); error(failure)
end,renderer,8)
assert(not ok and err==failure); restored()
-- A failed queue setup must be retried within the same UI frame.
presentation.menu_resource_clear_time=nil
local add_calls=0
UIRenderer.add_render_pass=function() add_calls=add_calls+1; error(failure) end
ok,err=pcall(begin_pass,function() error("Stock pass ran after setup failure") end,renderer)
assert(not ok and err==failure); restored()
UIRenderer.add_render_pass=function() add_calls=add_calls+1 end
begin(); assert(add_calls==2,"Failed queue setup was treated as complete")
assert(end_pass(function() return 13 end,renderer)==13); restored()
begin(); begin()
end_pass(function() end,renderer)
assert(renderer.base_render_pass=="resource" and #presentation.menu_resource_pass_states[renderer]==1)
end_pass(function() end,renderer); restored()
-- Diagnostic drawing can fail before stock end_pass; it still retires our fields.
begin(); presentation.world_menu_target_probe_requested=true
Vector3=function() return {} end; Color=function() return {} end
UIRenderer.draw_rect=function() error(failure) end
ok,err=pcall(end_pass,function() error("Stock end ran after diagnostic failure") end,renderer)
assert(not ok and err==failure); restored()
print("menu_renderer_lifetime=pass stock_errors recovery nested_draw bypass pass_cleanup retry")
