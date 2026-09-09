#include "producer/command_recording_snapshot.h"
#include <unordered_map>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <mutex>
using darktidevr::producer::CommandRecordingSnapshot;
struct DiagnosticValue {
  std::array<std::uint64_t, 16> counters{};
  inline static unsigned copies{};
  DiagnosticValue()=default;
  DiagnosticValue(const DiagnosticValue& other):counters(other.counters) { ++copies; }
  DiagnosticValue& operator=(const DiagnosticValue& other) { counters=other.counters; ++copies; return *this; }
};
struct Recording : CommandRecordingSnapshot {
  std::unordered_map<unsigned,DiagnosticValue> passes;
};
void check(bool value) { if(!value) throw std::runtime_error("snapshot mismatch"); }
__declspec(noinline) void old_copy(Recording& out,const Recording& in) {out=in;}
__declspec(noinline) void snapshot_copy(CommandRecordingSnapshot& out,const Recording& in) {out=in;}
__declspec(noinline) std::array<std::uint64_t,2> full_bindings(
    const CommandRecordingSnapshot& source,std::mutex& mutex) {
  CommandRecordingSnapshot snapshot{};
  {std::scoped_lock lock(mutex);snapshot=source;}
  return {snapshot.graphics_cbvs[0],snapshot.graphics_cbvs[2]};
}
__declspec(noinline) std::array<std::uint64_t,2> narrow_bindings(
    const CommandRecordingSnapshot& source,std::mutex& mutex) {
  std::array<std::uint64_t,2> snapshot{};
  {std::scoped_lock lock(mutex);snapshot={source.graphics_cbvs[0],source.graphics_cbvs[2]};}
  return snapshot;
}
int main() {
  Recording source;
  source.recording_generation=17; source.render_target=123;
  source.pso=321; source.scissor={1,2,3,4};
  source.graphics_cbvs[0]=100; source.graphics_cbvs[31]=200;
  source.compute_uavs[31]=300;
  for(unsigned i=0;i<128;++i) source.passes[i].counters[0]=i;
  CommandRecordingSnapshot snapshot;
  snapshot_copy(snapshot,source);
  check(DiagnosticValue::copies==0);
  check(snapshot.recording_generation==17 && snapshot.render_target==123 &&
      snapshot.pso==321 && snapshot.scissor.right==3 &&
      snapshot.graphics_cbvs[0]==100 && snapshot.graphics_cbvs[31]==200 &&
      snapshot.compute_uavs[31]==300);
  source.graphics_cbvs[0]=999; source.recording_generation=18; source.passes.clear();
  check(snapshot.graphics_cbvs[0]==100 && snapshot.recording_generation==17);
  for(const unsigned pass_count:{0U,128U}) {
    for(unsigned i=0;i<pass_count;++i) source.passes[i].counters[0]=i;
    for(unsigned trial=0;trial<5;++trial) {
      const auto measure=[&](bool old) {
        const auto begin=std::chrono::steady_clock::now();
        for(unsigned i=0;i<10000;++i) {
          if(old) {Recording out; old_copy(out,source);check(out.render_target==123);}
          else {CommandRecordingSnapshot out; snapshot_copy(out,source);check(out.render_target==123);}
        }
        return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
      };
      double before{},after{};
      if(trial%2) {after=measure(false);before=measure(true);}
      else {before=measure(true);after=measure(false);}
      std::cout << "passes=" << pass_count << " trial=" << trial << " copies=10000 old_ms=" << before << " new_ms=" << after << '\n';
    }
  }
  std::mutex mutex;
  source.graphics_cbvs[0]=100;source.graphics_cbvs[2]=200;
  for(unsigned trial=0;trial<5;++trial) {
    const auto measure=[&](bool full) {
      const auto begin=std::chrono::steady_clock::now();
      for(unsigned i=0;i<100000;++i) {
        const auto result=full?full_bindings(source,mutex):narrow_bindings(source,mutex);
        check(result[0]==100&&result[1]==200);
      }
      return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
    };
    double full{},narrow{};
    if(trial%2){narrow=measure(false);full=measure(true);}
    else{full=measure(true);narrow=measure(false);}
    std::cout << "bindings_trial=" << trial << " copies=100000 full_ms=" << full
      << " narrow_ms=" << narrow << " full_bytes=" << sizeof(CommandRecordingSnapshot) << " narrow_bytes=16\n";
  }
  std::cout << "PASS fixed-state snapshot copies no diagnostic values and survives source mutation\n";
}
