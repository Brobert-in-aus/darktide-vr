local Sound=dofile(assert(arg[1]))
local callback
local unit={}
local effect={_unit=unit,_is_local_unit=true}
local source={nodes={muzzle=true}}
local target={nodes={muzzle=true}}
local slot={equipped=true,wieldable=true,unit_1p=source,unit_3p=target,
    attachments_by_unit_1p={},attachment_id_lookup_1p={},
    attachments_by_unit_3p={},attachment_id_lookup_3p={}}
local first_person=false
local loadout={_unit=unit,_fx_extension=effect,_equipment={slot_primary=slot},
    _first_person_extension={is_in_first_person_mode=function() return first_person end}}
local player={player_unit=unit}
Managers={player={local_player=function() return player end}}
Unit={alive=function(u) return not u.dead end,has_node=function(u,node) return u.nodes[node]==true end}
ScriptUnit={has_extension=function(owner,name) assert(owner==unit and name=='visual_loadout_system'); return loadout end}
local presentation={mode=1,is_first_person_body_mode=function(mode) return mode=='shooting_range' end}
local tracking={body_visibility_enabled=true}
local mode='shooting_range'
Sound.install({hook_require=function(_,path,fn) fn({}) end,
    hook=function(_,class,name,fn) assert(name=='register_sound_source'); callback=fn end},
    presentation,tracking,function() return mode end)
local observed
local function original(self,name,parent,attachments,lookup,node,extra)
    assert(self==effect and name=='slot_primarymuzzle' and node=='muzzle' and extra=='extra')
    observed={parent,attachments,lookup}; return 'result',nil,3
end
local function call(expected)
    local a,b,c=callback(original,effect,'slot_primarymuzzle',source,
        slot.attachments_by_unit_1p,slot.attachment_id_lookup_1p,'muzzle','extra')
    assert(a=='result' and b==nil and c==3)
    assert(observed[1]==expected,'Weapon sound registered on the wrong visual owner')
    local suffix=expected==target and '3p' or '1p'
    assert(observed[2]==slot['attachments_by_unit_'..suffix] and observed[3]==slot['attachment_id_lookup_'..suffix])
end
call(target)
for _,condition in ipairs({'disabled','flat','mode','foreign','nonlocal','retired','first_person','unequipped','unwieldable','dead','missing_node'}) do
    tracking.body_visibility_enabled=condition~='disabled'
    presentation.mode=condition=='flat' and 0 or 1
    mode=condition=='mode' and 'unknown' or 'shooting_range'
    player.player_unit=condition=='foreign' and {} or unit
    effect._is_local_unit=condition~='nonlocal'
    loadout._fx_extension=condition=='retired' and {} or effect
    first_person=condition=='first_person'
    slot.equipped=condition~='unequipped'; slot.wieldable=condition~='unwieldable'
    target.dead=condition=='dead'; target.nodes.muzzle=condition~='missing_node'
    call(source)
end
target.nodes.muzzle=false
local attachment={nodes={muzzle=true}}
slot.attachments_by_unit_3p[target]={attachment}
slot.attachment_id_lookup_3p[target]='root'
call(target)
slot.attachment_id_lookup_3p[target]=nil; call(source)
slot.attachment_id_lookup_3p[target]='root'
attachment.dead=true; call(source)
target.nodes.muzzle=true; call(source)
target.nodes.muzzle=false
attachment.dead=nil
source.dead=true; call(source); source.dead=nil
local wrong_metadata={}
callback(function(_,_,parent,attachments) assert(parent==source and attachments==wrong_metadata) end,
    effect,'slot_primarymuzzle',source,wrong_metadata,slot.attachment_id_lookup_1p,'muzzle')
local old_has=ScriptUnit.has_extension
ScriptUnit.has_extension=function() error('retired engine accessor') end
call(source)
ScriptUnit.has_extension=old_has
-- An exception from the stock registrar itself must still propagate once.
local calls=0
local ok,reason=pcall(callback,function() calls=calls+1; error('stock registrar failed') end,
    effect,'slot_primarymuzzle',source,slot.attachments_by_unit_1p,slot.attachment_id_lookup_1p,'muzzle')
assert(not ok and calls==1 and tostring(reason):find('stock registrar failed',1,true))
if arg[2] then
    local file=assert(io.open(arg[2]..'/scripts/extension_systems/visual_loadout/player_unit_visual_loadout_extension.lua','r'))
    local source_text=file:read('*a'); file:close()
    local first=assert(source_text:find('local function _register_fx_sources(',1,true))
    local last=assert(source_text:find('\nlocal function _move_fx_sources(',first,true))
    local register=assert(loadstring(source_text:sub(first,last-1)..'\nreturn _register_fx_sources'))()
    effect.register_sound_source=function(self,name,parent,attachments,lookup,node)
        callback(function(_,_,actual) observed=actual end,self,name,parent,attachments,lookup,node)
    end
    effect.register_vfx_spawner=function(_,name,parent) assert(parent==target) end
    local sources=register(effect,slot,{muzzle='muzzle'},'slot_primary',false)
    assert(observed==target and sources.muzzle=='slot_primarymuzzle')
    print('weapon_sound_stock=pass actual initial registrar selects the owned VR item')
end
print('weapon_sound_owner=pass exact_slot attachments local_owner fallback return_values stock_error')
