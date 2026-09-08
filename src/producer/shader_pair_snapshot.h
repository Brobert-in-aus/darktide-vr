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

// The caller owns the counter lock for this complete snapshot. Copying each
// half-hash/count through separately ranked reads can combine different pairs
// while render threads change the ranking.
inline unsigned int copy_shader_pair_snapshot(
    const ShaderPairCounts& counts, std::span<ShaderPairSample> output) {
  using Record = std::pair<ShaderPairCounts::key_type, std::uint64_t>;
  std::vector<Record> ranked(counts.begin(), counts.end());
  std::sort(ranked.begin(), ranked.end(), [](const auto& left, const auto& right) {
    return left.second != right.second ? left.second > right.second
                                       : left.first < right.first;
  });
  const auto size = std::min(output.size(), ranked.size());
  for (std::size_t index = 0; index < size; ++index) {
    const auto& pair = ranked[index];
    output[index] = {static_cast<std::uint32_t>(pair.first.first),
        static_cast<std::uint32_t>(pair.first.first >> 32U),
        static_cast<std::uint32_t>(pair.first.second),
        static_cast<std::uint32_t>(pair.first.second >> 32U), pair.second};
  }
  return static_cast<unsigned int>(size);
}
}  // namespace darktidevr::producer
