-- Sample physical wheel ownership before turning and virtual stick bindings.
-- The stock wheel coordinator owns HUD state and deferred communication.
local Input={}
function Input.install(mod,presentation,observation,runtime)
    local root='darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/'
    local function load(name)return mod:io_dofile(root..'darktidevr_'..name)end
    local bindings,context=presentation.controller_bindings,presentation.gameplay_context
    local state={frame=0}
    local function same(owner,handler,unit,input,mode,world)
        return owner and owner.handler==handler and owner.unit==unit and owner.input==input and
            owner.mode==mode and owner.world==world and owner.revision==bindings.revision and
            owner.generation==observation.last_transport_generation and
            owner.recenter==observation.head_recenter_generation
    end
    local function current(owner)
        return owner~=nil and state.owner==owner and state.eligible==true and
            observation.gameplay_input_active==true and observation.right_aim_usable==true and
            presentation.mode==1 and presentation.is_first_person_body_mode(runtime.mode()) and
            same(owner,presentation.gameplay_input_owner[1],presentation.gameplay_input_owner[2],
                owner.input,runtime.mode(),runtime.world()) and
            context.local_input_unit(owner.handler,Managers and Managers.player)==owner.unit and
            context.input_service_enabled(owner.input) and
            not context.ui_blocks_gameplay(Managers and Managers.ui) and
            (not (Managers and Managers.imgui) or not context.ui_blocks_gameplay(Managers.imgui))
    end
    local wheel=load('communication_wheel').install(mod,{
        Gesture=load('communication_gesture'),Context=load('communication_context'),
        Navigation=load('communication_navigation'),current=current,
        hud_owner=function(hud,owner)return hud._parent and hud._parent:player_unit()==owner.unit end,
        dimensions=function()return RESOLUTION_LOOKUP.width,RESOLUTION_LOOKUP.height end,
        vector=function(x,y,z)return Vector3(x,y,z)end,
        defer=function(fn)Managers.state.game_mode:register_physics_safe_callback(fn)end,
    })
    local api={}
    function api.sample(handler,unit,input,enabled,physical,mode,world)
        local held=bindings.physical_hold('communication_wheel',physical,mode)
        state.frame=state.frame+1
        if not same(state.owner,handler,unit,input,mode,world) then
            state.owner={handler=handler,unit=unit,input=input,mode=mode,world=world,
                revision=bindings.revision,generation=observation.last_transport_generation,
                recenter=observation.head_recenter_generation}
        end
        state.eligible=enabled==true and unit~=nil and observation.right_aim_usable==true
        return wheel.sample(state.frame,state.owner,state.eligible,held,
            observation.right_stick_x,observation.right_stick_y)
    end
    function api.cancel()
        state.eligible=false;state.owner=nil
        wheel.cancel()
    end
    return api
end
return Input
