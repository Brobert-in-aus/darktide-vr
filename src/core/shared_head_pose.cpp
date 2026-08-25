#include "core/shared_head_pose.h"

#include <Windows.h>

#include <cmath>
#include <limits>
#include <stdexcept>

namespace darktidevr::core {
namespace {

struct SharedLayout {
  volatile LONG64 epoch{};
  volatile LONG64 sequence{};
  volatile LONG64 published_tick_ms{};
  float position_x{};
  float position_y{};
  float position_z{};
  float orientation_x{};
  float orientation_y{};
  float orientation_z{};
  float orientation_w{1.0F};
  float render_vertical_fov{};
  float render_aspect_ratio{};
  volatile LONG render_width{};
  volatile LONG render_height{};
  float eye0_left{};
  float eye0_right{};
  float eye0_down{};
  float eye0_up{};
  float eye1_left{};
  float eye1_right{};
  float eye1_down{};
  float eye1_up{};
  volatile LONG64 pair_epoch{};
  volatile LONG64 pair_ready_value{};
  volatile LONG64 pair_eye0_pose_sequence{};
  volatile LONG64 pair_eye1_pose_sequence{};
  float pair_eye0_vertical_fov{};
  float pair_eye1_vertical_fov{};
  float pair_eye0_aspect_ratio{};
  float pair_eye1_aspect_ratio{};
};

static_assert(alignof(SharedLayout) >= alignof(LONG64));

bool valid(const SharedHeadPoseSample& sample) {
  const auto& p = sample.pose.position;
  const auto& q = sample.pose.orientation;
  const auto norm =
      std::sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
  const auto valid_frustum = [](const EyeFrustumHalfAngles& frustum) {
    constexpr float half_pi = 1.57079633F;
    return std::isfinite(frustum.left) && std::isfinite(frustum.right) &&
           std::isfinite(frustum.down) && std::isfinite(frustum.up) &&
           frustum.left > -half_pi && frustum.right < half_pi &&
           frustum.down > -half_pi && frustum.up < half_pi &&
           frustum.left < frustum.right && frustum.down < frustum.up;
  };
  return sample.sequence != 0 &&
         sample.sequence <=
             static_cast<std::uint64_t>(std::numeric_limits<LONG64>::max()) &&
         std::isfinite(p.x) && std::isfinite(p.y) &&
         std::isfinite(p.z) && std::isfinite(q.x) && std::isfinite(q.y) &&
         std::isfinite(q.z) && std::isfinite(q.w) &&
         std::abs(norm - 1.0F) <= 0.01F &&
         std::isfinite(sample.render_vertical_fov_radians) &&
         sample.render_vertical_fov_radians > 0.0F &&
         sample.render_vertical_fov_radians < 3.14159265F &&
         std::isfinite(sample.render_aspect_ratio) &&
         sample.render_aspect_ratio > 0.0F &&
         sample.render_width >= 640 && sample.render_width <= 7680 &&
         sample.render_height >= 640 && sample.render_height <= 7680 &&
         valid_frustum(sample.render_frusta[0]) &&
         valid_frustum(sample.render_frusta[1]);
}

bool valid(const SharedRenderedEyePairPose& pair) {
  constexpr auto max_shared_counter =
      static_cast<std::uint64_t>(std::numeric_limits<LONG64>::max());
  return pair.ready_value != 0 && pair.ready_value <= max_shared_counter &&
         pair.eye_pose_sequences[0] != 0 &&
         pair.eye_pose_sequences[1] != 0 &&
         pair.eye_pose_sequences[0] <= max_shared_counter &&
         pair.eye_pose_sequences[1] <= max_shared_counter &&
         std::isfinite(pair.vertical_fov_radians[0]) &&
         std::isfinite(pair.vertical_fov_radians[1]) &&
         std::isfinite(pair.aspect_ratios[0]) &&
         std::isfinite(pair.aspect_ratios[1]) &&
         pair.vertical_fov_radians[0] > 0.0F &&
         pair.vertical_fov_radians[0] < 3.14159265F &&
         pair.vertical_fov_radians[1] > 0.0F &&
         pair.vertical_fov_radians[1] < 3.14159265F &&
         pair.aspect_ratios[0] > 0.0F && pair.aspect_ratios[1] > 0.0F;
}

void close_mapping(void*& mapping, void*& view) {
  if (view) {
    UnmapViewOfFile(view);
    view = nullptr;
  }
  if (mapping) {
    CloseHandle(static_cast<HANDLE>(mapping));
    mapping = nullptr;
  }
}

}  // namespace

SharedHeadPoseWriter::SharedHeadPoseWriter() {
  mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                0, sizeof(SharedLayout),
                                kSharedHeadPoseName);
  if (!mapping_) {
    throw std::runtime_error("CreateFileMapping(shared head pose) failed");
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_ALL_ACCESS, 0,
                        0, sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    throw std::runtime_error("MapViewOfFile(shared head pose) failed");
  }

