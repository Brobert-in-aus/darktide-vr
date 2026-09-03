#include "tracked_cuff_mesh.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <compare>
#include <cstdint>
#include <iostream>
#include <map>
#include <stdexcept>

namespace {

bool near(float left, float right, float epsilon = 0.00001F) {
  return std::abs(left - right) <= epsilon;
}

struct QuantizedPoint {
  std::int32_t x{};
  std::int32_t y{};
  std::int32_t z{};

  auto operator<=>(const QuantizedPoint&) const = default;
};

using Edge = std::array<QuantizedPoint, 2>;

QuantizedPoint quantize(darktidevr::math::Vec3 point) {
  constexpr float units_per_metre = 1000000.0F;
  return {static_cast<std::int32_t>(std::lround(point.x * units_per_metre)),
          static_cast<std::int32_t>(std::lround(point.y * units_per_metre)),
          static_cast<std::int32_t>(std::lround(point.z * units_per_metre))};
}

void add_edge(std::map<Edge, std::uint32_t>& edges,
              darktidevr::math::Vec3 left,
              darktidevr::math::Vec3 right) {
  Edge edge{quantize(left), quantize(right)};
  if (edge[1] < edge[0]) {
    std::swap(edge[0], edge[1]);
  }
  ++edges[edge];
}

}  // namespace

int main() {
  using darktidevr::harness::TrackedCuffDimensions;
  using darktidevr::harness::make_tracked_cuff_mesh;

  const TrackedCuffDimensions dimensions{};
  const auto vertices = make_tracked_cuff_mesh(dimensions);
  if (vertices.size() !=
      static_cast<std::size_t>(dimensions.radial_segments) * 12U) {
    std::cerr << "Tracked cuff vertex-count contract failed\n";
    return 1;
  }

  float minimum_y = vertices.front().position.y;
  float maximum_y = minimum_y;
  float maximum_abs_x{};
  float maximum_abs_z{};
  for (const auto& vertex : vertices) {
    minimum_y = std::min(minimum_y, vertex.position.y);
    maximum_y = std::max(maximum_y, vertex.position.y);
    maximum_abs_x = std::max(maximum_abs_x, std::abs(vertex.position.x));
    maximum_abs_z = std::max(maximum_abs_z, std::abs(vertex.position.z));
    const auto normal_length =
        std::sqrt(vertex.normal.x * vertex.normal.x +
                  vertex.normal.y * vertex.normal.y +
                  vertex.normal.z * vertex.normal.z);
    if (!std::isfinite(vertex.position.x) ||
        !std::isfinite(vertex.position.y) ||
        !std::isfinite(vertex.position.z) || !near(normal_length, 1.0F)) {
      std::cerr << "Tracked cuff finite/unit-normal contract failed\n";
      return 1;
    }
  }

  std::map<Edge, std::uint32_t> edges;
  for (std::size_t vertex = 0; vertex < vertices.size(); vertex += 3U) {
    const auto& a = vertices[vertex];
    const auto& b = vertices[vertex + 1U];
    const auto& c = vertices[vertex + 2U];
    add_edge(edges, a.position, b.position);
    add_edge(edges, b.position, c.position);
    add_edge(edges, c.position, a.position);
    const darktidevr::math::Vec3 ab{b.position.x - a.position.x,
                                    b.position.y - a.position.y,
                                    b.position.z - a.position.z};
    const darktidevr::math::Vec3 ac{c.position.x - a.position.x,
                                    c.position.y - a.position.y,
                                    c.position.z - a.position.z};
    const darktidevr::math::Vec3 face{
        ab.y * ac.z - ab.z * ac.y, ab.z * ac.x - ab.x * ac.z,
        ab.x * ac.y - ab.y * ac.x};
    const darktidevr::math::Vec3 average_normal{
        a.normal.x + b.normal.x + c.normal.x,
        a.normal.y + b.normal.y + c.normal.y,
        a.normal.z + b.normal.z + c.normal.z};
    const auto facing = face.x * average_normal.x +
                        face.y * average_normal.y +
                        face.z * average_normal.z;
    if (!(facing > 0.0F)) {
      std::cerr << "Tracked cuff outward-winding contract failed\n";
      return 1;
    }
  }
  if (std::any_of(edges.begin(), edges.end(),
                  [](const auto& edge) { return edge.second != 2U; })) {
    std::cerr << "Tracked cuff watertight topology contract failed\n";
    return 1;
  }
  if (!near(minimum_y, dimensions.back_y_metres) ||
      !near(maximum_y, dimensions.front_y_metres) ||
      !near(maximum_abs_x, dimensions.front_radius_x_metres) ||
      !near(maximum_abs_z, dimensions.front_radius_z_metres)) {
    std::cerr << "Tracked cuff bounds contract failed\n";
    return 1;
  }

  bool rejected_invalid{};
  try {
    auto invalid = dimensions;
    invalid.radial_segments = 2;
    (void)make_tracked_cuff_mesh(invalid);
  } catch (const std::invalid_argument&) {
    rejected_invalid = true;
  }
  if (!rejected_invalid) {
    std::cerr << "Tracked cuff validation contract failed\n";
    return 1;
  }

  std::cout << "Tracked cuff mesh contract passed vertices=" << vertices.size()
            << " triangles=" << vertices.size() / 3U << '\n';
  return 0;
}
