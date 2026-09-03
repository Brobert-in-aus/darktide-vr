#pragma once

#include "core/output_layout.h"
#include "core/shared_generated_frame_state.h"

#include <Windows.h>
#include <d3d12.h>
#include <dxgiformat.h>
#include <wrl/client.h>

#include <array>
#include <string>

namespace darktidevr::bridge {

struct SharedEyeSurfaceNames {
  std::array<std::wstring, 2> eyes;
  std::wstring ready_fence;
  std::wstring consumed_fence;
};

struct SharedEyeSurfaceDescription {
  core::PixelExtent extent{};
  DXGI_FORMAT format{DXGI_FORMAT_UNKNOWN};
};

struct OpenedEyeSurfaces {
  std::array<Microsoft::WRL::ComPtr<ID3D12Resource>, 2> eyes;
  Microsoft::WRL::ComPtr<ID3D12Fence> ready_fence;
  Microsoft::WRL::ComPtr<ID3D12Fence> consumed_fence;
  SharedEyeSurfaceDescription description{};
};

struct SharedTextureNames {
  std::wstring texture;
  std::wstring ready_fence;
  std::wstring consumed_fence;
};

struct OpenedSharedTexture {
  Microsoft::WRL::ComPtr<ID3D12Resource> texture;
  Microsoft::WRL::ComPtr<ID3D12Fence> ready_fence;
  Microsoft::WRL::ComPtr<ID3D12Fence> consumed_fence;
  SharedEyeSurfaceDescription description{};
};

struct SharedGeneratedSurfaceNames {
  std::array<std::wstring, core::kSharedGeneratedFrameSlotCount> textures;
  std::wstring ready_fence;
  std::wstring consumed_fence;
};

struct OpenedGeneratedSurfaces {
  std::array<Microsoft::WRL::ComPtr<ID3D12Resource>,
             core::kSharedGeneratedFrameSlotCount>
      textures;
  Microsoft::WRL::ComPtr<ID3D12Fence> ready_fence;
  Microsoft::WRL::ComPtr<ID3D12Fence> consumed_fence;
  SharedEyeSurfaceDescription description{};
};

// Opens producer-owned NT handles by name. The producer retains ownership and
// signals ready_fence after transitioning both surfaces to COMMON. The
// consumer signals consumed_fence with the same value only after its queue has
// finished reading both surfaces. Keeping the eye resources independent avoids
// coupling XR resolution to the desktop mirror or to an SBS back buffer.
OpenedEyeSurfaces open_shared_eye_surfaces(
    ID3D12Device* device, const SharedEyeSurfaceNames& names,
    SharedEyeSurfaceDescription expected);

// Opens one independently paced producer-owned texture. This is used for
// alpha UI surfaces: menu production must not consume, stall, or replace a
// stereo eye pair.
OpenedSharedTexture open_shared_texture(
    ID3D12Device* device, const SharedTextureNames& names,
    SharedEyeSurfaceDescription expected);

// Opens the bounded generated-output ring. Sequence N maps to
// generated_frame_slot(N); ready fence N makes that slot and its metadata
// visible, while consumed fence N releases it back to the producer.
OpenedGeneratedSurfaces open_shared_generated_surfaces(
    ID3D12Device* device, const SharedGeneratedSurfaceNames& names,
    SharedEyeSurfaceDescription expected);

// D3D12 reports UINT64_MAX when a fence's device has been removed. Treating
// that sentinel as an ordinary monotonically increasing value can queue an
// impossible cross-device wait and permanently pin the consumer to a dead
// producer generation.
bool shared_fence_values_healthy(std::uint64_t ready,
                                 std::uint64_t consumed) noexcept;

}  // namespace darktidevr::bridge
