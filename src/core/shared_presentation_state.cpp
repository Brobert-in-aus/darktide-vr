#include "core/shared_object_name.h"
#include "core/shared_presentation_state.h"

#include <Windows.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace darktidevr::core {
namespace {

struct SharedLayout {
  volatile LONG64 epoch{};
  volatile LONG64 writer_generation{};
  volatile LONG64 published_at_ms{};
  volatile LONG64 sequence{};
  volatile LONG mode{};
  volatile LONG source_width{};
  volatile LONG source_height{};
  volatile LONG crop_x{};
  volatile LONG crop_y{};
  volatile LONG crop_width{};
  volatile LONG crop_height{};
  float maximum_panel_width_metres{2.0F};
  float maximum_panel_height_metres{2.0F};
  volatile LONG body_panel_pose_valid{};
  float body_panel_pose[7]{};
  volatile LONG keyboard_mouse{};
  volatile LONG64 recenter_request{};
  volatile LONG controllers_disabled{};
  volatile LONG64 haptic_request{};
  volatile LONG haptic_hands{};
  float haptic_amplitude{};
  volatile LONG haptic_duration_ms{};
  float haptic_frequency_hz{};
};

static_assert(alignof(SharedLayout) >= alignof(LONG64));

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

bool immersive_projection_active(SharedPresentationMode mode) {
  return mode == SharedPresentationMode::stereo_world ||
         mode == SharedPresentationMode::world_anchored_menu ||
         mode == SharedPresentationMode::flat_menu;
}

bool flat_interactive_active(SharedPresentationMode mode) {
  return mode == SharedPresentationMode::flat_interactive ||
         mode == SharedPresentationMode::flat_interactive_native_aspect;
}

bool flat_interactive_uses_eye_aspect(SharedPresentationMode mode,
                                      bool shared_eyes_open) {
  // With the shared eyes open the engine draws every flat board into its
  // eye-sized private backbuffer, and the canvas blit squashes that whole
  // buffer into the 16:9 menu texture. A panel at the eye aspect restores the
  // geometry. Loading and video boards (mode 2) come from the same canvas,
  // so they take the same panel; shown 16:9 they were squashed.
  return (flat_interactive_active(mode) ||
          mode == SharedPresentationMode::flat_loading_or_cinematic) &&
         shared_eyes_open;
}

bool same_flat_panel_anchor_identity(const SharedPresentationState& left,
                                     const SharedPresentationState& right) {
  if (left.transport_generation != right.transport_generation ||
      left.mode != right.mode ||
      left.body_panel_pose_valid != right.body_panel_pose_valid) {
    return false;
  }
  if (left.mode != SharedPresentationMode::world_anchored_menu ||
      !left.body_panel_pose_valid) {
    return true;
  }
  const auto& a = left.body_panel_pose;
  const auto& b = right.body_panel_pose;
  return a.position.x == b.position.x && a.position.y == b.position.y &&
         a.position.z == b.position.z &&
         a.orientation.x == b.orientation.x &&
         a.orientation.y == b.orientation.y &&
         a.orientation.z == b.orientation.z &&
         a.orientation.w == b.orientation.w;
}

bool valid_presentation_state(const SharedPresentationState& state) {
  const auto raw_mode = static_cast<std::uint32_t>(state.mode);
  const auto dimensions_valid =
      state.source_width >= 1 && state.source_width <= 16384 &&
      state.source_height >= 1 && state.source_height <= 16384 &&
      state.crop_width >= 1 && state.crop_height >= 1 &&
      state.crop_width <= state.source_width &&
      state.crop_height <= state.source_height &&
      state.crop_x <= state.source_width - state.crop_width &&
      state.crop_y <= state.source_height - state.crop_height;
  const auto& pose = state.body_panel_pose;
  const auto pose_finite = std::isfinite(pose.position.x) &&
                           std::isfinite(pose.position.y) &&
                           std::isfinite(pose.position.z) &&
                           std::isfinite(pose.orientation.x) &&
                           std::isfinite(pose.orientation.y) &&
                           std::isfinite(pose.orientation.z) &&
                           std::isfinite(pose.orientation.w);
  const auto position_limit = 100.0F;
  const auto position_plausible =
      std::abs(pose.position.x) <= position_limit &&
      std::abs(pose.position.y) <= position_limit &&
      std::abs(pose.position.z) <= position_limit;
  const auto quaternion_length =
      pose.orientation.x * pose.orientation.x +
      pose.orientation.y * pose.orientation.y +
      pose.orientation.z * pose.orientation.z +
      pose.orientation.w * pose.orientation.w;
  const auto pose_valid = !state.body_panel_pose_valid ||
                          (pose_finite && position_plausible &&
                           quaternion_length >= 0.99F &&
                           quaternion_length <= 1.01F);
  const auto world_anchor_available =
      state.mode != SharedPresentationMode::world_anchored_menu ||
      state.body_panel_pose_valid;
  return state.sequence != 0 &&
         state.sequence <=
             static_cast<std::uint64_t>(std::numeric_limits<LONG64>::max()) &&
         raw_mode <= static_cast<std::uint32_t>(SharedPresentationMode::error) &&
         dimensions_valid &&
         std::isfinite(state.maximum_panel_width_metres) &&
         std::isfinite(state.maximum_panel_height_metres) &&
         state.maximum_panel_width_metres > 0.0F &&
         state.maximum_panel_width_metres <= 10.0F &&
         state.maximum_panel_height_metres > 0.0F &&
         state.maximum_panel_height_metres <= 10.0F && pose_valid &&
         world_anchor_available;
}

bool presentation_state_fresh(const SharedPresentationState& state,
                              std::uint64_t now_ms,
                              std::uint64_t maximum_age_ms) {
  return state.published_at_ms != 0 && now_ms >= state.published_at_ms &&
         now_ms - state.published_at_ms <= maximum_age_ms;
}

bool RecenterRequestTracker::observe(const SharedPresentationState& state) {
  if (state.transport_generation != generation) {
    generation = state.transport_generation;
    count = state.recenter_request;
    return false;
  }
  if (state.recenter_request == count) {
    return false;
  }
  count = state.recenter_request;
  return true;
}

bool HapticRequestTracker::observe(const SharedPresentationState& state,
                                   HapticPulse& pulse) {
  if (state.transport_generation != generation) {
    generation = state.transport_generation;
    count = state.haptic_request;
    return false;
  }
  if (state.haptic_request == count) {
    return false;
  }
  count = state.haptic_request;
  pulse.hands = state.haptic_hands & (kHapticLeftHand | kHapticRightHand);
  pulse.amplitude = std::isfinite(state.haptic_amplitude)
                        ? std::clamp(state.haptic_amplitude, 0.0F, 1.0F)
                        : 0.0F;
  pulse.duration_ms = std::clamp(state.haptic_duration_ms, std::uint32_t{1},
                                 kHapticMaximumDurationMs);
  pulse.frequency_hz = std::isfinite(state.haptic_frequency_hz) &&
                               state.haptic_frequency_hz > 0.0F
                           ? state.haptic_frequency_hz
                           : 0.0F;
  return pulse.hands != 0 && pulse.amplitude > 0.0F;
}

SharedPresentationStateWriter::SharedPresentationStateWriter() {
  mapping_ = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                0, sizeof(SharedLayout),
                                shared_object_name(kSharedPresentationStateName).c_str());
  if (!mapping_) {
    throw std::runtime_error(
        "CreateFileMapping(shared presentation state) failed");
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_ALL_ACCESS, 0,
                        0, sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    throw std::runtime_error("MapViewOfFile(shared presentation state) failed");
  }

  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedExchange64(&data.epoch, 1);
  InterlockedIncrement64(&data.writer_generation);
  InterlockedExchange64(&data.published_at_ms, 0);
  InterlockedExchange64(&data.sequence, 0);
  data.mode = static_cast<LONG>(SharedPresentationMode::disabled);
  data.source_width = 1;
  data.source_height = 1;
  data.crop_x = 0;
  data.crop_y = 0;
  data.crop_width = 1;
  data.crop_height = 1;
  data.maximum_panel_width_metres = 2.0F;
  data.maximum_panel_height_metres = 2.0F;
  data.body_panel_pose_valid = 0;
  data.body_panel_pose[6] = 1.0F;
  data.keyboard_mouse = 0;
  InterlockedExchange64(&data.recenter_request, 0);
  data.controllers_disabled = 0;
  InterlockedExchange64(&data.haptic_request, 0);
  data.haptic_hands = 0;
  data.haptic_amplitude = 0.0F;
  data.haptic_duration_ms = 0;
  data.haptic_frequency_hz = 0.0F;
  MemoryBarrier();
  InterlockedExchange64(&data.epoch, 2);
}

