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

  bool prepare(std::uint64_t id, std::uint32_t width,
               std::uint32_t height, const std::array<std::uint32_t, 2>& viewports,
               const std::array<StreamlineStereoTags::Constants, 2>& constants,
               const StreamlineStereoTags::Inputs& inputs) noexcept {
    if (phase_ != Phase::idle ||
        !pair_.prepare(width, height, viewports, constants, inputs) ||
        !lifetime_.begin(id)) return false;
    id_ = id;
    frame_ = nullptr;
    touched_ = {};
    for (std::uint32_t eye = 0; eye < 2; ++eye) {
      viewports_[eye] = {{nullptr, viewport_type_, 1}, viewports[eye]};
      for (std::uint32_t tag = 0; tag < 4; ++tag) {
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
             Tagging tagging = Tagging::frame_based) noexcept {
    if (phase_ != Phase::prepared || !api.constants || !frame || !commands ||
        (tagging == Tagging::frame_based ? !api.tags : !api.legacy_tags))
      return false;
    frame_ = frame;
    api_ = api;
    tagging_ = tagging;
    // A failing tag call may have partially installed tags. Track the attempt,
    // not only success, and clear both touched viewports on any failure.
    for (std::uint32_t eye = 0; eye < 2; ++eye) {
      last_result_ = api.constants(pair_.constants(eye), frame_, &viewports_[eye]);
      if (last_result_ != 0) {
        phase_ = Phase::cleanup_required;
        return false;
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
        ? api_.tags(frame_, &viewports_[eye], tags, 4, commands)
        : api_.legacy_tags(&viewports_[eye], tags, 4, commands);
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
  std::array<std::array<streamline_2_7_30::ResourceTag, 4>, 2> clear_{};
  std::array<bool, 2> touched_{};
};
} // namespace darktidevr::producer
