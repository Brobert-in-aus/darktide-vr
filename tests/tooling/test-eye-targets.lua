local module = dofile(arg[1])
local resources, stack, calls, released = {}, {}, {}, {}
local next_id, fail_allocation, fail_viewport = 0, nil, false
Renderer = {
 create_resource = function(kind, format, unused, w, h, name)
  if fail_allocation == name then error('allocation failed') end
  next_id = next_id + 1
  local r = {id=next_id,w=w,h=h,name=name}
  resources[r] = true
  return r
 end,
 destroy_resource = function(r)
  assert(resources[r], 'invalid or duplicate resource destruction')
  resources[r] = nil
 end,
}
ResourceReferenceContext = {
 push=function(name) stack[#stack+1]=name end,
 pop=function(name) assert(table.remove(stack)==name, 'reference context leaked') end,
}
local world_api = {
 create_viewport=function(world, name, template, layer, camera, position, rotation,
     shadow, shading, callback, mood, targets)
  if fail_viewport then error('viewport failed') end
  calls[#calls+1] = {world=world,name=name,template=template,layer=layer,camera=camera,
   position=position,rotation=rotation,shadow=shadow,shading=shading,callback=callback,
   mood=mood,targets=targets}
  return {world=world,name=name}
 end,
 destroy_viewport=function(world,name)
  -- The owning resources must still exist when the engine drops references.
  for _,c in ipairs(calls) do
   if c.world==world and c.name==name and c.targets and c.targets.back_buffer then
    assert(resources[c.targets.back_buffer] and resources[c.targets.hudless_color])
   end
  end
 end,
}
Application = {release_world=function(world) released[world]=true end}
local mod = {
 hook=function(_,target,name,hook)
  local original=assert(target[name]); target[name]=function(...) return hook(original,...) end
 end,
 info=function() end,
}
local extent_calls=0
local runtime_width, runtime_height = 2496, 2688
module.install(mod,world_api,function()
 extent_calls=extent_calls+1; return runtime_width,runtime_height
end)
local function create(world,name,template,camera,targets)
 return world_api.create_viewport(world,name,template or 'default',7,camera,
  'pos','rot',true,'shading','callback','mood',targets)
end
local function count() local n=0; for _ in pairs(resources) do n=n+1 end; return n end
-- Ordinary menus, explicit caller mappings, and unpaired right eyes pass through.
local w={}
create(w,'shop','default',{})
local explicit={custom=true}
create(w,'player1','default',{},explicit)
assert(calls[#calls].targets==explicit and count()==0)
create(w,'darktidevr_right_eye')
assert(calls[#calls].targets==nil and count()==0)
local camera={}
local left=create(w,'player1','default',camera)
local left_call=calls[#calls]
assert(left_call.camera==camera and left_call.layer==7 and left_call.shadow==true)
assert(left_call.position=='pos' and left_call.rotation=='rot' and left_call.callback=='callback')
assert(left_call.shading=='shading' and left_call.mood=='mood')
assert(left_call.targets.output_target==nil, 'engine must own the upscaler-sized internal target')
assert(left_call.targets.hudless_color~=left_call.targets.back_buffer)
assert(left_call.targets.hudless_color.w==2496 and left_call.targets.hudless_color.h==2688)
assert(left_call.targets.back_buffer.w==2496 and left_call.targets.back_buffer.h==2688)
local right=create(w,'darktidevr_right_eye')
local right_call=calls[#calls]
assert(extent_calls==1, 'paired eye dimensions must share the same captured extent')
assert(right_call.targets.back_buffer~=left_call.targets.back_buffer and count()==4)
assert(not pcall(create,w,'player1','default',camera) and count()==4)
world_api.destroy_viewport(w,'darktidevr_right_eye')
assert(count()==2)
Application.release_world(w)
assert(released[w] and count()==0)
Application.release_world(w)
assert(count()==0, 'world cleanup must be idempotent')
-- Partial allocations and failed viewport creation unwind ownership and contexts.
fail_allocation='darktidevr_left_eye_final'
assert(not pcall(create,{},'player1','default',camera) and count()==0 and #stack==0)
fail_allocation='darktidevr_left_eye_hudless'
assert(not pcall(create,{},'player1','default',camera) and count()==0 and #stack==0)
fail_allocation=nil; fail_viewport=true
assert(not pcall(create,{},'player1','default',camera) and count()==0 and #stack==0)
fail_viewport=false
local next_world={}
create(next_world,'player1','default',nil) -- Engine may spawn its own camera.
create(next_world,'darktidevr_right_eye')
assert(count()==4)
Application.release_world(next_world)
assert(count()==0 and #stack==0)
-- A new runtime/session may recommend any supported extent, including landscape.
-- Neither a headset model nor a DLSS quality fraction selects these finals.
for _,size in ipairs({{1800,1920},{3000,2000},{3200,3500}}) do
 runtime_width,runtime_height=size[1],size[2]
 local world={}
 create(world,'player1')
 create(world,'darktidevr_right_eye')
 for i=#calls-1,#calls do
  local targets=calls[i].targets
  assert(targets.output_target==nil, 'DLSS internal target must remain engine-owned')
  for _,name in ipairs({'back_buffer','hudless_color'}) do
   assert(targets[name].w==size[1] and targets[name].h==size[2])
  end
 end
 Application.release_world(world)
 assert(count()==0)
end
runtime_width,runtime_height=0,0
assert(not pcall(create,{},'player1') and count()==0,
 'missing runtime extent must not allocate fallback-sized targets')
print('gameplay eye targets: isolation, pass-through, extent pairing and lifecycle passed')
