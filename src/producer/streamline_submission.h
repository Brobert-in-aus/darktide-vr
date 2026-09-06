#pragma once

#include "core/streamline_input_lifetime.h"
#include "producer/streamline_stereo_tags.h"

namespace darktidevr::producer {

// ABI-compatible entry points obtained from the existing Streamline hooks.
// Caller must select the game's established tagging mode and run on the Present
// thread. This adapter never changes DLSS options or issues an extra Present.
struct StreamlineSubmissionApi {
  int (*constants)(const void*, const void*, const void*){};
  int (*tags)(const void*, const void*, const void*, std::uint32_t, void*){};
  int (*legacy_tags)(const void*, const void*, std::uint32_t, void*){};
};

class StreamlineSubmission {
 public:
  enum class Phase { idle, prepared, staged, cleanup_required, awaiting_completion };
  enum class Tagging { frame_based, legacy };
  enum class ConstantsMode { submit, already_supplied };

  bool prepare(std::uint64_t id, std::uint32_t width,
               std::uint32_t height, const std::array<std::uint32_t, 2>& viewports,
               const std::array<StreamlineStereoTags::Constants, 2>& constants,
               const StreamlineStereoTags::Inputs& inputs,
               const StreamlineStereoTags::UiInputs* ui = nullptr) noexcept {
    if (phase_ != Phase::idle ||
        !pair_.prepare(width, height, viewports, constants, inputs, ui) ||
        !lifetime_.begin(id)) return false;
    id_ = id;
    frame_ = nullptr;
    touched_ = {};
    for (std::uint32_t eye = 0; eye < 2; ++eye) {
      viewports_[eye] = {{nullptr, viewport_type_, 1}, viewports[eye]};
      for (std::uint32_t tag = 0; tag < pair_.eye(eye)->count(); ++tag) {
        clear_[eye][tag] = pair_.eye(eye)->data()[tag];
        clear_[eye][tag].resource = nullptr;
        clear_[eye][tag].extent = {};
      }
    }
    phase_ = Phase::prepared;
    return true;
  }

  // Snapshot preparation can precede Present by many frames. Bind the current
  // game's token only at submission; a token retained during readback may have
  // been recycled by Streamline. The caller must verify its Present ownership.
  bool stage(StreamlineSubmissionApi api, void* frame, void* commands,
             Tagging tagging = Tagging::frame_based,
             ConstantsMode constants_mode = ConstantsMode::submit) noexcept {
    if (phase_ != Phase::prepared ||
        (constants_mode == ConstantsMode::submit && !api.constants) || !frame || !commands ||
        (tagging == Tagging::frame_based ? !api.tags : !api.legacy_tags))
      return false;
    frame_ = frame;
    api_ = api;
    tagging_ = tagging;
    // A failing tag call may have partially installed tags. Track the attempt,
    // not only success, and clear both touched viewports on any failure.
    for (std::uint32_t eye = 0; eye < 2; ++eye) {
      // already_supplied is only valid for inputs captured from the exact game
      // frame whose constants were observed; the native binding gate proves it.
      if (constants_mode == ConstantsMode::submit) {
        last_result_ = api.constants(pair_.constants(eye), frame_, &viewports_[eye]);
        if (last_result_ != 0) {
          phase_ = Phase::cleanup_required;
          return false;
        }
      }
      touched_[eye] = true;
      last_result_ = set_tags(eye, pair_.eye(eye)->data(), commands);
      if (last_result_ != 0) {
        phase_ = Phase::cleanup_required;
        return false;
      }
    }
    phase_ = Phase::staged;
    return true;
  }

  // Mark immediately before invoking Present. Even a failed Present may have
  // consumed inputs; its HRESULT is not permission to release them.
  bool begin_present() noexcept {
    if (phase_ != Phase::staged || !lifetime_.mark_presented(id_)) return false;
    phase_ = Phase::awaiting_completion;
    return true;
  }

  bool clear_tags(void* commands) noexcept {
    if (phase_ == Phase::idle || !commands) return false;
    bool success = true;
    for (std::uint32_t eye = 0; eye < 2; ++eye) {
      if (!touched_[eye]) continue;
      const auto result = set_tags(eye, clear_[eye].data(), commands);
      if (result == 0) touched_[eye] = false;
      else { last_result_ = result; success = false; }
    }
    if (success) {
      lifetime_.mark_tags_cleared(id_);
      // Prevent staging or presenting a batch after cancellation.
      if (phase_ != Phase::awaiting_completion) phase_ = Phase::cleanup_required;
    }
    return success;
  }

