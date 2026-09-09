#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cmath>

namespace darktidevr::producer {
// Names from the pinned Streamline v2.7.30 NGX definitions. These are queries,
// not evidence that the installed SR implementation supports every input.
inline constexpr std::array<const char*, 7> kNgxSrResourceNames{
    "Color", "Output", "Depth", "MotionVectors", "TransparencyMask",
    "ExposureTexture", "DLSS.Input.Bias.Current.Color.Mask"};

inline constexpr std::array<const char*, 5> kNgxSrFloatNames{
    "Jitter.Offset.X", "Jitter.Offset.Y", "MV.Scale.X", "MV.Scale.Y", "DLSS.Pre.Exposure"};
inline constexpr std::array<const char*, 2> kNgxSrUnsignedNames{
    "DLSS.Render.Subrect.Dimensions.Width", "DLSS.Render.Subrect.Dimensions.Height"};
inline constexpr const char* kNgxSrResetName = "Reset";

inline int format_ngx_sr_scalar(char* output, std::size_t capacity,
    std::uint64_t call, const char* name, const char* type, bool queried,
    std::uint32_t result, double value) {
  char formatted[48] = "unavailable";
  const bool valid = queried && result == 1 && std::isfinite(value);
  if (valid) std::snprintf(formatted, sizeof(formatted), "%.17g", value);
  return std::snprintf(output, capacity,
      "NGX_SR_SCALAR call=%llu name=%s type=%s queried=%u result=%x valid=%u value=%s\n",
      static_cast<unsigned long long>(call), name, type, queried ? 1U : 0U,
      result, valid ? 1U : 0U, formatted);
}

struct NgxSrResourceRecord {
  std::uint64_t call{}, lifetime{}, batch{}, present{}, first_call{};
  const void* feature{};
  void* commands{};
  std::uint32_t thread{};
  std::size_t index{};
  std::uint32_t result{};
  void* resource{};
  bool described{};
  unsigned dimension{};
  std::uint64_t width{};
  unsigned height{}, depth_or_array{}, mips{}, format{}, samples{};
};

inline int format_ngx_sr_input(char* output, std::size_t capacity,
                               const NgxSrResourceRecord& r) {
  if (r.index >= kNgxSrResourceNames.size()) return -1;
  return std::snprintf(output, capacity,
      "NGX_SR_INPUT call=%llu feature=%p lifetime=%llu commands=%p thread=%u "
      "batch=%llu present=%llu first_call=%llu index=%zu name=%s result=%x resource=%p described=%u "
      "dimension=%u width=%llu height=%u depth_or_array=%u mips=%u format=%u samples=%u "
      "pixels_captured=0 publication=0\n",
      static_cast<unsigned long long>(r.call), r.feature,
      static_cast<unsigned long long>(r.lifetime), r.commands, r.thread,
      static_cast<unsigned long long>(r.batch), static_cast<unsigned long long>(r.present),
      static_cast<unsigned long long>(r.first_call), r.index, kNgxSrResourceNames[r.index],
      r.result, r.resource, r.described ? 1U : 0U, r.dimension,
      static_cast<unsigned long long>(r.width), r.height, r.depth_or_array,
      r.mips, r.format, r.samples);
}

inline int format_ngx_sr_evaluation(char* output, std::size_t capacity,
                                    std::uint64_t call, std::uint32_t result) {
  return std::snprintf(output, capacity,
      "NGX_SR_EVAL call=%llu result=%x gpu_complete=0 publication=0\n",
      static_cast<unsigned long long>(call), result);
}

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
