#pragma once
#include <d3d12.h>
#include <array>
#include <utility>

namespace darktidevr::producer {
// Owned eye snapshots are COPY_DEST; the separate packed target is PRESENT.
// Extents and formats are checked by the caller. Keep a shared source legal.
template<class Commands>
void record_stereo_color_pack(Commands* commands, ID3D12Resource* target,
    const std::array<ID3D12Resource*, 2>& eyes, unsigned eye_width) {
  std::array<D3D12_RESOURCE_BARRIER, 3> barriers{};
  barriers[0].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barriers[0].Transition = {target, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_COPY_DEST};
  unsigned count = 1;
  for (unsigned eye = 0; eye < 2; ++eye) {
    if (eye && eyes[eye] == eyes[0]) continue;
    auto& barrier = barriers[count++];
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition = {eyes[eye], D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COPY_SOURCE};
  }
  commands->ResourceBarrier(count, barriers.data());
  for (unsigned eye = 0; eye < 2; ++eye) {
    D3D12_TEXTURE_COPY_LOCATION from{}, to{};
    from.pResource = eyes[eye]; from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    to.pResource = target; to.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands->CopyTextureRegion(&to, eye * eye_width, 0, 0, &from, nullptr);
  }
  for (unsigned i = 0; i < count; ++i)
    std::swap(barriers[i].Transition.StateBefore, barriers[i].Transition.StateAfter);
  commands->ResourceBarrier(count, barriers.data());
}

}
