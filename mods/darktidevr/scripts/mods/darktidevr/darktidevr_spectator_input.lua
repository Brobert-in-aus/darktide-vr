-- Local camera-only input. No character liveness requirement, combat cache
-- writes, target selection or camera-orientation override belongs here.
local Spectator = {}
function Spectator.native_reader(ffi,library)
    local ok,read=pcall(function() return library.dtvr_read_spectator_input end)
    if not ok or not read then return function() return 2,0,0 end end
    local pressed,held,released,sequence,generation=ffi.new('unsigned long long[1]'),
        ffi.new('unsigned long long[1]'),ffi.new('unsigned long long[1]'),
        ffi.new('unsigned long long[1]'),ffi.new('unsigned long long[1]')
    local movement,stick=ffi.new('float[2]'),ffi.new('float[3]')
    return function(enabled)
        local status=read(enabled and 1 or 0,pressed,held,released,sequence,movement,generation,stick)
        return status,tonumber(held[0]),tonumber(generation[0]),tonumber(stick[0]),tonumber(stick[1]),stick[2]==1
    end
end
function Spectator.install(mod, Bindings, Context, sample, allowed)
    local CameraModes=require('scripts/managers/player/player_game_states/utilities/camera_modes')
    local bindings=Bindings.install(mod)
    local owner=setmetatable({}, {__mode='v'})
    local available=false
    local mode
    local input_scope
    local sample_serial=0
    local function pack(...)return {n=select('#',...),...}end
    -- `scope` leads so the stock arguments can be a tail: a handler that
    -- names them drops whatever the engine adds beyond them, which is the
    -- shape that lost the bindings' ninth argument for a day (17 September).
    local function run(scope,func,self,...)
        if not input_scope and not scope then return func(self,...) end
        local previous=input_scope
        input_scope=scope
        local result=pack(pcall(func,self,...))
        input_scope=previous
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    local function current(self)
        local player=Managers.player:local_player(1)
        return player and self._player==player and player.camera_handler==self
    end
    local function owns(self)
        local ok,result=pcall(current,self)
        return ok and result==true
    end
    local function admitted(self,input)
        return owns(self) and (self._mode==CameraModes.observer or self._mode==CameraModes.dead) and
            Context.input_service_enabled(input) and not Context.ui_blocks_gameplay(Managers and Managers.ui) and
            allowed()==true
    end
    mod:hook(require('scripts/managers/player/player_game_states/camera_handler'),'update',
        function(func,self,dt,t,orientation,input,...)
            if not owns(self) then return run(nil,func,self,dt,t,orientation,input,...) end
            local enabled=admitted(self,input)
            sample_serial=sample_serial+1
            local changed=owner[1]~=self or owner[2]~=input or owner[3]~=self._player or mode~=self._mode
            owner[1],owner[2],owner[3],mode=self,input,self._player,self._mode
            local status,physical,generation,x,y,usable=sample(enabled and not changed)
            available=enabled and status==0
            local pressed=bindings.sample(available and not changed,physical,x,y,usable,generation,'combat')
            if bit.band(pressed,32)==0 then return run(nil,func,self,dt,t,orientation,input,...) end
            -- Limit the extra edge to this exact stock consumer and service.
            -- Other input calls, including combat, keep their original owner.
            local scope={mode=self._mode,sample=sample_serial}
            local proxy=setmetatable({get=function(_,name,...)
                local value=input:get(name,...)
                if name=='spectate_next' and input_scope==scope and sample_serial==scope.sample and available and
                    owner[1]==self and owner[2]==input and
                    self._mode==scope.mode and admitted(self,input) then return true end
                return value
            end},{__index=function(_,name)
                local value=input[name]
                if type(value)=='function' then return function(_,...)return value(input,...)end end
                return value
            end})
            return run(scope,func,self,dt,t,orientation,proxy,...)
        end)
    local function hint_enabled()
        return available and owner[1] and owner[2] and admitted(owner[1],owner[2])
    end
    mod:hook('HudElementSpectatorText','_get_cycle_input_text',function(func,self,...)
        if not hint_enabled() then return func(self,...) end
        local controls=bindings.controls_for_action('jump')
        if not controls[1] then return func(self,...) end
        local InputUtils=require('scripts/managers/input/input_utils')
        return InputUtils.apply_color_to_input_text(
            '['..mod:localize('vr_prompt_'..controls[1])..']',Color.ui_input_color(255,true))
    end)
    local revisions=setmetatable({}, {__mode='k'})
    mod:hook('HudElementSpectatorText','update',function(func,self,...)
        local revision=bindings.revision*2+(hint_enabled() and 1 or 0)
        if revisions[self]~=revision then
            revisions[self]=revision; self._update_spectator_text=true
        end
        return func(self,...)
    end)
    return {bindings=bindings}
end
return Spectator
