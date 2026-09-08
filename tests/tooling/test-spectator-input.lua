bit=require('bit')
local Spectator,Bindings,Context=dofile(arg[1]),dofile(arg[2]),dofile(arg[3])
local Camera={}; local Modes={observer=5,dead=3,first_person=4}
package.loaded['scripts/managers/player/player_game_states/camera_handler']=Camera
package.loaded['scripts/managers/player/player_game_states/utilities/camera_modes']=Modes
package.loaded['scripts/managers/input/input_utils']={apply_color_to_input_text=function(s) return s end}
Color={ui_input_color=function() return 0 end}
local hooks,settings={},{}
local mod={get=function(_,id) return settings[id] end,localize=function(_,id) return id end,
    hook=function(_,class,name,callback)
        hooks[class]=hooks[class] or {}; assert(not hooks[class][name]); hooks[class][name]=callback
    end}
local original_bindings=Bindings.install(mod)
original_bindings.sample(true,0)
original_bindings.sample(true,1)
local physical,generation,status,x,y,usable=0,1,0,0,0,true
local enabled,ui,null,stock=true,false,false,false
local samples=0
local player={}
local camera={_player=player,_mode=Modes.observer}
player.camera_handler=camera -- Deliberately no player_unit.
Managers={player={local_player=function() return player end},ui={using_input=function() return ui end}}
local input={get=function(_,name) return name=='spectate_next' and stock or name=='other' and 'untouched' end,
    is_null_service=function() return null end}
Spectator.install(mod,Bindings,Context,function(active)
    samples=samples+1
    return status,active and physical or 0,generation,x,y,usable
end,function() return enabled end)
local seen,last_input,during_update
local function step(owner,service,fail)
    seen=nil
    local result,empty,tail=hooks[Camera].update(function(self,dt,t,orientation,selected)
        assert(self==(owner or camera) and dt==.01 and t==10 and orientation=='orientation')
        seen=selected:get('spectate_next') or false
        last_input=selected
        assert(selected:get('other')=='untouched')
        if during_update then during_update(selected) end
        if fail then error('stock camera error') end
        return 'target',nil,99
    end,owner or camera,.01,10,'orientation',service or input)
    assert(result=='target' and empty==nil and tail==99); return seen
end
assert(not step()); assert(not step())
physical=32; assert(step(),'Default A press did not reach camera without a character')
assert(not last_input:get('spectate_next'),'Retained camera proxy outlived its update')
local old_proxy=last_input
physical=0;step();physical=32
input.identity='original'
function input:has(name)assert(self==input);return name=='spectate_next' end
during_update=function(selected)
    assert(not old_proxy:get('spectate_next'),'old proxy revived during a newer edge')
    assert(selected.identity=='original' and selected:has('spectate_next'),'stock service members were not forwarded')
    ui=true;assert(not selected:get('spectate_next'));ui=false
    null=true;assert(not selected:get('spectate_next'));null=false
    camera._mode=Modes.first_person;assert(not selected:get('spectate_next'));camera._mode=Modes.observer
    local original_player=camera._player;camera._player={};assert(not selected:get('spectate_next'));camera._player=original_player
    hooks[Camera].update(function()
        assert(not selected:get('spectate_next'),'remote nested update inherited the outer edge')
    end,{_player={},_mode=Modes.observer},.01,10,'orientation',input)
    assert(selected:get('spectate_next'),'outer scope was not restored')
    local nested_ok=pcall(hooks[Camera].update,function()error('nested camera failure')end,
        {_player={},_mode=Modes.observer},.01,10,'orientation',input)
    assert(not nested_ok and selected:get('spectate_next'))
    hooks[Camera].update(function()end,camera,.01,10,'orientation',input)
    assert(not selected:get('spectate_next'),'new local sample revived an old scoped edge')
