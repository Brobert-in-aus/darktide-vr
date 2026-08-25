#include "adapters/darktide/semantic_camera.h"

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void expect_near(float actual, float expected, float tolerance,
                 const char* message) {
  if (std::abs(actual - expected) > tolerance) {
    throw std::runtime_error(message);
  }
}

}  // namespace

int main() {
  try {
    using darktidevr::darktide::parse_semantic_camera_line;

    const auto sample = parse_semantic_camera_line(
        "08:16:02.000 [Lua] [MOD] DARKTIDEVR_CAMERA schema=1 "
        "viewport=player1 position=0.852718,-88.641678,101.887756 "
        "rotation=0.00336080,-0.16083823,0.98675966,-0.02061885 "
        "vfov_rad=0.959931");
    expect(sample.has_value(), "Valid semantic camera line should parse");
    expect(sample->viewport == "player1", "Viewport should be retained");
    expect_near(sample->pose.position.y, -88.641678F, 0.0001F,
                "Position should parse losslessly enough for camera use");
    expect_near(sample->vertical_fov_rad, 0.959931F, 0.000001F,
                "Vertical FOV should parse");

    expect(!parse_semantic_camera_line("ordinary log line"),
           "Unrelated lines must be ignored");
    expect(!parse_semantic_camera_line(
               "DARKTIDEVR_CAMERA schema=2 viewport=player1 "
               "position=0,0,0 rotation=0,0,0,1 vfov_rad=1.0"),
           "Unknown schemas must fail closed");
    expect(!parse_semantic_camera_line(
               "DARKTIDEVR_CAMERA schema=1 viewport=player1 "
               "position=0,0,0 rotation=0,0,0,0.5 vfov_rad=1.0"),
           "Non-unit quaternions must fail closed");
    expect(!parse_semantic_camera_line(
               "DARKTIDEVR_CAMERA schema=1 viewport=player1 "
               "position=0,0,0 rotation=0,0,0,1 vfov_rad=4.0"),
           "Implausible FOV must fail closed");

    std::cout << "semantic_camera.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "semantic_camera: " << error.what() << '\n';
    return 1;
  }
}
