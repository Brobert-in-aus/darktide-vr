#pragma once

#include "core/xr_math.h"

#include <cstdint>

namespace darktidevr::core {

inline constexpr wchar_t kSharedHeadPoseName[] =
    L"Local\\DarktideVR-head-pose-v6";

struct EyeFrustumHalfAngles {
  float left{};
  float right{};
  float down{};
  float up{};
};

struct SharedHeadPoseSample {
  std::uint64_t sequence{};
  math::Pose pose{};
  float render_vertical_fov_radians{};
  float render_aspect_ratio{};
  std::uint32_t render_width{};
  std::uint32_t render_height{};
  EyeFrustumHalfAngles render_frusta[2]{};
  // Runtime-provided separation between the two located XrView positions.
  // This is the user's calibrated headset IPD, not a population-average guess.
  float ipd_metres{0.064F};
};

struct SharedRenderedEyePairPose {
  std::uint64_t ready_value{};
  std::uint64_t eye_pose_sequences[2]{};
  float vertical_fov_radians[2]{};
  float aspect_ratios[2]{};
};

// Single-writer named-memory transport from the OpenXR process to Darktide.
// The packet is protected by a cross-process seqlock; neither side waits.
class SharedHeadPoseWriter {
 public:
  SharedHeadPoseWriter();
  ~SharedHeadPoseWriter();

  SharedHeadPoseWriter(const SharedHeadPoseWriter&) = delete;
  SharedHeadPoseWriter& operator=(const SharedHeadPoseWriter&) = delete;

  bool publish(const SharedHeadPoseSample& sample);
  bool read_rendered_pair(SharedRenderedEyePairPose& pair) const;

 private:
  void* mapping_{};
  void* view_{};
};

class SharedHeadPoseReader {
 public:
  SharedHeadPoseReader() = default;
  ~SharedHeadPoseReader();

  SharedHeadPoseReader(const SharedHeadPoseReader&) = delete;
  SharedHeadPoseReader& operator=(const SharedHeadPoseReader&) = delete;

  bool read(SharedHeadPoseSample& sample);
  bool publish_rendered_pair(const SharedRenderedEyePairPose& pair);

 private:
  bool ensure_open();

  void* mapping_{};
  void* view_{};
};

}  // namespace darktidevr::core
