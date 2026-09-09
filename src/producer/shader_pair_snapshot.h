#pragma once

#include <algorithm>
#include <cstdint>
#include <map>
#include <span>
#include <utility>
#include <vector>

namespace darktidevr::producer {
struct ShaderPairSample {
  std::uint32_t vertex_low{}, vertex_high{}, pixel_low{}, pixel_high{};
  std::uint64_t count{};
};
static_assert(sizeof(ShaderPairSample) == 24);

using ShaderPairCounts =
    std::map<std::pair<std::uint64_t, std::uint64_t>, std::uint64_t>;
using ShaderPairRecords =
    std::vector<std::pair<ShaderPairCounts::key_type, std::uint64_t>>;

// Counter records are copied together under their owner's lock. Sorting this
// private snapshot needs no counter lock and cannot combine different epochs.
inline unsigned int copy_shader_pair_snapshot(
    ShaderPairRecords ranked, std::span<ShaderPairSample> output) {
  const auto size = std::min(output.size(), ranked.size());
  if (size == 0) return 0;
  const auto order = [](const auto& left, const auto& right) {
    return left.second != right.second ? left.second > right.second
                                       : left.first < right.first;
  };
  if (size == ranked.size()) std::sort(ranked.begin(), ranked.end(), order);
  else std::partial_sort(ranked.begin(), ranked.begin() + size, ranked.end(), order);
  for (std::size_t index = 0; index < size; ++index) {
    const auto& pair = ranked[index];
    output[index] = {static_cast<std::uint32_t>(pair.first.first),
        static_cast<std::uint32_t>(pair.first.first >> 32U),
        static_cast<std::uint32_t>(pair.first.second),
        static_cast<std::uint32_t>(pair.first.second >> 32U), pair.second};
  }
  return static_cast<unsigned int>(size);
}
// Convenience overload: caller protects counts while they are copied. Use the
// records overload to release that lock before sorting in a concurrent reader.
inline unsigned int copy_shader_pair_snapshot(
    const ShaderPairCounts& counts, std::span<ShaderPairSample> output) {
  if (output.empty()) return 0;
  return copy_shader_pair_snapshot(ShaderPairRecords(counts.begin(), counts.end()), output);
}
}  // namespace darktidevr::producer