  bool record_ticket(std::uint64_t id, std::uint32_t eye,
                     std::uintptr_t fence, std::uint64_t value) noexcept {
    return lifetime_.record_ticket(id, eye, fence, value);
  }
  // Called on the same Present thread after a successor has installed BOTH
  // eye tag sets. Retiring this owner must not clear the successor's viewport
  // bindings. Resource release still requires this owner's completion tickets.
  bool replace_tags_with(const StreamlineSubmission& successor) noexcept {
    if (phase_ != Phase::awaiting_completion || successor.phase_ != Phase::staged ||
        successor.id_ <= id_ || tagging_ != successor.tagging_ ||
        api_.tags != successor.api_.tags || api_.legacy_tags != successor.api_.legacy_tags)
      return false;
    for (std::uint32_t eye = 0; eye < 2; ++eye) {
      if (!touched_[eye] || !successor.touched_[eye] ||
          viewports_[eye].value != successor.viewports_[eye].value) return false;
      // Omitting a UI tag does not remove a previous UI binding. A change of
      // tag set requires explicit cleanup, rather than replacement retirement.
      if (pair_.eye(eye)->count() != successor.pair_.eye(eye)->count()) return false;
      const auto& extent = pair_.eye(eye)->data()[3].extent;
      const auto& next_extent = successor.pair_.eye(eye)->data()[3].extent;
      if (std::memcmp(&extent, &next_extent, sizeof(extent)) != 0) return false;
      // Separate owners cannot keep immutable inputs if any resource is shared,
      // including aliases across different eye/role combinations.
      for (std::uint32_t role = 0; role < pair_.eye(eye)->count(); ++role)
        for (std::uint32_t next_eye = 0; next_eye < 2; ++next_eye)
          for (std::uint32_t next_role = 0;
               next_role < successor.pair_.eye(next_eye)->count(); ++next_role)
            if (pair_.eye(eye)->data()[role].resource &&
                successor.pair_.eye(next_eye)->data()[next_role].resource &&
                pair_.eye(eye)->data()[role].resource->native ==
                successor.pair_.eye(next_eye)->data()[next_role].resource->native)
              return false;
    }
    touched_ = {};
    return lifetime_.mark_tags_cleared(id_); // Removed by replacement, not null tags.
  }
  bool observe_completion(std::uint64_t id, std::uint32_t eye,
                          std::uintptr_t fence, std::uint64_t value) noexcept {
    return lifetime_.observe_completion(id, eye, fence, value);
  }
  bool retire() noexcept {
    if (!lifetime_.release(id_)) return false;
    phase_ = Phase::idle;
    frame_ = nullptr;
    return true;
  }
  Phase phase() const noexcept { return phase_; }
  int last_result() const noexcept { return last_result_; }

 private:
  int set_tags(std::uint32_t eye,
               const streamline_2_7_30::ResourceTag* tags,
               void* commands) noexcept {
    return tagging_ == Tagging::frame_based
        ? api_.tags(frame_, &viewports_[eye], tags, pair_.eye(eye)->count(), commands)
        : api_.legacy_tags(&viewports_[eye], tags, pair_.eye(eye)->count(), commands);
  }
  static constexpr streamline_2_7_30::StructType viewport_type_{
      0x171b6435, 0x9b3c, 0x4fc8, {0x99, 0x94, 0xfb, 0xe5, 0x25, 0x69, 0xaa, 0xa4}};
  Phase phase_{Phase::idle};
  Tagging tagging_{Tagging::frame_based};
  std::uint64_t id_{};
  void* frame_{};
  int last_result_{};
  StreamlineSubmissionApi api_{};
  StreamlineStereoTags pair_;
  core::StreamlineInputLifetime lifetime_;
  std::array<streamline_2_7_30::ViewportHandle, 2> viewports_{};
  std::array<std::array<streamline_2_7_30::ResourceTag, 5>, 2> clear_{};
  std::array<bool, 2> touched_{};
};
} // namespace darktidevr::producer
