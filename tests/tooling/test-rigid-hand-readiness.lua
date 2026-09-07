local f=assert(io.open(arg[1],'r')); local source=f:read('*all'); f:close()
local first=assert(source:find('local function disable_visual_colliders(',1,true))
local last=assert(source:find('\nlocal function place_rigid_hand(',first,true))
local updates,surfaces=0,0
local collision_writes=0
state={source_unit={}}
Unit={alive=function(u) return not u.dead end,
    num_actors=function(u) return u.actor_count or #(u.actors or {}) end,
    actor=function(u,i) return u.actors[i] end}
Actor={set_collision_enabled=function(a,value) a.collision=value; collision_writes=collision_writes+1 end,
    set_scene_query_enabled=function(a,value) a.query=value; collision_writes=collision_writes+1 end}
show_rigid_hand_surface=function(hand) assert(hand.unit); surfaces=surfaces+1 end
local update,disable=assert(loadstring(source:sub(first,last-1)..'\nreturn update_rigid_hand,disable_visual_colliders'))()
assert(not pcall(disable,state.source_unit),'Gameplay body admitted to visual collision cleanup')
local function hand()
    local spawner={unit={actor_count=3,actors={[1]={collision=true,query=true},[3]={collision=true,query=true}}},complete=false,fail=false}
    function spawner:update(dt,t)
        assert(dt==.02 and t==10); updates=updates+1
        if self.fail then error('stream failed') end
    end
    function spawner:spawned() return self.complete end
    function spawner:spawned_character_unit() return self.unit end
    return {side='left',profile_spawner=spawner},spawner
end
local h,s=hand()
assert(update(h,.02,10)==nil and not h.ready and h.unit==nil and surfaces==0,
    'An existing unit was accepted before the spawner completed initialization')
assert(update(h,.02,10)==nil and updates==2,'Pending spawner stopped receiving updates')
s.complete=true
assert(update(h,.02,10)==s.unit and h.ready and h.unit==s.unit)
assert(updates==3 and surfaces==1)
assert(collision_writes==4 and not s.unit.actors[1].collision and not s.unit.actors[3].query,
    'Ready visual hand retained collision/query actors')
for _=1,100 do assert(update(h,.02,10)==s.unit) end
assert(updates==3 and surfaces==1,'Ready-hand update repeated the placement visibility pass')
assert(collision_writes==4,'Stable visual hand repeated collider cleanup')
s.unit.dead=true
assert(update(h,.02,10)==nil,'Dead unit was returned as ready')
h,s=hand(); s.complete=true; s.unit=nil
assert(update(h,.02,10)==nil and not h.ready)
s.unit={}; assert(update(h,.02,10)==s.unit and h.ready)
h,s=hand(); s.fail=true
local before=updates
assert(update(h,.02,10)==nil and h.failure and not h.ready)
assert(update(h,.02,10)==nil and updates==before+1,'Failed streaming retried every frame')
-- Replacement ownership gets a fresh hand record and can initialize normally.
h,s=hand(); s.complete=true
assert(update(h,.02,10)==s.unit and h.ready and not h.failure)
-- A cached ready flag cannot authorize reads of a hand unit that has retired.
BodyProxy={}
state={hands_only=true,ready=true}
rigid_hands={left={ready=true,unit={}},right={ready=true,unit={}}}
local active_first=assert(source:find('function BodyProxy.active()',1,true))
local active_last=assert(source:find('\nfunction BodyProxy.check_rigid_hands_before_render()',active_first,true))
assert(loadstring(source:sub(active_first,active_last-1)))()
local hide_first=assert(source:find('function BodyProxy.hides_source_slot(',1,true))
local hide_last=assert(source:find('\nfunction BodyProxy.consume_ready_transition()',hide_first,true))
assert(loadstring(source:sub(hide_first,hide_last-1)))()
assert(BodyProxy.active() and BodyProxy.hides_source_slot('slot_body_arms'))
for _,side in ipairs({'left','right'}) do
    local live=rigid_hands[side].unit
    live.dead=true
    assert(not BodyProxy.active() and not BodyProxy.rigid_hands_active(),
        'Retired hand retained active proxy ownership')
    assert(not BodyProxy.hides_source_slot('slot_body_arms') and
        not BodyProxy.hides_source_slot('slot_gear_upperbody'))
    rigid_hands[side].unit=nil
    assert(not BodyProxy.active(),'Missing ready hand retained active proxy ownership')
    live.dead=false; rigid_hands[side].unit=live
    assert(BodyProxy.active())
