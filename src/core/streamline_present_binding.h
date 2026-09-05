#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace darktidevr::core {

struct StreamlinePresentEyeBinding {
  bool constants_valid{};
  std::uintptr_t token{};
  std::uint64_t token_call{};
  std::uint32_t frame_index{~0U};
  std::uint64_t constants_present{};
  std::uint64_t pose{};
  std::uint32_t viewport{};
  bool options_valid{};
  std::uint32_t mode{};
  std::uint64_t options_present{};
};

// The native Present counter advances on entry, after this pair's game calls.
// Require observations from that exact preceding interval, not merely a token
// pointer (Streamline recycles pointers) or neighboring source frame indices.
constexpr bool streamline_present_binding_matches(
    std::uint64_t present, const std::array<std::uint32_t, 2>& viewports,
    const std::array<StreamlinePresentEyeBinding, 2>& eyes) noexcept {
  if (!present || !viewports[0] || !viewports[1] || viewports[0] == viewports[1])
    return false;
  for (std::size_t eye = 0; eye < 2; ++eye) {
    const auto& value = eyes[eye];
    if (!value.constants_valid || !value.token || !value.token_call ||
        value.frame_index == ~0U || value.constants_present != present - 1 ||
        !value.pose || value.viewport != viewports[eye] ||
        !value.options_valid || value.mode != 1 ||
        value.options_present != value.constants_present) return false;
  }
  return eyes[0].token == eyes[1].token &&
      eyes[0].token_call == eyes[1].token_call &&
      eyes[0].frame_index == eyes[1].frame_index && eyes[0].pose == eyes[1].pose;
}
} // namespace darktidevr::core
