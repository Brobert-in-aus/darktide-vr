#pragma once

#include "producer/streamline_eye_tags.h"
#include <cstring>

namespace darktidevr::producer {

// Owns a stable pair of descriptors and constants for a future submitter.
// Does not own textures, call SL, or prove that camera history is temporally
// correct. The submitter must attach these to the matching target frame token
// and keep inputs immutable until StreamlineInputLifetime allows retirement.
class StreamlineStereoTags {
 public:
  using Constants = streamline_2_7_30::Constants;
  using Inputs = std::array<std::array<StreamlineTagInput, 3>, 2>;
  using UiInputs = std::array<StreamlineTagInput, 2>;

  bool prepare(std::uint32_t width, std::uint32_t height,
               const std::array<std::uint32_t, 2>& viewports,
               const std::array<Constants, 2>& constants,
               const Inputs& inputs, const UiInputs* ui = nullptr) noexcept {
    ready_ = false;
    constants_ = {};
    viewports_ = {};
    if (!viewports[0] || !viewports[1] || viewports[0] == viewports[1])
      return false;
    for (const auto& value : constants) {
      // Reject extension chains instead of retaining borrowed pointers or
      // silently stripping semantics we do not understand.
      if (value.base.next || value.base.struct_version != 2 ||
          std::memcmp(&value.base.struct_type, &constants_type_,
                      sizeof(constants_type_)) != 0) return false;
    }
    // Different roles can alias across eyes too, not just depth vs depth.
    for (const auto& left : inputs[0])
      for (const auto& right : inputs[1])
        if (left.native == right.native) return false;
    if (ui) {
      if ((*ui)[0].native == (*ui)[1].native) return false;
      for (const auto& overlay : *ui)
        for (const auto& eye : inputs)
          for (const auto& input : eye)
            if (overlay.native == input.native) return false;
    }
    if (!eyes_[0].prepare(0, width, height, inputs[0], ui ? &(*ui)[0] : nullptr) ||
        !eyes_[1].prepare(1, width, height, inputs[1], ui ? &(*ui)[1] : nullptr)) return false;
    constants_ = constants; // Preserve per-eye matrices, jitter and reset flags.
    viewports_ = viewports;
    ready_ = true;
    return true;
  }

  const StreamlineEyeTags* eye(std::uint32_t index) const noexcept {
    return ready_ && index < 2 ? &eyes_[index] : nullptr;
  }
  const Constants* constants(std::uint32_t index) const noexcept {
    return ready_ && index < 2 ? &constants_[index] : nullptr;
  }
  std::uint32_t viewport(std::uint32_t index) const noexcept {
    return ready_ && index < 2 ? viewports_[index] : 0;
  }

 private:
  static constexpr streamline_2_7_30::StructType constants_type_{
      0xdcd35ad7, 0x4e4a, 0x4bad, {0xa9, 0x0c, 0xe0, 0xc4, 0x9e, 0xb2, 0x3a, 0xfe}};
  bool ready_{};
  std::array<StreamlineEyeTags, 2> eyes_{};
  std::array<Constants, 2> constants_{};
  std::array<std::uint32_t, 2> viewports_{};
};
} // namespace darktidevr::producer
