-- Light hand aim uses stock target selection and trajectory correction. It
-- does not impersonate a gamepad or rotate the headset/locomotion camera.
local Assist={}
function Assist.limit(raw,wanted)
    if not wanted then return raw end
    local angle=Quaternion.angle(raw,wanted)
    if angle~=angle or angle>math.rad(5) then return raw end
    return Quaternion.lerp(raw,wanted,angle>1e-6 and math.min(.5,math.rad(1)/angle) or 0)
end
function Assist.install(mod,presentation,tracking)
    local SmartTargeting=require('scripts/utilities/smart_targeting')
    local api={}
    local observed,observed_t,observed_weapon,observed_epoch,sequence,epoch,cached,owner,weapon
    local pending=false
    local flag=Mods and Mods.lua and Mods.lua.io and Mods.lua.io.open(
        './../mods/darktidevr_stereo_probe/darktidevr_aim_assist_light.flag','r')
    if flag then pending=flag:read(32):match('^%s*enabled%s*$')~=nil;flag:close() end
    function api.observe(extension,t)
        observed,observed_t=extension,t
        observed_weapon=extension._weapon_extension and extension._weapon_extension:weapon_template()
        observed_epoch=tracking.last_transport_generation
        if pending then
            local data=Managers.save:account_data()
            if data and data.input_settings then
                data.input_settings.controller_aim_assist='new_slim'
                Managers.save:queue_save()
                Managers.event:trigger('event_on_input_settings_changed')
                pending=false
                mod:info('DARKTIDEVR_AIM_ASSIST setting=Light saved=true source=user_request')
            end
        end
    end
    local target=presentation.weapon_aim_target
    local function reset() sequence,epoch,cached,owner,weapon=nil,nil,nil,nil,nil end
    local function resolve(rotation)
        local data=Managers.save and Managers.save:account_data()
        local side=presentation.weapon_hand_roles.physical('dominant')
        local t=Managers.time:time('gameplay')
        if not rotation or not data or not data.input_settings or data.input_settings.controller_aim_assist~='new_slim' or
                (side~='left' and side~='right') or
                presentation.mode~=1 or not tracking.authoring_enabled or not tracking[side..'_aim_usable'] or
                presentation.gameplay_context.ui_blocks_gameplay(Managers.ui) or
                Managers.input:is_using_gamepad() or DevParameters.disable_aim_assist or
                not observed or observed_epoch~=tracking.last_transport_generation or
                not observed_t or t<observed_t or t-observed_t>.1 then reset();return rotation end
        local player=Managers.player:local_player_safe(1)
        if not player or observed._unit~=player.player_unit or not Unit.alive(player.player_unit) then reset();return rotation end
        local ext=observed._weapon_extension
        local template=ext and ext:weapon_template()
        local ranged=false
        for _,key in ipairs(template and template.keywords or {}) do if key=='ranged' then ranged=true end end
        local targeting=observed:targeting_data()
        if not ranged or template~=observed_weapon or not targeting or not targeting.unit or not Unit.alive(targeting.unit) or
                (observed._buff_extension and observed._buff_extension:has_keyword('enable_auto_aim')) then reset();return rotation end
        if owner==observed and weapon==template and sequence==tracking.last_sequence and
                epoch==tracking.last_transport_generation and cached then return cached:unbox() end
        local settings=SmartTargeting.smart_targeting_template(t,observed._weapon_action_component,
            observed._combat_ability_action_component,observed._grenade_ability_action_component)
        local wanted=observed:assisted_hitscan_trajectory(settings,template,rotation)
        local result=Assist.limit(rotation,wanted)
        cached=QuaternionBox(result)
        owner,weapon,sequence,epoch=observed,template,tracking.last_sequence,tracking.last_transport_generation
        return result
    end
    presentation.weapon_aim_target=function(role)
        local position,rotation=target(role)
        if role~='dominant' then return position,rotation end
        local ok,result=pcall(resolve,rotation)
        if not ok then
            reset()
            if not api.failed then mod:warning('DARKTIDEVR_AIM_ASSIST fallback=%s',tostring(result));api.failed=true end
            return position,rotation
        end
        return position,result
    end
    return api
end
return Assist
