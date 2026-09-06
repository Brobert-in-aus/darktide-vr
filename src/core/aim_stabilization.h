#pragma once

#include "core/xr_math.h"
#include <cstdint>
#include <optional>

namespace darktidevr::core {

// Trial values, not calibrated weapon defaults. Time is the requested pose time
// in nanoseconds, in one clock domain; epoch changes invalidate all history.
struct AimStabilizationConfig {
  float minimum_cutoff_hz{8.0F};
  float speed_coefficient{1.0F};  // Hz per radian/second
  float derivative_cutoff_hz{10.0F};
  double maximum_gap_seconds{0.1};
};

class AimStabilization {
 public:
  explicit AimStabilization(AimStabilizationConfig config = {});
  std::optional<math::Quaternion> update(math::Quaternion raw,
      std::uint64_t sequence, std::int64_t pose_time_ns,
      std::uint64_t epoch, bool tracked);
  void reset();

 private:
  AimStabilizationConfig config_;
  std::optional<math::Quaternion> filtered_;
  math::Quaternion previous_raw_{};
  std::uint64_t sequence_{};
  std::uint64_t epoch_{};
  std::int64_t pose_time_ns_{};
  float speed_{};
};

}  // namespace darktidevr::core
