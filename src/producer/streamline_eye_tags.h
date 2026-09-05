#pragma once

#include "producer/streamline_abi_2_7_30.h"
#include <array>
#include <cstdint>

namespace darktidevr::producer {

// Offline preparation only: no SL calls or GPU resource ownership. The eventual
// submitter must retain immutable inputs through Present, then clear their tags.
// GUIDs/type numbers/lifetimes follow the official Streamline v2.7.30 headers.
struct StreamlineTagInput {
  void* native{};
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint32_t state{~0U};
  std::uint32_t format{};
};

class StreamlineEyeTags {
 public:
  StreamlineEyeTags() = default;
  // Tags point into this object's resource array. Moving/copying would retain
  // pointers to the old owner; construct and prepare at the final address.
  StreamlineEyeTags(const StreamlineEyeTags&) = delete;
  StreamlineEyeTags& operator=(const StreamlineEyeTags&) = delete;
  StreamlineEyeTags(StreamlineEyeTags&&) = delete;
  StreamlineEyeTags& operator=(StreamlineEyeTags&&) = delete;

  bool prepare(std::uint32_t eye, std::uint32_t eye_width,
               std::uint32_t eye_height,
               const std::array<StreamlineTagInput, 3>& inputs) noexcept {
    ready_ = false;
    tags_ = {};
    resources_ = {};
    if (eye > 1 || eye_width == 0 || eye_width > (~0U / 2) || eye_height == 0)
      return false;
    for (std::size_t i = 0; i < inputs.size(); ++i) {
      const auto& input = inputs[i];
      if (!input.native || input.width == 0 || input.height == 0 ||
          input.state == ~0U || input.format == 0) return false;
      for (std::size_t j = 0; j < i; ++j)
        if (inputs[j].native == input.native) return false;
    }
    // Initial adapter supports matching depth/motion extents and full-eye
    // HUD-less color. More general subresource layouts need explicit support.
    if (inputs[0].width != inputs[1].width ||
        inputs[0].height != inputs[1].height ||
        inputs[2].width != eye_width || inputs[2].height != eye_height)
      return false;
    for (std::size_t i = 0; i < inputs.size(); ++i) {
      const auto& input = inputs[i];
      auto& resource = resources_[i];
      resource.base = {nullptr, resource_type_, 1};
      resource.type = streamline_2_7_30::ResourceType::texture_2d;
      resource.native = input.native;
      resource.state = input.state;
      resource.width = input.width;
      resource.height = input.height;
      resource.native_format = input.format;
      auto& tag = tags_[i];
      tag.base = {nullptr, tag_type_, 1};
      tag.resource = &resource;
      tag.type = static_cast<std::uint32_t>(i); // depth, motion, HUD-less
      tag.lifecycle = 1; // eValidUntilPresent
      tag.extent = {0, 0, input.width, input.height};
    }
    auto& backbuffer = tags_[3];
    backbuffer.base = {nullptr, tag_type_, 1};
    backbuffer.type = 53;
    // SL already owns the presented backbuffer; this tag supplies only subrect.
    backbuffer.extent = {0, eye * eye_width, eye_width, eye_height};
    ready_ = true;
    return true;
  }

  const streamline_2_7_30::ResourceTag* data() const noexcept {
    return ready_ ? tags_.data() : nullptr;
  }
  std::uint32_t count() const noexcept { return ready_ ? 4U : 0U; }

 private:
  static constexpr streamline_2_7_30::StructType resource_type_{
      0x3a9d70cf, 0x2418, 0x4b72, {0x83, 0x91, 0x13, 0xf8, 0x72, 0x1c, 0x72, 0x61}};
  static constexpr streamline_2_7_30::StructType tag_type_{
      0x4c6a5aad, 0xb445, 0x496c, {0x87, 0xff, 0x1a, 0xf3, 0x84, 0x5b, 0xe6, 0x53}};
  bool ready_{};
  std::array<streamline_2_7_30::Resource, 3> resources_{};
  std::array<streamline_2_7_30::ResourceTag, 4> tags_{};
};
} // namespace darktidevr::producer