SharedPresentationStateWriter::~SharedPresentationStateWriter() {
  close_mapping(mapping_, view_);
}

bool SharedPresentationStateWriter::publish(
    const SharedPresentationState& state) {
  if (!valid_presentation_state(state)) {
    return false;
  }
  auto& data = *static_cast<SharedLayout*>(view_);
  InterlockedIncrement64(&data.epoch);
  data.mode = static_cast<LONG>(state.mode);
  data.source_width = static_cast<LONG>(state.source_width);
  data.source_height = static_cast<LONG>(state.source_height);
  data.crop_x = static_cast<LONG>(state.crop_x);
  data.crop_y = static_cast<LONG>(state.crop_y);
  data.crop_width = static_cast<LONG>(state.crop_width);
  data.crop_height = static_cast<LONG>(state.crop_height);
  data.maximum_panel_width_metres = state.maximum_panel_width_metres;
  data.maximum_panel_height_metres = state.maximum_panel_height_metres;
  data.body_panel_pose_valid = state.body_panel_pose_valid ? 1 : 0;
  data.body_panel_pose[0] = state.body_panel_pose.position.x;
  data.body_panel_pose[1] = state.body_panel_pose.position.y;
  data.body_panel_pose[2] = state.body_panel_pose.position.z;
  data.body_panel_pose[3] = state.body_panel_pose.orientation.x;
  data.body_panel_pose[4] = state.body_panel_pose.orientation.y;
  data.body_panel_pose[5] = state.body_panel_pose.orientation.z;
  data.body_panel_pose[6] = state.body_panel_pose.orientation.w;
  data.keyboard_mouse = state.keyboard_mouse ? 1 : 0;
  InterlockedExchange64(&data.recenter_request,
                        static_cast<LONG64>(state.recenter_request));
  data.controllers_disabled = state.controllers_disabled ? 1 : 0;
  InterlockedExchange64(&data.haptic_request,
                        static_cast<LONG64>(state.haptic_request));
  data.haptic_hands = static_cast<LONG>(state.haptic_hands);
  data.haptic_amplitude = state.haptic_amplitude;
  data.haptic_duration_ms = static_cast<LONG>(state.haptic_duration_ms);
  data.haptic_frequency_hz = state.haptic_frequency_hz;
  InterlockedExchange64(&data.published_at_ms,
                        static_cast<LONG64>(GetTickCount64()));
  InterlockedExchange64(&data.sequence, static_cast<LONG64>(state.sequence));
  MemoryBarrier();
  InterlockedIncrement64(&data.epoch);
  return true;
}

