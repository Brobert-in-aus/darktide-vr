#pragma once

#include <optional>
#include <string>
#include <string_view>

#include "core/xr_math.h"

namespace darktidevr::darktide {

struct SemanticCameraSample {
  std::string viewport;
  math::Pose pose;
  float vertical_fov_rad{};
};

// Parses the versioned DMF camera contract from a complete console-log line.
// Invalid, non-finite, implausible, or unrelated lines fail closed.
std::optional<SemanticCameraSample> parse_semantic_camera_line(
    std::string_view line);

}  // namespace darktidevr::darktide
