#include "producer/bounded_diagnostic.h"
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <thread>
#include <vector>
using darktidevr::producer::BoundedDiagnostic;
int main() {
  BoundedDiagnostic budget(4096);
  std::atomic<unsigned> prepared{};
  std::vector<std::thread> workers;
  for (unsigned i=0; i<8; ++i) workers.emplace_back([&] {
    for (unsigned j=0; j<10000; ++j) budget.run([&] { ++prepared; });
  });
  for (auto& worker:workers) worker.join();
  if (prepared != 4096) return EXIT_FAILURE;
  BoundedDiagnostic empty(0);
  empty.run([] { std::abort(); });
  budget.run([] { std::abort(); });
  // Compare the old exhausted-counter RMW with the production saturated gate.
  // No resource-name work is included: timing isolates rejected admission only.
  constexpr unsigned iterations=500000;
  for (unsigned trial=0; trial<5; ++trial) {
    std::atomic<std::uint64_t> old_count{4096};
    auto measure=[&](bool old) {
      workers.clear();
      const auto begin=std::chrono::steady_clock::now();
      for (unsigned i=0; i<8; ++i) workers.emplace_back([&] {
        for (unsigned j=0; j<iterations; ++j) {
          if (old) {
            if (old_count.fetch_add(1,std::memory_order_relaxed)<4096) std::abort();
          } else budget.run([] { std::abort(); });
        }
      });
      for (auto& worker:workers) worker.join();
      return std::chrono::duration<double,std::milli>(
          std::chrono::steady_clock::now()-begin).count();
    };
    double old_ms{},new_ms{};
    if (trial%2) {new_ms=measure(false);old_ms=measure(true);}
    else {old_ms=measure(true);new_ms=measure(false);}
    std::cout << "trial=" << trial << " calls=4000000 threads=8 old_ms="
              << old_ms << " new_ms=" << new_ms << '\n';
  }
  std::cout << "PASS exact concurrent budget=4096; exhausted payload calls=0\n";
}
