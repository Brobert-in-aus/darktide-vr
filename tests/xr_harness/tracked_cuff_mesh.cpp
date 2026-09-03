#include "tracked_cuff_mesh.h"

#include <array>
#include <cmath>
#include <numbers>
#include <stdexcept>

namespace darktidevr::harness {
namespace {

math::Vec3 normalized(math::Vec3 value) {
  const auto length =
      std::sqrt(value.x * value.x + value.y * value.y + value.z * value.z);
  if (!(length > 0.0F)) {
    throw std::invalid_argument("Tracked cuff normal must be nonzero");
  }
  return {value.x / length, value.y / length, value.z / length};
}

void add_triangle(std::vector<TrackedCuffVertex>& vertices,
                  const std::array<math::Vec3, 3>& positions,
                  const std::array<math::Vec3, 3>& normals) {
  for (std::size_t index = 0; index < positions.size(); ++index) {
    vertices.push_back({positions[index], normals[index]});
  }
}

}  // namespace

std::vector<TrackedCuffVertex> make_tracked_cuff_mesh(
    const TrackedCuffDimensions& dimensions) {
  if (dimensions.radial_segments < 3 ||
      !(dimensions.front_y_metres > dimensions.back_y_metres) ||
      !(dimensions.front_radius_x_metres > 0.0F) ||
      !(dimensions.front_radius_z_metres > 0.0F) ||
      !(dimensions.back_radius_x_metres > 0.0F) ||
      !(dimensions.back_radius_z_metres > 0.0F)) {
    throw std::invalid_argument("Invalid tracked cuff dimensions");
  }

  std::vector<TrackedCuffVertex> vertices;
  vertices.reserve(static_cast<std::size_t>(dimensions.radial_segments) * 12U);
  const math::Vec3 front_center{0.0F, dimensions.front_y_metres, 0.0F};
  const math::Vec3 back_center{0.0F, dimensions.back_y_metres, 0.0F};
  const math::Vec3 front_normal{0.0F, 1.0F, 0.0F};
  const math::Vec3 back_normal{0.0F, -1.0F, 0.0F};

  for (std::uint32_t segment = 0; segment < dimensions.radial_segments;
       ++segment) {
    const auto angle0 = 2.0F * std::numbers::pi_v<float> *
                        static_cast<float>(segment) /
                        static_cast<float>(dimensions.radial_segments);
    const auto angle1 = 2.0F * std::numbers::pi_v<float> *
                        static_cast<float>(segment + 1U) /
                        static_cast<float>(dimensions.radial_segments);
    const auto cosine0 = std::cos(angle0);
    const auto sine0 = std::sin(angle0);
    const auto cosine1 = std::cos(angle1);
    const auto sine1 = std::sin(angle1);
    const math::Vec3 front0{
        cosine0 * dimensions.front_radius_x_metres,
        dimensions.front_y_metres,
        sine0 * dimensions.front_radius_z_metres};
    const math::Vec3 front1{
        cosine1 * dimensions.front_radius_x_metres,
        dimensions.front_y_metres,
        sine1 * dimensions.front_radius_z_metres};
    const math::Vec3 back0{cosine0 * dimensions.back_radius_x_metres,
                           dimensions.back_y_metres,
                           sine0 * dimensions.back_radius_z_metres};
    const math::Vec3 back1{cosine1 * dimensions.back_radius_x_metres,
                           dimensions.back_y_metres,
                           sine1 * dimensions.back_radius_z_metres};
    const auto side0 = normalized(
        {cosine0 / dimensions.front_radius_x_metres, 0.0F,
         sine0 / dimensions.front_radius_z_metres});
    const auto side1 = normalized(
        {cosine1 / dimensions.front_radius_x_metres, 0.0F,
         sine1 / dimensions.front_radius_z_metres});

    add_triangle(vertices, {back0, front0, front1}, {side0, side0, side1});
    add_triangle(vertices, {back0, front1, back1}, {side0, side1, side1});
    add_triangle(vertices, {front_center, front1, front0},
                 {front_normal, front_normal, front_normal});
    add_triangle(vertices, {back_center, back0, back1},
                 {back_normal, back_normal, back_normal});
  }
  return vertices;
}

}  // namespace darktidevr::harness
