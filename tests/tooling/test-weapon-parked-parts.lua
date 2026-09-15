local Parked=dofile(assert(arg[1]))
local receiver='content/weapons/player/ranged/galvanic_rifle/attachments/receiver_01/receiver_01'
-- Pure selection.
local meshes=assert(Parked.hidden_meshes(receiver,nil,true,66))
assert(#meshes==44 and meshes[1]==23 and meshes[4]==26 and meshes[5]==27 and meshes[36]==58 and meshes[37]==59 and meshes[40]==62 and meshes[44]==66,'galvanic rounds, clip and case')
assert(Parked.hidden_meshes(receiver,'shoot_hit_scan',true,66),'hidden while firing')
assert(Parked.hidden_meshes(receiver,'reload_state',true,66)==nil,'shown during reload')
assert(Parked.hidden_meshes(receiver,nil,false,66)==nil,'stock arms visible: untouched')
assert(Parked.hidden_meshes('content/other',nil,true,66)==nil,'other attachments untouched')
assert(#Parked.hidden_meshes(receiver,nil,true,60)==38,'clamped to the mesh count (23-26, 27-58, 59-60)')
-- Adapter: hides while the arms are hidden, shows again for reload, weapon
-- change and stock arms.
local visibility,unit_names,alive={}, {}, {}
Unit={alive=function(u) return alive[u] end,get_data=function(u,k) return unit_names[u] end,
    num_meshes=function() return 66 end,
    set_mesh_visibility=function(u,i,v) visibility[u]=visibility[u] or {}; visibility[u][i]=v end}
local attachment,rig={}, {}
alive[attachment]=true; unit_names[attachment]=receiver
local action=nil
local slot={unit_3p=rig,attachments_by_unit_3p={[rig]={attachment}}}
local extensions={unit_data_system={read_component=function() return {wielded_slot='slot_secondary'} end},
    visual_loadout_system={_equipment={slot_secondary=slot}},
    weapon_system={running_action_settings=function() return action end}}
ScriptUnit={has_extension=function(_,name) return extensions[name] end}
local arms_hidden=true
local lines={}
local api=Parked.install({info=function(_,f,...) lines[#lines+1]=string.format(f,...) end},
    {body_proxy={hides_source_slot=function(slot_name) return slot_name=='slot_body_arms' and arms_hidden end}})
local player={}
api.update(player)
assert(visibility[attachment][27]==false and visibility[attachment][66]==false and visibility[attachment][60]==false and visibility[attachment][22]==nil,'rounds, clip and case hidden')
assert(lines[1]:find('parked_hidden',1,true) and #lines==1)
action={kind='reload_state'}
api.update(player)
assert(visibility[attachment][27]==true and visibility[attachment][66]==true,'reload shows the rounds')
action=nil
api.update(player)
assert(visibility[attachment][40]==false,'hidden again after reload')
assert(#lines==1,'logged once')
arms_hidden=false
api.update(player)
assert(visibility[attachment][40]==true,'stock arms: shown')
arms_hidden=true; api.update(player)
slot.attachments_by_unit_3p={[rig]={}}
api.update(player)
assert(visibility[attachment][40]==true,'weapon change: shown')
-- A failure restores what was hidden.
slot.attachments_by_unit_3p={[rig]={attachment}}
api.update(player)
assert(visibility[attachment][40]==false)
extensions.weapon_system={running_action_settings=function() error('boom') end}
api.update(player)
assert(visibility[attachment][40]==true,'failure restores visibility')
assert(lines[#lines]:find('failed=',1,true))
print('weapon_parked_parts=pass selection reload arms weapon_change failure')
