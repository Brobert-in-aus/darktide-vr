#include "producer/ngx_sr_observation.h"
#include <atomic>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

using darktidevr::producer::NgxSrObservationBudget;
void expect(bool condition) {
  if (!condition) throw std::runtime_error("SR observation budget invariant failed");
}
int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--emit-records") == 0) {
    using namespace darktidevr::producer;
    char identity{};
    char line[768]{};
    for (std::size_t index = 0; index < kNgxSrResourceNames.size(); ++index) {
      NgxSrResourceRecord record{12, 2, 1, 8, 10, &identity, &identity, 7, index,
          1, &identity, true, 3, 1440, 1600, 1, 1, 28, 1};
      if (index >= 4) {
        record.resource = nullptr;
        record.described = false;
        record.dimension = record.height = record.depth_or_array = record.mips =
            record.format = record.samples = 0;
        record.width = 0;
        if (index == 4) record.result = 0xbad00005;
      }
      const auto length = format_ngx_sr_input(line, sizeof(line), record);
      expect(length > 0 && static_cast<std::size_t>(length) < sizeof(line));
      std::cout << line;
    }
    expect(format_ngx_sr_evaluation(line, sizeof(line), 12, 1) > 0);
    std::cout << line;
    return 0;
  }
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
