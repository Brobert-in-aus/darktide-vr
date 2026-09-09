#pragma once
#include <array>
#include <atomic>
#include <cstdint>

namespace darktidevr::producer {
// Names from the pinned Streamline v2.7.30 NGX definitions. These are queries,
// not evidence that the installed SR implementation supports every input.
inline constexpr std::array<const char*, 7> kNgxSrResourceNames{
    "Color", "Output", "Depth", "MotionVectors", "TransparencyMask",
    "ExposureTexture", "DLSS.Input.Bias.Current.Color.Mask"};

class NgxSrObservationBudget {
 public:
  static constexpr unsigned limit = 64;
  bool reserve(bool enabled, bool window_eligible, std::uint32_t kind,
               std::uint64_t lifetime, bool abi_verified) {
    if (!enabled || !window_eligible || kind != 1 || !lifetime || !abi_verified)
      return false;
    auto count = used_.load(std::memory_order_relaxed);
    while (count < limit) {
      if (used_.compare_exchange_weak(count, count + 1, std::memory_order_relaxed))
        return true;
    }
    return false;
  }
  bool exhausted() const { return used_.load(std::memory_order_relaxed) >= limit; }
 private:
  std::atomic<unsigned> used_{};
};
}  // namespace darktidevr::producer
