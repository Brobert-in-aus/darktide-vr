#include "producer/command_recording_snapshot.h"
#include <unordered_map>
#include <chrono>
#include <iostream>
#include <stdexcept>
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
  std::cout << "PASS fixed-state snapshot copies no diagnostic values and survives source mutation\n";
}
