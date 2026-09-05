#pragma once
#include <cstddef>
#include <cstdint>
#include <cstdlib>

namespace darktidevr::core {
// Paint only the 41x41 sprite, including transparent filtering gutters.
inline void paint_reticle_atlas(std::byte* pixels, std::uint32_t row_pitch) {
  for (int y = 0; y < 41; ++y) {
    for (int x = 0; x < 41; ++x) {
      const int dx = x - 20, dy = y - 20;
      const int ax = std::abs(dx), ay = std::abs(dy);
      const bool outline = dx*dx + dy*dy <= 16 ||
          (ax <= 2 && ay >= 6 && ay <= 16) ||
          (ay <= 2 && ax >= 6 && ax <= 16);
      const bool fill = dx*dx + dy*dy <= 4 ||
          (ax <= 1 && ay >= 8 && ay <= 14) ||
          (ay <= 1 && ax >= 8 && ax <= 14);
      auto* p = pixels + y * row_pitch + x * 4;
      p[0] = p[1] = p[2] = fill ? std::byte{255} : std::byte{0};
      p[3] = outline ? std::byte{171} : std::byte{0};
    }
  }
}
}
