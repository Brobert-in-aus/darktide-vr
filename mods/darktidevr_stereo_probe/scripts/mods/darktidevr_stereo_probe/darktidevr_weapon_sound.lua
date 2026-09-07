-- Initial stock sound registration uses the 1P item even with 3P equipment.
-- Resolve only an owned local VR slot; later stock move/unregister stays stock.
local Sound={}
local function contains_node(parent,attachments,lookup,node)
    if lookup~=nil and type(lookup)~='table' then return false end
    local found=Unit.has_node(parent,node)
    for owner,children in pairs(attachments or {}) do
        for _,child in ipairs(children) do
            -- Stock registration visits every supplied attachment, including
            -- when the root also has this node. Do not pass a retiring tree.
            if not child or not Unit.alive(child) then return false end
            if Unit.has_node(child,node) then
                if not lookup or lookup[owner]==nil then return false end
                found=true
            end
        end
    end
    return found
end
function Sound.install(mod,presentation,tracking,mode_name)
    local function destination(effect,parent,attachments,lookup,node)
        if presentation.mode~=1 or not tracking.body_visibility_enabled or
                not presentation.is_first_person_body_mode(mode_name()) or
                not effect._is_local_unit or type(node)~='string' or node=='' then return end
        local player=Managers.player and Managers.player:local_player(1)
        local unit=player and player.player_unit
        if not unit or effect._unit~=unit or not Unit.alive(unit) then return end
        local loadout=ScriptUnit.has_extension(unit,'visual_loadout_system')
        if not loadout or loadout._unit~=unit or loadout._fx_extension~=effect or
                not loadout._first_person_extension or
                loadout._first_person_extension:is_in_first_person_mode()~=false then return end
        for _,slot in pairs(loadout._equipment or {}) do
            if slot.equipped and slot.wieldable and slot.unit_1p==parent and
                    slot.attachments_by_unit_1p==attachments and slot.attachment_id_lookup_1p==lookup then
                local target=slot.unit_3p
                if parent and Unit.alive(parent) and target and Unit.alive(target) and
                        contains_node(target,slot.attachments_by_unit_3p,slot.attachment_id_lookup_3p,node) then
                    return target,slot.attachments_by_unit_3p,slot.attachment_id_lookup_3p
                end
                return
            end
        end
    end
    mod:hook_require('scripts/extension_systems/fx/player_unit_fx_extension',function(class)
        mod:hook(class,'register_sound_source',function(func,self,name,parent,attachments,lookup,node,...)
            local ok,target,target_attachments,target_lookup=pcall(destination,self,parent,attachments,lookup,node)
            if ok and target then
                return func(self,name,target,target_attachments,target_lookup,node,...)
            end
            return func(self,name,parent,attachments,lookup,node,...)
        end)
    end)
end
return Sound
