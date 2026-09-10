#pragma once
#include <d3d12.h>
#include <array>
#include <utility>

namespace darktidevr::xr {

// Destinations must already be COPY_DEST. The producer's packed source remains
// owned until the caller signals its consumed fence after queue execution.
inline void copy_packed_original(
    ID3D12GraphicsCommandList* commands, ID3D12Resource* packed,
    UINT width, UINT height, const std::array<ID3D12Resource*, 2>& outputs,
    bool separate_outputs, const std::array<ID3D12Resource*, 2>& cached,
    const std::array<ID3D12Resource*, 2>& readbacks = {},
    const D3D12_PLACED_SUBRESOURCE_FOOTPRINT& footprint = {}) {
  D3D12_RESOURCE_BARRIER barrier{};
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barrier.Transition = {packed, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_SOURCE};
  commands->ResourceBarrier(1, &barrier);
  D3D12_TEXTURE_COPY_LOCATION source{};
  source.pResource = packed;
  source.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
  for (UINT eye = 0; eye < 2; ++eye) {
    const D3D12_BOX box{eye * width, 0, 0, (eye + 1) * width, height, 1};
    D3D12_TEXTURE_COPY_LOCATION destination{};
    destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    destination.pResource = outputs[separate_outputs ? eye : 0];
    commands->CopyTextureRegion(&destination, 0, separate_outputs ? 0 : eye * height,
        0, &source, &box);
    destination.pResource = cached[eye];
    commands->CopyTextureRegion(&destination, 0, 0, 0, &source, &box);
    if (readbacks[eye]) {
      destination.pResource = readbacks[eye];
      destination.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
      destination.PlacedFootprint = footprint;
      commands->CopyTextureRegion(&destination, 0, 0, 0, &source, &box);
    }
  }
  std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
  commands->ResourceBarrier(1, &barrier);
}

} // namespace darktidevr::xr