SharedPresentationStateReader::~SharedPresentationStateReader() {
  close_mapping(mapping_, view_);
}

bool SharedPresentationStateReader::ensure_open() {
  if (view_) {
    return true;
  }
  mapping_ = OpenFileMappingW(FILE_MAP_READ, FALSE,
                              shared_object_name(kSharedPresentationStateName).c_str());
  if (!mapping_) {
    return false;
  }
  view_ = MapViewOfFile(static_cast<HANDLE>(mapping_), FILE_MAP_READ, 0, 0,
                        sizeof(SharedLayout));
  if (!view_) {
    close_mapping(mapping_, view_);
    return false;
  }
  return true;
}

bool SharedPresentationStateReader::read(SharedPresentationState& state) {
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
    SharedPresentationState candidate{
        static_cast<std::uint64_t>(data.sequence),
        static_cast<SharedPresentationMode>(data.mode),
        static_cast<std::uint32_t>(data.source_width),
        static_cast<std::uint32_t>(data.source_height),
        static_cast<std::uint32_t>(data.crop_x),
        static_cast<std::uint32_t>(data.crop_y),
        static_cast<std::uint32_t>(data.crop_width),
        static_cast<std::uint32_t>(data.crop_height),
        data.maximum_panel_width_metres,
        data.maximum_panel_height_metres,
        data.body_panel_pose_valid != 0,
        {{data.body_panel_pose[3], data.body_panel_pose[4],
          data.body_panel_pose[5], data.body_panel_pose[6]},
         {data.body_panel_pose[0], data.body_panel_pose[1],
          data.body_panel_pose[2]}},
        static_cast<std::uint64_t>(data.writer_generation),
        static_cast<std::uint64_t>(data.published_at_ms),
        data.keyboard_mouse != 0,
        static_cast<std::uint64_t>(data.recenter_request),
        data.controllers_disabled != 0,
        static_cast<std::uint64_t>(data.haptic_request),
        static_cast<std::uint32_t>(data.haptic_hands),
        data.haptic_amplitude,
        static_cast<std::uint32_t>(data.haptic_duration_ms),
        data.haptic_frequency_hz};
    MemoryBarrier();
    const auto after = data.epoch;
    if (before == after && (after & 1) == 0 &&
        candidate.transport_generation != 0 &&
        valid_presentation_state(candidate)) {
      state = candidate;
      return true;
    }
  }
  return false;
}

}  // namespace darktidevr::core
