-- A semantic controller hold contributes to stock ChatManager input only.
-- The binding mapper owns release-before-activation and remap cancellation.
local Input={}
function Input.install(mod,presentation,observation,runtime)
    local Talk=mod:io_dofile('darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_push_to_talk_input')
    local context,bindings=presentation.gameplay_context,presentation.controller_bindings
    local state={sample=0,needs_release=true}
    local function valid(owner,sample)
        return state.owner==owner and state.sample==sample and owner~=nil and
            observation.gameplay_input_active==true and presentation.mode==1 and
            owner.revision==bindings.revision and owner.generation==observation.last_transport_generation and
            owner.recenter==observation.head_recenter_generation and
            owner.mode==runtime.mode() and owner.world==runtime.world() and
            presentation.is_first_person_body_mode(owner.mode) and
            presentation.gameplay_input_owner[1]==owner.handler and
            presentation.gameplay_input_owner[2]==owner.unit and
            context.local_input_unit(owner.handler,Managers and Managers.player)==owner.unit and
            context.input_service_enabled(owner.input) and
            not context.ui_blocks_gameplay(Managers and Managers.ui) and
            (not (Managers and Managers.imgui) or not context.ui_blocks_gameplay(Managers.imgui))
    end
    local api={}
    function api.sample(handler,unit,input,enabled,held,mode,world)
        state.sample=state.sample+1
        state.owner=nil
        if enabled~=true or unit==nil then state.needs_release=true;return end
        local down=bit.band(held or 0,8388608)~=0
        if not down then state.needs_release=false;return end
        if not state.needs_release then
            state.owner={handler=handler,unit=unit,input=input,mode=mode,world=world,
                revision=bindings.revision,generation=observation.last_transport_generation,
                recenter=observation.head_recenter_generation}
        end
    end
    function api.cancel()state.sample=state.sample+1;state.owner=nil;state.needs_release=true end
    mod:hook('ChatManager','update',function(func,self,...)
        local owner,sample=state.owner,state.sample
        local function current()
            local ok,live=pcall(function()
                return valid(owner,sample) and context.input_service_enabled(self._input_service)
            end)
            if ok and live==true then return true end
            if owner~=nil and state.owner==owner and state.sample==sample then
                state.owner=nil;state.needs_release=true
            end
            return false
        end
        return Talk.with_input(self,owner~=nil and current(),current,func,...)
    end)
    return api
end
return Input