end
-- Exercise the real post-update visibility seam, including nil proxy return.
f=assert(io.open(arg[2],'r')); local main=f:read('*all'); f:close()
local seam_first=assert(main:find('        local proxy_unit = presentation.body_proxy and',1,true))
local seam_last=assert(main:find('\n        local ik_start =',seam_first,true))
local refreshes,logs=0,{}
local transition=false
BodyProxy.update=function()
    if state.ready then return rigid_hands.left.unit or rigid_hands.right.unit end
end
BodyProxy.consume_ready_transition=function() local value=transition; transition=false; return value end
presentation={body_proxy=BodyProxy,body_proxy_active=false,is_first_person_body_mode=function() return true end,
    current_game_mode_name=function() return 'shooting_range' end,
    safe_apply_body_visibility=function(_,_,force) assert(force); refreshes=refreshes+1 end}
controller_observation={body_visibility_enabled=true,body_visibility_update_frame=10}
ScriptUnit={has_extension=function(_,name) assert(name=='visual_loadout_system'); return {} end}
mod={info=function(_,format,...) logs[#logs+1]=string.format(format,...) end}
local tick=assert(loadstring('return function(self,player_unit,local_player,dt,t)\n'..
    main:sub(seam_first,seam_last-1)..'\nend'))()
tick({_world={}},'player',{},.02,10)
assert(refreshes==1 and logs[1]:find('visual_proxy=active',1,true))
tick({_world={}},'player',{},.02,10)
assert(refreshes==1,'Stable active proxy repeated forced visibility work')
rigid_hands.left.unit.dead=true
tick({_world={}},'player',{},.02,10)
assert(refreshes==2 and logs[2]:find('visual_proxy=inactive',1,true),
    'Hand loss did not immediately refresh source visibility')
rigid_hands.left.unit=nil; rigid_hands.right.unit=nil; state.ready=false
tick({_world={}},'player',{},.02,10)
assert(refreshes==2,'Stable inactive proxy repeated forced visibility work')
rigid_hands.left.unit={}; rigid_hands.right.unit={}; state.ready=true; transition=true
tick({_world={}},'player',{},.02,10)
assert(refreshes==3 and logs[3]:find('visual_proxy=active',1,true))
-- Complete teardown can jump directly from active to no proxy at all.
rigid_hands.left.unit=nil; rigid_hands.right.unit=nil; state.ready=false
tick({_world={}},'player',{},.02,10)
assert(refreshes==4 and logs[4]:find('visual_proxy=inactive',1,true))
-- The update path retires both gloves after loss of a previously ready hand,
-- then quarantines that owner instead of retrying allocation every frame.
local update_first=assert(source:find('function BodyProxy.update(',1,true))
assert(loadstring(source:sub(update_first,active_first-1)))()
local world,owner,profile={},{},{}
local destroys,polls=0,0
player_profile=function() return profile end
safe_destroy=function()
    destroys=destroys+1
    for key in pairs(state) do state[key]=nil end
    rigid_hands={left={},right={}}
end
spawn_rigid_hands=function(w,u,p)
    state.world,state.source_unit,state.profile,state.hands_only=w,u,p,true
    rigid_hands={left={ready=true,unit={}},right={ready=true,unit={}}}
end
update_rigid_hand=function(hand)
    polls=polls+1
    if hand.unit and Unit.alive(hand.unit) then return hand.unit end
end
spawn_rigid_hands(world,owner,profile)
state.ready=true; rigid_hands.left.unit.dead=true
assert(BodyProxy.update(world,owner,{},true,.02,10,true)==nil)
assert(destroys==1 and state.failed_source_unit==owner and not BodyProxy.active())
assert(rigid_hands.right.unit==nil,'Surviving glove remained beside fallback source hands')
local polled=polls
assert(BodyProxy.update(world,owner,{},true,.02,10,true)==nil and polls==polled and destroys==1)
assert(BodyProxy.update(world,owner,{},false,.02,10,true)==nil and state.failed_source_unit==nil)
assert(BodyProxy.update(world,owner,{},true,.02,10,true) and BodyProxy.active())
print('rigid hand waits for stock spawn readiness, initializes visibility once and retains failed-owner quarantine')
