#pragma once
#include <d3d12.h>
#include <array>

namespace darktidevr::producer {
// Evidence is local to a single recording. Inherited/implicit states are never
// guessed. Enhanced barriers and capacity overflow exclude the recording.
struct BillboardResourceState {
  struct Entry { ID3D12Resource* resource{}; bool render_target{}; };
  std::array<Entry, 128> entries{};
  bool excluded{};
  void unknown() noexcept { entries = {}; excluded = true; }
  void observe(UINT count, const D3D12_RESOURCE_BARRIER* barriers) noexcept {
    if (excluded || !barriers) return;
    for (UINT i = 0; i < count; ++i) {
      const auto& barrier = barriers[i];
      if (barrier.Type == D3D12_RESOURCE_BARRIER_TYPE_ALIASING) {
        entries = {}; continue;
      }
      if (barrier.Type != D3D12_RESOURCE_BARRIER_TYPE_TRANSITION) continue;
      auto* resource = barrier.Transition.pResource;
      if (!resource) { unknown(); return; }
      Entry* entry{};
      for (auto& candidate : entries) {
        if (candidate.resource == resource) { entry = &candidate; break; }
        if (!candidate.resource && !entry) entry = &candidate;
      }
      if (!entry) { unknown(); return; }
      entry->resource = resource;
      entry->render_target = barrier.Flags == D3D12_RESOURCE_BARRIER_FLAG_NONE &&
          (barrier.Transition.Subresource == 0 ||
           barrier.Transition.Subresource == D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES) &&
          barrier.Transition.StateAfter == D3D12_RESOURCE_STATE_RENDER_TARGET;
    }
  }
  bool known_render_target(ID3D12Resource* resource) const noexcept {
    if (excluded || !resource) return false;
    for (const auto& entry : entries)
      if (entry.resource == resource) return entry.render_target;
    return false;
  }
};
}  // namespace darktidevr::producer