end
assert(step());during_update=nil
assert(not step(),'Held button cycled repeatedly')
assert(original_bindings.held==1,'Camera sampler changed combat mapper')
local hint=hooks.HudElementSpectatorText._get_cycle_input_text
assert(hint(function() return 'stock hint' end,{})=='[vr_prompt_a]')
physical=0; step(); stock=true; assert(step(),'Stock spectator input was suppressed'); stock=false
-- Foreign and retiring handlers never sample or consume the current route.
local before=samples
assert(not step({_player={},_mode=Modes.observer})); assert(samples==before)
assert(not step(setmetatable({}, {__index=function() error('retired camera') end}))); assert(samples==before)
-- Every blocked context drains inherited levels and requires a new press.
for _,block in ipairs({'ui','null','disabled','normal','failed','publisher','replacement','player','service'}) do
    physical=0; step(); physical=32; assert(step())
    local other_service
    if block=='ui' then ui=true
    elseif block=='null' then null=true
    elseif block=='disabled' then enabled=false
    elseif block=='normal' then camera._mode=Modes.first_person
    elseif block=='failed' then status=2
    elseif block=='publisher' then generation=generation+1; status=3
    elseif block=='replacement' then camera={_player=player,_mode=Modes.observer}; player.camera_handler=camera
    elseif block=='player' then player={camera_handler=camera}; camera._player=player
    elseif block=='service' then other_service={get=input.get,is_null_service=input.is_null_service} end
    assert(not step(nil,other_service),'Blocked context delivered: '..block)
    ui=false; null=false; enabled=true; camera._mode=Modes.observer; status=0
    assert(not step(),'Inherited hold retriggered: '..block)
    physical=0; step(); physical=32; assert(step(),'Failed to rearm: '..block)
end
-- A remap follows the jump action and refreshes the cached spectator hint.
physical=0; step()
settings.vr_bind_a='unbound'; settings.vr_bind_right_trigger='jump'
mod.on_setting_changed('vr_bind_a'); mod.on_setting_changed('vr_bind_right_trigger')
physical=1; assert(not step(),'Remap converted a held input into a camera edge')
physical=0; step(); physical=1; assert(step())
assert(hint(function() return 'stock hint' end,{})=='[vr_prompt_right_trigger]')
local hud={}; local refresh=hooks.HudElementSpectatorText.update
local function draw(self) local changed=self._update_spectator_text; self._update_spectator_text=nil; return changed end
assert(refresh(draw,hud)); assert(not refresh(draw,hud))
enabled=false; assert(refresh(draw,hud)); assert(hint(function() return 'stock hint' end,hud)=='stock hint')
enabled=true
settings.vr_bind_right_trigger='unbound'; mod.on_setting_changed('vr_bind_right_trigger')
assert(refresh(draw,hud)); assert(hint(function() return 'stock hint' end,hud)=='stock hint')
-- Directional remaps use the same thresholds and turning exclusion as combat.
settings.vr_bind_right_stick_up='jump'; mod.on_setting_changed('vr_bind_right_stick_up')
physical=0; y=0; step(); y=.8; assert(step()); assert(not step())
usable=false; assert(not step()); usable=true; assert(not step())
y=0; step(); y=.8; assert(step())
-- Stock errors propagate without leaving a global input replacement installed.
y=0; step(); y=.8
assert(not pcall(step,nil,nil,true))
assert(not last_input:get('spectate_next'),'failed stock update retained its injected edge')
assert(not step())
-- Optional native export: old producer versions remain a stock-only fallback.
local ffi=require('ffi')
local missing=Spectator.native_reader(ffi,setmetatable({}, {__index=function() error('missing export') end}))
assert(missing(true)==2)
local reader=Spectator.native_reader(ffi,{dtvr_read_spectator_input=function(active,p,h,r,s,m,g,stick)
    assert(active==1); h[0]=32; g[0]=7; stick[0]=.5; stick[1]=-.25; stick[2]=1; return 0
end})
local code,held,gen,sx,sy,valid=reader(true)
assert(code==0 and held==32 and gen==7 and sx==.5 and sy==-.25 and valid)
print('PASS: scoped spectator edges, ownership, neutral rearming, remaps, hints and optional native reader')
