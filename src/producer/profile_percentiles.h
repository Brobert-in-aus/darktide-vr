#pragma once
#include <algorithm>
#include <cstdint>
#include <span>
#include <utility>

namespace darktidevr::producer {
// Mutates detached samples only; the rank convention matches the profiler API.
inline std::pair<std::uint64_t, std::uint64_t> profile_percentiles(
    std::span<std::uint64_t> samples) {
  if (samples.empty()) return {};
  const auto last = samples.size() - 1;
  const auto middle = last / 2;
  const auto upper = (last / 100) * 95 + ((last % 100) * 95) / 100;
  // Avoid two partition operations for tiny reports.
  if (samples.size() <= 32) {
    std::sort(samples.begin(), samples.end());
    return {samples[middle], samples[upper]};
  }
  auto median = samples.begin() + middle;
  std::nth_element(samples.begin(), median, samples.end());
  const auto p50 = *median;
  if (upper == middle) return {p50, p50};
  auto p95 = samples.begin() + upper;
  std::nth_element(median + 1, p95, samples.end());
  return {p50, *p95};
}
}  // namespace darktidevr::producer
