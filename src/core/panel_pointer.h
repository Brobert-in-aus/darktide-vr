#pragma once

#include "core/xr_math.h"

#include <cstdint>
#include <optional>

namespace darktidevr::core {

struct PointerRay {
  math::Vec3 origin{};
  math::Vec3 direction{0.0F, 0.0F, -1.0F};
};

struct PanelPointerMapping {
  float u{};
  float v{};
  float distance_metres{};
  std::uint32_t source_x{};
  std::uint32_t source_y{};
};

// Intersects a LOCAL-space controller ray with a spatial panel and maps the
// hit through the captured source crop. U grows right and V grows down, matching
// desktop client coordinates. Hits outside the finite panel are rejected.
std::optional<PanelPointerMapping> map_pointer_to_panel(
    PointerRay ray, math::Pose panel_pose, float panel_width_metres,
    float panel_height_metres, std::uint32_t source_width,
    std::uint32_t source_height, std::uint32_t crop_x, std::uint32_t crop_y,
    std::uint32_t crop_width, std::uint32_t crop_height);

// The inverse mapping: a source pixel inside the crop to its LOCAL-space point
// on the panel surface. Used to mark a desktop mouse position on the panel.
std::optional<math::Vec3> panel_point_from_source(
    math::Pose panel_pose, float panel_width_metres, float panel_height_metres,
    std::uint32_t source_x, std::uint32_t source_y, std::uint32_t crop_x,
    std::uint32_t crop_y, std::uint32_t crop_width, std::uint32_t crop_height);

bool pointer_origin_within_reach(math::Vec3 pointer_origin,
                                 math::Vec3 head_position,
                                 float maximum_reach_metres);

}  // namespace darktidevr::core
