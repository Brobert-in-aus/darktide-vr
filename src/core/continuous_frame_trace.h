#pragma once
#include <cstdint>

namespace darktidevr::core {
// Bounded ownership probes need every frame. Continuous delivery keeps its
// startup evidence and periodic samples without five locked writes per frame.
// Failure and lifecycle records must be emitted independently of this policy.
constexpr bool trace_continuous_frame(bool persistent, std::uint64_t frame) noexcept {
  return frame != 0 && (!persistent || frame <= 8 || frame % 120 == 0);
}
}
