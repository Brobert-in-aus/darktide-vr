#include "producer/shader_pair_snapshot.h"
#include <array>
#include <chrono>
#include <iostream>
#include <mutex>
#include <stdexcept>
using namespace darktidevr::producer;
void check(bool value){if(!value)throw std::runtime_error("shader pair snapshot mismatch");}
// Original full-sort implementation, including identical sample packing.
unsigned original(const ShaderPairCounts& counts,std::span<ShaderPairSample> output) {
  ShaderPairRecords ranked(counts.begin(),counts.end());
  std::sort(ranked.begin(),ranked.end(),[](const auto& a,const auto& b){
    return a.second!=b.second?a.second>b.second:a.first<b.first;
  });
  const auto size=std::min(output.size(),ranked.size());
  for(std::size_t i=0;i<size;++i){
    const auto& pair=ranked[i];
    output[i]={static_cast<std::uint32_t>(pair.first.first),
      static_cast<std::uint32_t>(pair.first.first>>32U),
      static_cast<std::uint32_t>(pair.first.second),
      static_cast<std::uint32_t>(pair.first.second>>32U),pair.second};
  }
  return static_cast<unsigned>(size);
}
__declspec(noinline) unsigned read_original(const ShaderPairCounts& counts,
    std::mutex& mutex,std::span<ShaderPairSample> output) {
  std::scoped_lock lock(mutex);return original(counts,output);
}
__declspec(noinline) unsigned read_candidate(const ShaderPairCounts& counts,
    std::mutex& mutex,std::span<ShaderPairSample> output) {
  ShaderPairRecords records;
  {std::scoped_lock lock(mutex);records.assign(counts.begin(),counts.end());}
  return copy_shader_pair_snapshot(std::move(records),output);
}
void equal(const ShaderPairSample& a,const ShaderPairSample& b) {
  check(a.vertex_low==b.vertex_low&&a.vertex_high==b.vertex_high&&
    a.pixel_low==b.pixel_low&&a.pixel_high==b.pixel_high&&a.count==b.count);
}
__declspec(noinline) std::uint64_t old_shader_value(const ShaderCounts& counts,
    std::mutex& mutex,unsigned rank,bool count) {
  ShaderRecords records;
  {std::scoped_lock lock(mutex);records.assign(counts.begin(),counts.end());}
  std::sort(records.begin(),records.end(),[](const auto& a,const auto& b){
    return a.second!=b.second?a.second>b.second:a.first<b.first;
  });
  return rank<records.size()?(count?records[rank].second:records[rank].first):0;
}
__declspec(noinline) unsigned bulk_shaders(const ShaderCounts& counts,
    std::mutex& mutex,std::span<ShaderSample> output) {
  ShaderRecords records;
  {std::scoped_lock lock(mutex);records.assign(counts.begin(),counts.end());}
  return copy_shader_snapshot(std::move(records),output);
}
void shader_reads() {
  std::mutex mutex;
  for(const unsigned size:{0U,8U,32U,128U,1024U}) {
    ShaderCounts counts;
    for(unsigned i=0;i<size;++i)counts[0xfedcba9800000000ULL+i]=(i*997)%31;
    for(const unsigned capacity:{0U,1U,8U,256U,1025U}) {
      std::vector<ShaderSample> samples(capacity);
      const auto copied=bulk_shaders(counts,mutex,samples);
      check(copied==std::min(capacity,size));
      for(unsigned i=0;i<copied;++i){
        const auto hash=old_shader_value(counts,mutex,i,false);
        check(samples[i].hash_low==static_cast<std::uint32_t>(hash)&&
          samples[i].hash_high==static_cast<std::uint32_t>(hash>>32U)&&
          samples[i].count==old_shader_value(counts,mutex,i,true));
      }
    }
    if(size==0)continue;
    for(unsigned trial=0;trial<5;++trial){
      const auto measure=[&](bool old){
        const auto begin=std::chrono::steady_clock::now();
        for(unsigned read=0;read<1000;++read){
          std::array<ShaderSample,8> output{};
          if(old)for(unsigned i=0;i<8;++i){
            output[i]={static_cast<std::uint32_t>(old_shader_value(counts,mutex,i,false)),
              static_cast<std::uint32_t>(old_shader_value(counts,mutex,i,false)>>32U),
              old_shader_value(counts,mutex,i,true)};
          }else check(bulk_shaders(counts,mutex,output)==8);
          check(output[0].count>0);
        }
        return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
      };
      double before{},after{};
      if(trial%2){after=measure(false);before=measure(true);}else{before=measure(true);after=measure(false);}
      std::cout<<"shaders="<<size<<" capacity=8 trial="<<trial<<" reports=1000 old_ms="<<before<<" new_ms="<<after<<'\n';
    }
    ShaderRecords records(counts.begin(),counts.end());
    const auto hash=old_shader_value(counts,mutex,0,false),count=old_shader_value(counts,mutex,0,true);
    counts.clear();std::array<ShaderSample,1> retained{};
    check(copy_shader_snapshot(std::move(records),retained)==1);
    check(retained[0].hash_high==static_cast<std::uint32_t>(hash>>32U)&&retained[0].count==count);
  }
}
int main(){
  shader_reads();
  std::mutex mutex;
  for(const unsigned size:{0U,8U,32U,128U,1024U,4096U}) {
    ShaderPairCounts counts;
    for(unsigned i=0;i<size;++i)
      counts[{0xf000000000000000ULL+i,0xe000000000000000ULL+(i*7919)%100003}]=(i*997)%31;
    for(const unsigned capacity:{0U,1U,3U,32U,256U,4097U}) {
      std::vector<ShaderPairSample> a(capacity),b(capacity);
      const auto before=read_original(counts,mutex,a),after=read_candidate(counts,mutex,b);
      check(before==after);
      for(unsigned i=0;i<before;++i)equal(a[i],b[i]);
    }
    if(size==0)continue;
    for(unsigned trial=0;trial<5;++trial) {
      const auto measure=[&](bool old){
        std::array<ShaderPairSample,32> output{};
        const auto begin=std::chrono::steady_clock::now();
        for(unsigned i=0;i<1000;++i){
          const auto copied=old?read_original(counts,mutex,output):read_candidate(counts,mutex,output);
          check(copied==std::min(size,32U));
        }
        return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
      };
      double before{},after{};
      if(trial%2){after=measure(false);before=measure(true);}else{before=measure(true);after=measure(false);}
      std::cout<<"pairs="<<size<<" capacity=32 trial="<<trial<<" reads=1000 old_ms="<<before<<" new_ms="<<after<<'\n';
    }
    std::array<ShaderPairSample,32> expected{},actual{};
    const auto count=original(counts,expected);
    ShaderPairRecords records(counts.begin(),counts.end());
    counts.clear(); // Private records retain one coherent counter snapshot.
    check(copy_shader_pair_snapshot(std::move(records),actual)==count);
    for(unsigned i=0;i<count;++i)equal(expected[i],actual[i]);
  }
  std::cout<<"PASS ranking_ties_capacity_zero_full_prefix_high_hashes_snapshot_ownership\n";
}
