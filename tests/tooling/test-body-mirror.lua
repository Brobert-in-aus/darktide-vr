local Mirror=dofile(assert(arg[1]))
assert(Mirror.keeps_slot('slot_body_torso',{slot_type='body'}))
assert(Mirror.keeps_slot('slot_gear_head',{slot_type='gear'}))
assert(Mirror.keeps_slot('slot_gear_material_override_decal',{slot_type='material'}))
assert(Mirror.keeps_slot('slot_unarmed',{slot_type='weapon'}),'spawner plumbing')
assert(not Mirror.keeps_slot('slot_primary',{slot_type='weapon'}),'no weapons')
assert(not Mirror.keeps_slot('slot_pocketable',{slot_type='gadget',ignore_character_spawning=true}))
assert(not Mirror.keeps_slot('slot_companion_gear_full',{slot_type='gear'}),'no companion')
assert(not Mirror.keeps_slot('slot_insignia',{slot_type='ui',ignore_character_spawning=true}))
local a={j_hips=2,j_head=9}
local b={j_hips=2,j_head=9}
local c={j_hips=2,j_head=10}
local function lookup(t) return function(name) return t[name] end end
assert(Mirror.same_layout(246,246,lookup(a),lookup(b),{'j_hips','j_head'}))
assert(not Mirror.same_layout(246,220,lookup(a),lookup(b),{'j_hips'}),'node counts differ')
assert(not Mirror.same_layout(246,246,lookup(a),lookup(c),{'j_hips','j_head'}),'probe index differs')
print('body_mirror=pass keeps_slot same_layout')
