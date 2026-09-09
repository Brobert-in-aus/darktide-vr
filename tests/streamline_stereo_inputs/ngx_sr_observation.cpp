#include "producer/ngx_sr_observation.h"
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

using darktidevr::producer::NgxSrObservationBudget;
void expect(bool condition) {
  if (!condition) throw std::runtime_error("SR observation budget invariant failed");
}
int main() {
  NgxSrObservationBudget budget;
  // Excluded calls must neither query resources nor consume the later window.
  for (unsigned i = 0; i < 128; ++i) {
    expect(!budget.reserve(false, true, 1, 1, true));
    expect(!budget.reserve(true, false, 1, 1, true));
    expect(!budget.reserve(true, true, 11, 1, true));
    expect(!budget.reserve(true, true, 1, 0, true));
    expect(!budget.reserve(true, true, 1, 1, false));
  }
  expect(!budget.exhausted());
  std::atomic<unsigned> accepted{};
  std::vector<std::thread> workers;
  for (unsigned i = 0; i < 16; ++i) {
    workers.emplace_back([&] {
      for (unsigned attempt = 0; attempt < 128; ++attempt)
        if (budget.reserve(true, true, 1, 1, true)) ++accepted;
    });
  }
  for (auto& worker : workers) worker.join();
  expect(accepted == NgxSrObservationBudget::limit && budget.exhausted());
  // A later feature lifetime/window cannot replenish the process budget.
  expect(!budget.reserve(true, true, 1, 2, true));
  std::cout << "ngx_sr_observation=pass disabled closed FG unknown ABI concurrency exhaustion\n";
}
