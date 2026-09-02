#pragma once

#include <cstdint>

namespace darktidevr::core {

// Shared D3D12 textures are a one-slot mailbox. The producer may reuse the
// slot only after the consumer has acknowledged the last published value.
// UINT64_MAX is D3D12's device-removed sentinel, never a valid acknowledgement.
constexpr bool shared_mailbox_writable(std::uint64_t ready,
                                       std::uint64_t consumed) noexcept {
  return ready != UINT64_MAX && consumed != UINT64_MAX &&
         (ready == 0 || consumed >= ready);
}

// A render target may be backed by either a typed or typeless game resource
// while using the same typed RTV. The shared texture is sampled by a second
// process, so its stable identity is the typed RTV contract, not the game's
// interchangeable backing-resource format.
constexpr std::uint32_t canonical_shared_render_target_format(
    std::uint32_t source_format, std::uint32_t render_target_format) noexcept {
  return render_target_format != 0 ? render_target_format : source_format;
}

constexpr bool shared_render_target_description_matches(
    std::uint64_t current_width, std::uint32_t current_height,
    std::uint32_t current_resource_format, std::uint64_t requested_width,
    std::uint32_t requested_height, std::uint32_t requested_source_format,
    std::uint32_t requested_render_target_format) noexcept {
  return current_width == requested_width &&
         current_height == requested_height &&
         current_resource_format == canonical_shared_render_target_format(
                                        requested_source_format,
                                        requested_render_target_format);
}

}  // namespace darktidevr::core
