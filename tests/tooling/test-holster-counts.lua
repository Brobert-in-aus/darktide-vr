local Counts=dofile(assert(arg[1]))
local belt={id='belt',selector='blitz'}
local chest={id='chest_left',slot='slot_pocketable_small'}
local shoulder={id='shoulder_right',slot='slot_secondary'}
local hip={id='hip_left',slot='slot_primary'}
assert(Counts.label(belt,{blitz={2,3}})=='2/3')
assert(Counts.label(belt,{blitz={0,1}})=='0/1')
assert(Counts.label(belt,{blitz={1,0}})==nil,'no blitz charges to show')
assert(Counts.label(belt,{})==nil)
assert(Counts.label(shoulder,{ammo={6,49}})=='6 / 49')
assert(Counts.label(shoulder,{ammo={12}})=='12','no reserve (overheat weapons show the clip only)')
assert(Counts.label(chest,{names={slot_pocketable_small='Medical Stimm'}})=='Medical Stimm')
assert(Counts.label(chest,{names={slot_pocketable_small=false}})=='empty')
assert(Counts.label(chest,{names={}})==nil,'unknown name draws nothing')
assert(Counts.label(hip,{names={slot_primary='Power Maul'}})=='Power Maul')
assert(Counts.label(nil,{})==nil and Counts.label(chest,nil)==nil)
print('holster_counts=pass blitz ammo names empty unknown')
