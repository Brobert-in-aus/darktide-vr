#pragma once

#include "core/xr_math.h"

#include <cstdint>

namespace darktidevr::harness {

enum class SyntheticHeadPhase {
  neutral,
  pitch,
  roll,
  combined,
};

struct SyntheticHeadPathSample {
  math::Pose delta{};
  SyntheticHeadPhase phase{};
};

// Deterministic test-only orientation sweep. Translation is preserved so the
// path can replace only the physical headset orientation in an otherwise live
// OpenXR sample.
SyntheticHeadPathSample synthetic_head_path_sample(
    std::uint64_t frame, math::Vec3 preserved_translation);

}  // namespace darktidevr::harness
