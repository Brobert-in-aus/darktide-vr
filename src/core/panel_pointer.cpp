#include "core/panel_pointer.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace darktidevr::core {
namespace {

bool finite(math::Vec3 value) {
  return std::isfinite(value.x) && std::isfinite(value.y) &&
         std::isfinite(value.z);
}

}  // namespace

std::optional<PanelPointerMapping> map_pointer_to_panel(
    PointerRay ray, math::Pose panel_pose, float panel_width_metres,
    float panel_height_metres, std::uint32_t source_width,
    std::uint32_t source_height, std::uint32_t crop_x, std::uint32_t crop_y,
    std::uint32_t crop_width, std::uint32_t crop_height) {
  if (!finite(ray.origin) || !finite(ray.direction) ||
      !(panel_width_metres > 0.0F) || !(panel_height_metres > 0.0F) ||
      !std::isfinite(panel_width_metres) ||
      !std::isfinite(panel_height_metres) || source_width == 0 ||
      source_height == 0 || crop_width == 0 || crop_height == 0 ||
      crop_x > source_width || crop_y > source_height ||
      crop_width > source_width - crop_x ||
      crop_height > source_height - crop_y) {
    // Presentation metadata can change independently of the render loop while
    // a menu opens or closes. A transiently stale crop is a pointer miss, not
    // a fatal XR condition.
    return std::nullopt;
  }

  const auto inverse_panel = math::inverse(panel_pose);
  const auto local_origin = math::transform_point(inverse_panel, ray.origin);
  const auto local_direction =
      math::rotate(inverse_panel.orientation, ray.direction);
  if (std::abs(local_direction.z) < 1.0e-6F) {
    return std::nullopt;
  }

  const auto distance = -local_origin.z / local_direction.z;
  if (!(distance >= 0.0F) || !std::isfinite(distance)) {
    return std::nullopt;
  }
  const auto hit_x = local_origin.x + local_direction.x * distance;
  const auto hit_y = local_origin.y + local_direction.y * distance;
  const auto u = hit_x / panel_width_metres + 0.5F;
  const auto v = 0.5F - hit_y / panel_height_metres;
  constexpr float kBoundaryTolerance = 1.0e-5F;
  if (u < -kBoundaryTolerance || u > 1.0F + kBoundaryTolerance ||
      v < -kBoundaryTolerance || v > 1.0F + kBoundaryTolerance) {
    return std::nullopt;
  }

  const auto clamped_u = std::clamp(u, 0.0F, 1.0F);
  const auto clamped_v = std::clamp(v, 0.0F, 1.0F);
  const auto pixel_x = crop_x + static_cast<std::uint32_t>(
                                    std::lround(clamped_u * (crop_width - 1)));
  const auto pixel_y = crop_y + static_cast<std::uint32_t>(
                                    std::lround(clamped_v * (crop_height - 1)));
  return PanelPointerMapping{clamped_u, clamped_v, distance, pixel_x, pixel_y};
}

bool pointer_origin_within_reach(math::Vec3 pointer_origin,
                                 math::Vec3 head_position,
                                 float maximum_reach_metres) {
  if (!finite(pointer_origin) || !finite(head_position) ||
      !std::isfinite(maximum_reach_metres) || maximum_reach_metres <= 0.0F) {
    throw std::invalid_argument("Invalid spatial pointer reach inputs");
  }
  const auto dx = pointer_origin.x - head_position.x;
  const auto dy = pointer_origin.y - head_position.y;
  const auto dz = pointer_origin.z - head_position.z;
  return dx * dx + dy * dy + dz * dz <=
         maximum_reach_metres * maximum_reach_metres;
}

}  // namespace darktidevr::core