  // A reader in Darktide can keep the named mapping alive after a harness
  // restart. Establish a clean writer session so neither the last pose nor its
  // rendered-pair tag can be mistaken for data from the new XR session.
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedExchange64(&data.epoch, 1);
  InterlockedExchange64(&data.sequence, 0);
  InterlockedExchange64(&data.published_tick_ms, 0);
  data.render_vertical_fov = 0.0F;
  data.render_aspect_ratio = 0.0F;
  data.render_width = 0;
  data.render_height = 0;
  data.eye0_left = 0.0F;
  data.eye0_right = 0.0F;
  data.eye0_down = 0.0F;
  data.eye0_up = 0.0F;
  data.eye1_left = 0.0F;
  data.eye1_right = 0.0F;
  data.eye1_down = 0.0F;
  data.eye1_up = 0.0F;
  MemoryBarrier();
  InterlockedExchange64(&data.epoch, 2);
  InterlockedExchange64(&data.pair_epoch, 1);
  InterlockedExchange64(&data.pair_ready_value, 0);
  InterlockedExchange64(&data.pair_eye0_pose_sequence, 0);
  InterlockedExchange64(&data.pair_eye1_pose_sequence, 0);
  data.pair_eye0_vertical_fov = 0.0F;
  data.pair_eye1_vertical_fov = 0.0F;
  data.pair_eye0_aspect_ratio = 0.0F;
  data.pair_eye1_aspect_ratio = 0.0F;
  MemoryBarrier();
  InterlockedExchange64(&data.pair_epoch, 2);
}

SharedHeadPoseWriter::~SharedHeadPoseWriter() {
  close_mapping(mapping_, view_);
}

