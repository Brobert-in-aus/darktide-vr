-- Explicit copied-DLL ABI check. Does not install hooks or open XR/game state.
local ffi=require('ffi')
ffi.cdef[[
typedef struct {unsigned int hash_low,hash_high;unsigned long long count;} dtvr_billboard_shader_sample;
unsigned int dtvr_copy_billboard_candidate_shaders(dtvr_billboard_shader_sample*,unsigned int);
unsigned int dtvr_billboard_candidate_shader_hash_low(unsigned int);
unsigned int dtvr_billboard_candidate_shader_hash_high(unsigned int);
unsigned long long dtvr_billboard_candidate_shader_count(unsigned int);
]]
assert(ffi.sizeof('dtvr_billboard_shader_sample')==16)
assert(ffi.offsetof('dtvr_billboard_shader_sample','hash_low')==0)
assert(ffi.offsetof('dtvr_billboard_shader_sample','hash_high')==4)
assert(ffi.offsetof('dtvr_billboard_shader_sample','count')==8)
local library=ffi.load(assert(arg[1],'copied DLL required'))
local ok,snapshot=pcall(function()return library.dtvr_copy_billboard_candidate_shaders end)
local mode=assert(arg[2],'available or legacy required')
assert(mode=='available' or mode=='legacy')
assert(ok==(mode=='available'))
if ok then
    local samples=ffi.new('dtvr_billboard_shader_sample[3]')
    samples[2].count=777
    assert(snapshot(nil,1)==0 and snapshot(samples,0)==0 and snapshot(samples,257)==0)
    assert(snapshot(samples,3)==0 and samples[2].count==777)
else
    assert(library.dtvr_billboard_candidate_shader_hash_low(0)==0)
    assert(library.dtvr_billboard_candidate_shader_hash_high(0)==0)
    assert(library.dtvr_billboard_candidate_shader_count(0)==0)
end
print('billboard_shader_snapshot_ffi=pass mode='..mode..' hooks_installed=0')
