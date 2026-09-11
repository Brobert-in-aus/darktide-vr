#pragma once

#include "core/xr_math.h"

#include <cstdint>
#include <mutex>

namespace darktidevr::core {

inline constexpr wchar_t kSharedHeadPoseName[] =
    L"Local\\DarktideVR-head-pose-v12";

struct EyeFrustumHalfAngles {
  float left{};
  float right{};
  float down{};
  float up{};
};

struct SharedHeadPoseSample {
  std::uint64_t sequence{};
  // Distinguishes equal sequence values published by consecutive XR writers.
  // Assigned by the transport reader rather than the caller.
  std::uint64_t transport_generation{};
  // Increments whenever the runtime rebuilds its horizon-locked HMD origin.
  // Consumers use this to rebase pose-derived body calibration atomically.
  std::uint32_t recenter_generation{};
  math::Pose pose{};
  // Cumulative recenter-local OpenXR horizontal displacement assigned to the
  // character body rather than the bounded camera lean.
  math::Vec3 body_follow_offset{};
  float render_vertical_fov_radians{};
  float render_aspect_ratio{};
  std::uint32_t render_width{};
  std::uint32_t render_height{};
  EyeFrustumHalfAngles render_frusta[2]{};
  // Runtime-provided separation between the two located XrView positions.
  // This is the user's calibrated headset IPD, not a population-average guess.
  float ipd_metres{0.064F};
  // Floor-relative centre-eye height from an OpenXR STAGE reference space.
  // Zero means the active runtime does not expose a valid floor space.
  float floor_eye_height_metres{};
};

struct SharedRenderedEyePairPose {
  std::uint64_t ready_value{};
  // VR gameplay-orientation generation committed by the Lua seam before this
  // pair was captured. A menu-resume consumer can reject pairs produced by
  // the outgoing modal camera without guessing a frame count.
  std::uint64_t gameplay_generation{};
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
  std::uint64_t transport_generation() const;
  bool read_rendered_pair(SharedRenderedEyePairPose& pair) const;
  std::uint64_t read_gameplay_generation() const;
  std::uint64_t read_eye_surface_generation() const;
  std::uint64_t read_menu_surface_generation() const;

 private:
  void* mapping_{};
  void* view_{};
};

struct SharedHeadPoseReadDiagnostics {
  const char* reason{"unavailable"};
  std::uint64_t now_ms{};
  std::uint64_t published_ms{};
  std::uint64_t sequence{};
  std::uint64_t epoch_before{};
  std::uint64_t epoch_after{};
  unsigned attempts{};
};

class SharedHeadPoseReader {
 public:
  SharedHeadPoseReader() = default;
  ~SharedHeadPoseReader();

  SharedHeadPoseReader(const SharedHeadPoseReader&) = delete;
  SharedHeadPoseReader& operator=(const SharedHeadPoseReader&) = delete;

  bool read(SharedHeadPoseSample& sample,
            SharedHeadPoseReadDiagnostics* diagnostics = nullptr);
  bool publish_rendered_pair(const SharedRenderedEyePairPose& pair);
  bool publish_gameplay_generation(std::uint64_t generation);
  std::uint64_t advance_eye_surface_generation();
  std::uint64_t advance_menu_surface_generation();

 private:
  bool ensure_open();
  // The producer shares one reader between the Lua and render threads.
  std::mutex open_mutex_;

  void* mapping_{};
  void* view_{};
};

}  // namespace darktidevr::core
