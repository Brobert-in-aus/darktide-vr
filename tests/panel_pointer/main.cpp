#include "core/panel_pointer.h"

#include <cmath>
#include <iostream>
#include <stdexcept>

namespace {

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

}  // namespace

void test_menu_pointer_input();

int main() {
  try {
    using darktidevr::core::PointerRay;
    using darktidevr::core::map_pointer_to_panel;
    using darktidevr::math::Pose;

    const Pose panel{{}, {0.0F, 0.0F, -2.0F}};
    auto hit = map_pointer_to_panel(
        PointerRay{}, panel, 2.0F, 2.0F, 1920, 1080, 0, 0, 1920, 1080);
    expect(hit && std::abs(hit->u - 0.5F) < 1.0e-5F &&
               std::abs(hit->v - 0.5F) < 1.0e-5F &&
               std::abs(hit->distance_metres - 2.0F) < 1.0e-5F &&
               hit->source_x == 960 && hit->source_y == 540,
           "Centre ray must map to the centre source pixel");

    hit = map_pointer_to_panel(
        PointerRay{{-1.0F, 1.0F, 0.0F}, {0.0F, 0.0F, -1.0F}}, panel,
        2.0F, 2.0F, 2048, 2048, 100, 200, 1000, 500);
    expect(hit && hit->source_x == 100 && hit->source_y == 200,
           "Panel top-left must map to crop top-left");

    hit = map_pointer_to_panel(
        PointerRay{{1.0F, -1.0F, 0.0F}, {0.0F, 0.0F, -1.0F}}, panel,
        2.0F, 2.0F, 2048, 2048, 100, 200, 1000, 500);
    expect(hit && hit->source_x == 1099 && hit->source_y == 699,
           "Panel bottom-right must map inside the final crop pixel");

    hit = map_pointer_to_panel(
        PointerRay{{1.01F, 0.0F, 0.0F}, {0.0F, 0.0F, -1.0F}}, panel,
        2.0F, 2.0F, 1920, 1080, 0, 0, 1920, 1080);
    expect(!hit, "A ray outside the finite panel must miss");

    hit = map_pointer_to_panel(
        PointerRay{{0.0F, 0.0F, -3.0F}, {0.0F, 0.0F, -1.0F}}, panel,
        2.0F, 2.0F, 1920, 1080, 0, 0, 1920, 1080);
    expect(!hit, "A ray pointing away from the panel must miss");

    expect(darktidevr::core::pointer_origin_within_reach(
               {0.5F, 0.0F, 0.0F}, {}, 1.5F) &&
               !darktidevr::core::pointer_origin_within_reach(
                   {2.0F, 0.0F, 0.0F}, {}, 1.5F),
           "Controller reach envelope mismatch");

    const Pose rotated{
        darktidevr::math::from_axis_angle({0.0F, 1.0F, 0.0F},
                                          -1.57079632679F),
        {2.0F, 0.0F, 0.0F}};
    hit = map_pointer_to_panel(
        PointerRay{{}, {1.0F, 0.0F, 0.0F}}, rotated, 2.0F, 2.0F, 800, 600,
        0, 0, 800, 600);
    expect(hit && std::abs(hit->u - 0.5F) < 1.0e-5F &&
               std::abs(hit->v - 0.5F) < 1.0e-5F,
           "Mapping must respect a rotated panel pose");

    test_menu_pointer_input();

    std::cout << "panel_pointer.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "panel_pointer: " << error.what() << '\n';
    return 1;
  }
}
