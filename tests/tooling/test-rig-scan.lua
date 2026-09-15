local RigScan=dofile(assert(arg[1]))
-- 1 root, 2 j_hips, 3 unmapped twist, 4 j_spine, 5 j_neck under 4
local parent_of={nil,1,2,3,4}
local name_of={[2]='j_hips',[4]='j_spine',[5]='j_neck'}
assert(RigScan.mapped_parent(4,parent_of,name_of)=='j_hips','skips unmapped intermediates')
assert(RigScan.mapped_parent(5,parent_of,name_of)=='j_spine')
assert(RigScan.mapped_parent(2,parent_of,name_of)==nil,'root has no mapped parent')
local loop={[1]=2,[2]=1}
assert(RigScan.mapped_parent(1,loop,{})==nil,'guards against loops')
local seen={}
for _,name in ipairs(RigScan.JOINTS) do assert(not seen[name],'duplicate '..name); seen[name]=true end
assert(seen.j_hips and seen.j_head and seen.j_lefthand and seen.j_rightfoot)
print('rig_scan=pass mapped_parent loops joint_list')