bool SharedHeadPoseWriter::publish(const SharedHeadPoseSample& sample) {
  if (!valid(sample)) {
    return false;
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedIncrement64(&data.epoch);
  data.position_x = sample.pose.position.x;
  data.position_y = sample.pose.position.y;
  data.position_z = sample.pose.position.z;
  data.orientation_x = sample.pose.orientation.x;
  data.orientation_y = sample.pose.orientation.y;
  data.orientation_z = sample.pose.orientation.z;
  data.orientation_w = sample.pose.orientation.w;
  data.render_vertical_fov = sample.render_vertical_fov_radians;
  data.render_aspect_ratio = sample.render_aspect_ratio;
  data.render_width = static_cast<LONG>(sample.render_width);
  data.render_height = static_cast<LONG>(sample.render_height);
  data.eye0_left = sample.render_frusta[0].left;
  data.eye0_right = sample.render_frusta[0].right;
  data.eye0_down = sample.render_frusta[0].down;
  data.eye0_up = sample.render_frusta[0].up;
  data.eye1_left = sample.render_frusta[1].left;
  data.eye1_right = sample.render_frusta[1].right;
  data.eye1_down = sample.render_frusta[1].down;
  data.eye1_up = sample.render_frusta[1].up;
  InterlockedExchange64(&data.sequence,
                        static_cast<LONG64>(sample.sequence));
  InterlockedExchange64(&data.published_tick_ms,
                        static_cast<LONG64>(GetTickCount64()));
  MemoryBarrier();
  InterlockedIncrement64(&data.epoch);
  return true;
}

bool SharedHeadPoseWriter::read_rendered_pair(
    SharedRenderedEyePairPose& pair) const {
  const auto& data = *static_cast<const SharedLayout*>(view_);
  for (int attempt = 0; attempt < 4; ++attempt) {
    const auto before = data.pair_epoch;
    MemoryBarrier();
    if ((before & 1) != 0) {
      continue;
    }
    SharedRenderedEyePairPose candidate{
        static_cast<std::uint64_t>(data.pair_ready_value),
        {static_cast<std::uint64_t>(data.pair_eye0_pose_sequence),
         static_cast<std::uint64_t>(data.pair_eye1_pose_sequence)},
        {data.pair_eye0_vertical_fov, data.pair_eye1_vertical_fov},
        {data.pair_eye0_aspect_ratio, data.pair_eye1_aspect_ratio}};
    MemoryBarrier();
    const auto after = data.pair_epoch;
    if (before == after && (after & 1) == 0 && valid(candidate)) {
      pair = candidate;
      return true;
    }
  }
  return false;
}

SharedHeadPoseReader::~SharedHeadPoseReader() {
  close_mapping(mapping_, view_);
}

bool SharedHeadPoseReader::ensure_open() {
  if (view_) {
    return true;
  }
  mapping_ = OpenFileMappingW(FILE_MAP_ALL_ACCESS, FALSE,
                              kSharedHeadPoseName);
  if (!mapping_) {
    return false;
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_ALL_ACCESS, 0,
                        0, sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    return false;
  }
  return true;
}

bool SharedHeadPoseReader::read(SharedHeadPoseSample& sample) {
  if (!ensure_open()) {
    return false;
  }
  const auto& data = *static_cast<const SharedLayout*>(view_);
  for (int attempt = 0; attempt < 4; ++attempt) {
    const auto before = data.epoch;
    MemoryBarrier();
    if ((before & 1) != 0) {
      continue;
    }
    SharedHeadPoseSample candidate{};
    candidate.sequence = static_cast<std::uint64_t>(data.sequence);
    const auto published_tick_ms =
        static_cast<std::uint64_t>(data.published_tick_ms);
    candidate.pose.position =
        {data.position_x, data.position_y, data.position_z};
    candidate.pose.orientation = {data.orientation_x, data.orientation_y,
                                  data.orientation_z, data.orientation_w};
    candidate.render_vertical_fov_radians = data.render_vertical_fov;
    candidate.render_aspect_ratio = data.render_aspect_ratio;
    candidate.render_width = static_cast<std::uint32_t>(data.render_width);
    candidate.render_height = static_cast<std::uint32_t>(data.render_height);
    candidate.render_frusta[0] =
        {data.eye0_left, data.eye0_right, data.eye0_down, data.eye0_up};
    candidate.render_frusta[1] =
        {data.eye1_left, data.eye1_right, data.eye1_down, data.eye1_up};
    MemoryBarrier();
    const auto after = data.epoch;
    const auto now_ms = GetTickCount64();
    const auto fresh = now_ms >= published_tick_ms &&
                       now_ms - published_tick_ms <= 250;
    if (before == after && (after & 1) == 0 && fresh && valid(candidate)) {
      sample = candidate;
      return true;
    }
  }
  return false;
}

bool SharedHeadPoseReader::publish_rendered_pair(
    const SharedRenderedEyePairPose& pair) {
  if (!ensure_open() || !valid(pair)) {
    return false;
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedIncrement64(&data.pair_epoch);
  InterlockedExchange64(&data.pair_ready_value,
                        static_cast<LONG64>(pair.ready_value));
  InterlockedExchange64(&data.pair_eye0_pose_sequence,
                        static_cast<LONG64>(pair.eye_pose_sequences[0]));
  InterlockedExchange64(&data.pair_eye1_pose_sequence,
                        static_cast<LONG64>(pair.eye_pose_sequences[1]));
  data.pair_eye0_vertical_fov = pair.vertical_fov_radians[0];
  data.pair_eye1_vertical_fov = pair.vertical_fov_radians[1];
  data.pair_eye0_aspect_ratio = pair.aspect_ratios[0];
  data.pair_eye1_aspect_ratio = pair.aspect_ratios[1];
  MemoryBarrier();
  InterlockedIncrement64(&data.pair_epoch);
  return true;
}

}  // namespace darktidevr::core
