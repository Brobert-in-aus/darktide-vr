#include "producer/profile_percentiles.h"
#include <chrono>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>

using Samples = std::vector<std::uint64_t>;
using Result = std::pair<std::uint64_t, std::uint64_t>;
__declspec(noinline) Result original(Samples& values) {
  if (values.empty()) return {};
  std::sort(values.begin(), values.end());
  return {values[(values.size()-1)/2], values[((values.size()-1)*95)/100]};
}
__declspec(noinline) Result candidate(Samples& values) {
  return darktidevr::producer::profile_percentiles(values);
}
void compare(const Samples& values) {
  auto a = values, b = values;
  if (original(a) != candidate(b)) throw std::runtime_error("percentile mismatch");
}
int main() {
  std::mt19937_64 random(84721);
  for (std::size_t size = 0; size <= 4096; ++size) {
    Samples values(size);
    for (auto& value : values) value = random();
    compare(values);
    for (auto& value : values) value %= 7;
    compare(values);
    std::sort(values.begin(), values.end()); compare(values);
    std::reverse(values.begin(), values.end()); compare(values);
    std::fill(values.begin(), values.end(), UINT64_MAX); compare(values);
  }
  std::uint64_t checksum = 0;
  for (const auto size : {16, 120, 1024, 8192}) {
    Samples source(static_cast<std::size_t>(size));
    for (auto& value : source) value = random();
    Samples scratch(source.size());
    for (int trial = 0; trial < 5; ++trial) {
      for (int order = 0; order < 2; ++order) {
        const bool use_candidate = ((trial + order) % 2) != 0;
        const auto fn = use_candidate ? candidate : original;
        const auto start = std::chrono::steady_clock::now();
        for (int iteration = 0; iteration < 2000; ++iteration) {
          std::copy(source.begin(), source.end(), scratch.begin());
          const auto result = fn(scratch);
          checksum += result.first ^ result.second;
        }
        const auto ms = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - start).count();
        std::cout << size << ',' << trial << ',' << use_candidate << ',' << ms << '\n';
      }
    }
  }
  std::cout << "20485 comparisons passed; checksum=" << checksum << '\n';
}
