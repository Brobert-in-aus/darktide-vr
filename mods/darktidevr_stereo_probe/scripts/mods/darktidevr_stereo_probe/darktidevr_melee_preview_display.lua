-- Local, opt-in first-light swing guide. It never runs physics or attacks.
local Display={}
function Display.startup_requested(io_api)
    if not io_api then return false end
    local flag=io_api.open('./../mods/darktidevr_stereo_probe/darktidevr_melee_preview.flag','r')
    if not flag then return false end
    local ok,value=pcall(flag.read,flag,32)
    flag:close()
    return ok and type(value)=='string' and value:match('^%s*enabled%s*$')~=nil
end
function Display.install(mod,presentation,tracking)
    local Preview=mod:io_dofile('darktidevr_stereo_probe/scripts/mods/darktidevr_stereo_probe/darktidevr_melee_preview')
    local api={enabled=false}
    local world,gui,failed
    function api.destroy()
        if gui then pcall(World.destroy_gui,world,gui) end
        world,gui=nil,nil
        api.last_preview=nil
    end
    local function hide(clear)
        if gui then Gui.set_visible(gui,false) end
        if clear then api.last_preview=nil end
    end
    local function vector(p) return Vector3(p.x,p.y,p.z) end
    local function line(a,b,eye,color,width)
        local delta=b-a
        local length=Vector3.length(delta)
        if length<.0001 then return end
        local right=delta/length
        local across=Vector3.cross(right,eye-(a+b)*.5)
        if Vector3.length(across)<.0001 then return end
        local up=Vector3.normalize(across)
        local tm=Matrix4x4.identity()
        Matrix4x4.set_right(tm,right)
        Matrix4x4.set_up(tm,up)
        Matrix4x4.set_forward(tm,Vector3.cross(up,right))
        Matrix4x4.set_translation(tm,a)
        Gui.rect_3d(gui,tm,Vector2(0,-width*.5),1,Vector2(length,width),color)
    end
    local function update()
        if not api.enabled or failed then hide(true); return end
        if presentation.mode~=1 or not tracking.authoring_enabled or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) then hide(true); return end
        -- Startup opt-in can precede the network connection. local_player()
        -- calls Network.peer_id(), whose engine assertion bypasses Lua pcall.
        local player=Managers.player and Managers.player:local_player_safe(1)
        local unit=player and player.player_unit
        if not unit or not Unit.alive(unit) then hide(true); return end
        local side='right'
        if presentation.weapon_hand_roles then side=presentation.weapon_hand_roles.physical('dominant') end
        if side~='left' and side~='right' then hide(true); return end
        if not tracking[side..'_aim_usable'] then hide(true); return end
        local extension=ScriptUnit.has_extension(unit,'weapon_system')
        if not extension then hide(true); return end
        local t=Managers.time:time('gameplay')
        local result,reason=Preview.context(extension,presentation,t)
        if not result then
            local prior=api.last_preview
            hide(reason~='action_running' or not prior or t<prior.t or t-prior.t>1)
            return
        end
        if world~=extension._world then api.destroy(); world=extension._world end
        -- The path is redrawn at the latest hand pose each frame. Retained
        -- mode keeps every old rectangle and accumulates a blue trail.
        if not gui then gui=World.create_world_gui(world,Matrix4x4.identity(),1,1,'immediate') end
        api.last_preview={name=result.action_name,t=t,unit=unit,
            weapon=extension._weapons[extension._inventory_component.wielded_slot]}
        Gui.set_visible(gui,true)
        local eye=extension._first_person_component.position
        for _,path in ipairs(result.paths) do
            local color=Color(150,100,220,255)
            for i=2,#path do line(vector(path[i-1].tip),vector(path[i].tip),eye,color,.008) end
            -- Two backward wings indicate travel direction at the final sample.
            local tip=vector(path[#path].tip)
            local delta=tip-vector(path[#path-1].tip)
            if Vector3.length(delta)>.0001 then
                local direction=Vector3.normalize(delta)
                local wing=Vector3.cross(direction,eye-tip)
                if Vector3.length(wing)>.0001 then
                    wing=Vector3.normalize(wing)*.035
                    local back=tip-direction*.09
                    line(tip,back+wing,eye,color,.008)
                    line(tip,back-wing,eye,color,.008)
                end
            end
        end
    end
    function api.update()
        local ok,err=pcall(update)
        if not ok then
            failed=true; api.destroy()
            mod:warning('DARKTIDEVR_MELEE preview_error=%s damage=false',tostring(err))
        end
    end
    mod:hook_safe('ActionSweep','start',function(action,settings,t)
        local prior=api.last_preview
        if not api.enabled or not prior or action._player_unit~=prior.unit then return end
        api.last_preview=nil
        if action._weapon~=prior.weapon or type(t)~='number' or t~=t or
                math.abs(t)==math.huge or t<prior.t or t-prior.t>1 then return end
        mod:info('DARKTIDEVR_MELEE preview_action=%s started_action=%s matched=%s preview_age=%.4f server_process=%s damage_verified=false',
            tostring(prior.name),tostring(settings.name),tostring(prior.name==settings.name),
            t-prior.t,tostring(action._is_server==true))
    end)
    local function set_enabled(enabled)
        failed=nil; api.enabled=enabled
        if not enabled then api.destroy() end
        mod:info('DARKTIDEVR_MELEE preview=%s damage=false obstruction_tested=false',
            enabled and 'on' or 'off')
    end
    mod.toggle_melee_preview=function()
        set_enabled(not api.enabled)
        mod:echo(api.enabled and 'Melee swing preview on' or 'Melee swing preview off')
    end
    mod:command('dtvr_melee_preview_on','Show the first stock light swing direction',function()
        set_enabled(true)
    end)
    mod:command('dtvr_melee_preview_off','Hide the stock swing preview',function()
        set_enabled(false)
    end)
    local requested_ok,requested=pcall(Display.startup_requested,
        Mods and Mods.lua and Mods.lua.io)
    if requested_ok and requested then set_enabled(true) end
    return api
end
return Display
