#include "pair_poll_wait.h"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <numeric>
#include <string_view>
#include <type_traits>
#include <vector>

namespace {
void require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}

struct FakeApi {
  using Handle = int*;
  static inline int resource{}, creates{}, arms{}, waits{}, closes{}, fallbacks{};
  static inline bool create_ok{true}, arm_ok{true}, wait_ok{true};
  static Handle create() { ++creates; return create_ok ? &resource : nullptr; }
  static bool arm(Handle) { ++arms; return arm_ok; }
  static bool wait(Handle) { ++waits; return wait_ok; }
  static void close(Handle) { ++closes; }
  static void fallback() { ++fallbacks; }
  static void reset() {
    creates=arms=waits=closes=fallbacks=0;
    create_ok=arm_ok=wait_ok=true;
  }
};
using Wait = darktidevr::xr::PairPollWait<FakeApi>;
static_assert(!std::is_copy_constructible_v<Wait> && !std::is_move_constructible_v<Wait>);

void failure_tests() {
  FakeApi::reset();
  { Wait wait(false); wait.wait(); wait.wait();
    require(!wait.precise() && wait.failures()==0, "disabled path is not a timer failure"); }
  require(FakeApi::creates==0 && FakeApi::closes==0 && FakeApi::fallbacks==2,
          "disabled path must retain ordinary sleeps without creating a timer");
  FakeApi::reset();
  { Wait wait(true); wait.wait(); wait.wait();
    require(wait.precise() && wait.failures()==0, "successful timer lost its state"); }
  require(FakeApi::creates==1 && FakeApi::arms==2 && FakeApi::waits==2 &&
          FakeApi::closes==1 && FakeApi::fallbacks==0, "reuse/ownership is wrong");
  for (int failure=0; failure<3; ++failure) {
    FakeApi::reset();
    FakeApi::create_ok=failure!=0;
    FakeApi::arm_ok=failure!=1;
    FakeApi::wait_ok=failure!=2;
    { Wait wait(true); wait.wait(); wait.wait();
      require(!wait.precise() && wait.failures()==1, "failure must be explicit and retire once"); }
    require(FakeApi::creates==1 && FakeApi::fallbacks==2,
            "timer failure must sleep on this and subsequent polls without retrying creation");
    require(FakeApi::closes==(failure==0 ? 0 : 1), "failed handle leaked or closed twice");
    require(FakeApi::arms==(failure==0 ? 0 : 1) && FakeApi::waits==(failure==2 ? 1 : 0),
            "failed arm/create must never enter the timer wait");
  }
}

void report(const char* name, std::vector<double> samples) {
  std::sort(samples.begin(),samples.end());
  std::cout << name << " n=" << samples.size()
            << " mean_ms=" << std::accumulate(samples.begin(),samples.end(),0.0)/static_cast<double>(samples.size())
            << " min_ms=" << samples.front() << " p50_ms=" << samples[samples.size()/2]
            << " p95_ms=" << samples[samples.size()*95/100] << " p99_ms=" << samples[samples.size()*99/100]
            << " max_ms=" << samples.back() << '\n';
}

void native_check(bool benchmark) {
  darktidevr::xr::PairPollWait precise(true), standard(false);
  require(precise.precise(), "high-resolution timer unavailable on validation host");
  std::vector<double> standard_ms, precise_ms;
  const int samples=benchmark ? 2000 : 8;
  const int warmup=benchmark ? 100 : 0;
  for (int i=0; i<samples+warmup; ++i) {
    for (int j=0; j<2; ++j) {
      const bool high=(i+j)%2==0;
      const auto start=std::chrono::steady_clock::now();
      (high ? precise : standard).wait();
      const auto ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
      require(ms>0, "native wait was not observed");
      if (i>=warmup) (high ? precise_ms : standard_ms).push_back(ms);
    }
  }
  require(precise.precise() && precise.failures()==0, "native repeated timer wait failed");
  // Timing distributions are observations, not brittle scheduler performance assertions.
  report("standard_500us",standard_ms);
  report("high_resolution_500us",precise_ms);
}
}

int main(int argc, char** argv) {
  const bool benchmark=argc==2 && std::string_view(argv[1])=="--benchmark";
  if (argc>1 && !benchmark) { std::cerr << "usage: pair-poll-wait-tests [--benchmark]\n"; return 2; }
  failure_tests();
  native_check(benchmark);
  std::cout << "pair_poll_wait=pass\n";
}
