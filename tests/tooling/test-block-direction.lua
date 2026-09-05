local module=dofile(arg[1])
local player,remote={},{}
local head,left={},{}
local components={first_person={rotation=head,position=7},other={value=8}}
local data={_unit=player}
local other_data={_unit=remote}
local data_class={read_component=function(self,name) return components[name] end}
local block={}
block.is_blocking=function(unit)
 local owner=unit==player and data or other_data
 local read=data_class.read_component(owner,'first_person')
 assert(read.position==7)
 assert(data_class.read_component(owner,'other')==components.other)
 return read.rotation==left,nil,17
end
block.attempt_block_break=block.is_blocking
require=function(path)
 if path:find('player_unit_data_extension',1,true) then error('unit data cannot load during mod boot') end
 return block
end
Managers={player={local_player=function() return {player_unit=player} end}}
local deferred
local mod={hook_require=function(_,_,callback) deferred=callback end,hook=function(_,target,name,callback)
 local original=target[name]
 target[name]=function(...) return callback(original,...) end
end,info=function() end}
module.install(mod,{target=function(side) assert(side=='left'); return {},left end})
assert(deferred, 'missing deferred unit-data registration')
deferred(data_class)
for _,name in ipairs({'is_blocking','attempt_block_break'}) do
 local a,b,c=block[name](player)
 assert(a and b==nil and c==17,'left block heading/returns lost')
 assert(not block[name](remote),'changed remote block heading')
 assert(data_class.read_component(data,'first_person').rotation==head,'leaked heading outside block')
end
-- Throw inside the scoped calculation; subsequent reads must be ordinary again.
local read_original=data_class.read_component
data_class.read_component=function() error('fixture') end
assert(not pcall(block.is_blocking,player))
data_class.read_component=read_original
assert(data_class.read_component(data,'first_person').rotation==head)
left=nil
assert(not block.is_blocking(player),'missing left pose must keep stock behavior')
print('left-hand block eligibility/cost scope, remote isolation and cleanup passed')
