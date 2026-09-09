#pragma once

#include <cstdint>
#include <limits>
#include <optional>

namespace darktidevr::producer {

constexpr bool buffer_copy_contains(std::uint64_t copy_offset,
                                    std::uint64_t copy_bytes,
                                    std::uint64_t requested_offset,
                                    std::uint64_t requested_bytes) {
  return requested_offset >= copy_offset && requested_bytes <= copy_bytes &&
         requested_offset - copy_offset <= copy_bytes - requested_bytes;
}

// Translate only after selecting a copy that contains the complete request.
// Reject unaddressable sources instead of wrapping into another GPU allocation.
constexpr std::optional<std::uint64_t> buffer_copy_source_address(
    std::uint64_t base, std::uint64_t source_offset, std::uint64_t delta,
    std::uint64_t bytes) {
  constexpr auto maximum = (std::numeric_limits<std::uint64_t>::max)();
  if (base == 0 || source_offset > maximum - base) return std::nullopt;
  const auto start = base + source_offset;
  if (delta > maximum - start) return std::nullopt;
  const auto address = start + delta;
  if (bytes != 0 && bytes - 1 > maximum - address) return std::nullopt;
  return address;
}

}  // namespace darktidevr::producer
