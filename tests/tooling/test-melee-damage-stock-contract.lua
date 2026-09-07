-- Optional cached-source audit: execute stock sweep boundaries with engine
-- fixtures. This neither loads the mod nor establishes live damage authority.
local root=assert(arg[1], 'cached stock source root required')
local path=root..'/scripts/extension_systems/weapon/actions/action_sweep.lua'
local f=assert(io.open(path,'r')); local source=f:read('*a'); f:close()
local first=assert(source:find('ActionSweep._process_hit =',1,true))
local last=assert(source:find('\nActionSweep._modify_sweep_position =',first,true))
local Sweep={}
local target,player,actor={},{},{}
local breed={tags={}}
local counts,attack_args,effect_args
local armor_stop,breed_stop=false,false
local alive={[target]=true}
local function count(name) counts[name]=(counts[name] or 0)+1 end
local env=setmetatable({ActionSweep=Sweep, HEALTH_ALIVE=alive,
    ScriptUnit={has_extension=function() return {breed=function() return breed end} end},
    Unit={level=function() end}, Breed={is_character=function() return true end},
    buff_keywords={}, AttackSettings={attack_types={melee='melee'}},
    Weakspot={hit_weakspot=function() return true end},
    HitMass={target_hit_mass=function() return 2 end},
    Armor={armor_type=function() return 'armored' end,aborts_attack=function() return armor_stop end},
    Health={is_ragdolled=function() return false end,is_damagable=function() return true end},
    HazardProp={status=function() return false,false end},
    _breed_aborts_attack=function() return breed_stop end,
    AttackIntensity={add_intensity=function() count('intensity') end},
    attack_results={died='died'}, DEFAULT_POWER_LEVEL=500,
    Attack={execute=function(unit,profile,...)
        count('damage'); attack_args={unit=unit,profile=profile}
        local args={...}; for i=1,#args,2 do attack_args[args[i]]=args[i+1] end
        return 12,'died','efficient','staggered',true
    end},
    ImpactEffect={play=function(...) count('impact'); effect_args={...} end},
    math=setmetatable({clamp01=function(n) return math.max(0,math.min(1,n)) end},{__index=math})
}, {__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1),'@'..path)),env)()
local function fixture(resim,server,mass_limit)
    counts={}; attack_args=nil; effect_args=nil
    local settings={power_level=321,wounds_shape='ordinary',wounds_shape_special_active='special'}
    local weapon={item={},weapon_special_implementation={process_hit=function() count('special') end}}
    local self=setmetatable({_critical_strike_component={is_active=true},_weapon=weapon,
        _is_server=server,_target_index=0,_num_hit_enemies=0,_player_unit=player,
        _inventory_component={wielded_slot='slot_primary'},_amount_of_mass_hit=0,
        _buff_extension={has_keyword=function() return false end},
        _weapon_action_component={special_active_at_start=true},
        _unit_data_extension={is_resimulating=resim},_num_killed_enemies=0,
        _weapon_template={weapon_special_tweak_data={special_active_hit_extra_time=.1}},
        _do_chain_lightning_on_sweep=true,_action_settings=settings,_charge_level=.4,
        _auto_completed=false,
        _current_max_hit_mass=function() return mass_limit end,
        _damage_profile=function() return 'normal','special','normal_abort','special_abort' end,
        _damage_type=function() return 'normal_type','special_type','normal_abort_type','special_abort_type' end,
        _play_hit_effects=function() count('hit_effect') end,
        _increase_action_duration=function() count('extend') end,
        _add_weapon_blood=function() count('blood') end,
        _try_make_chain_from_sweep_hit=function() count('chain') end}, {__index=Sweep})
    return self,settings
end
local function hit(self,settings)
    local hits={}
    local abort,armor=self:_process_hit(1,target,actor,hits,settings,'position','direction','head','normal',1)
    assert(hits[target], 'Stock target set was not mutated')
    return abort,armor
end
local self,settings=fixture(false,true,100)
assert(not hit(self,settings))
assert(counts.damage==1 and counts.impact==1 and counts.hit_effect==1)
assert(attack_args.unit==target and attack_args.profile=='special')
assert(attack_args.target_index==1 and attack_args.target_number==1)
assert(attack_args.power_level==321 and attack_args.charge_level==.4)
assert(attack_args.is_critical_strike and attack_args.auto_completed_action==false)
assert(attack_args.item==self._weapon.item and attack_args.wounds_shape=='special')
assert(attack_args.hit_actor==actor and attack_args.hit_zone_name=='head')
assert(effect_args[8]=='normal' and effect_args[12]==false)
assert(self._num_killed_enemies==1 and self._hit_weakspot and self._amount_of_mass_hit==2)
-- The damage profile index and number of enemies are separate arguments.
-- Their final physical-melee policy is deliberately not selected here.
self,settings=fixture(false,false,100)
self._weapon_action_component.special_active_at_start=false
self._target_index=7; self._num_hit_enemies=11
assert(not hit(self,settings))
assert(attack_args.profile=='normal' and attack_args.damage_type=='normal_type')
assert(attack_args.target_index==8 and attack_args.target_number==12)
assert(attack_args.wounds_shape=='ordinary' and not counts.intensity and not counts.extend)
-- Resimulation guards damage/effects, but NOT all action mutations or callbacks.
for _,server in ipairs({false,true}) do
    self,settings=fixture(true,server,100)
    assert(not hit(self,settings))
    assert(not counts.damage and not counts.impact and not counts.hit_effect)
    for _,name in ipairs({'special','extend','blood','chain'}) do assert(counts[name]==1,name) end
    assert((counts.intensity or 0)==(server and 1 or 0))
    assert(self._target_index==1 and self._num_hit_enemies==1 and self._amount_of_mass_hit==2)
    assert(self._hit_enemies and self._hit_weakspot and self._num_killed_enemies==0)
end
-- Numeric cleave and armor/breed aborts share profile selection, but are
-- distinct decisions: removing only the mass budget must not erase armor.
for _,reason in ipairs({'mass','armor','breed'}) do
    armor_stop=reason=='armor'; breed_stop=reason=='breed'
    self,settings=fixture(false,true,reason=='mass' and 2 or 100)
    local abort,armor=hit(self,settings)
    assert(abort and armor==armor_stop)
    assert(attack_args.profile=='special_abort' and attack_args.damage_type=='special_abort_type')
end
print('melee_damage_stock=pass damage_arguments impact replay_side_effects mass_armor_breed_abort')
