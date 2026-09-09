#pragma once
#include <d3d12.h>
#include <array>
#include <utility>

namespace darktidevr::producer {
struct StereoInputCopy {
  ID3D12Resource* source{};
  ID3D12Resource* destination{};
  D3D12_RESOURCE_STATES source_state{};
};

// Inputs have already passed extent/state validation. Destinations are separate
// owned COPY_DEST textures. Preserve the old ordering if any source aliases.
template<class Commands>
void record_stereo_input_copies(Commands* commands,
    const std::array<StereoInputCopy, 5>& copies, unsigned count) {
  bool independent = true;
  for (unsigned i = 0; i < count; ++i)
    for (unsigned j = 0; j < i; ++j)
      independent = independent && copies[i].source != copies[j].source;
  std::array<D3D12_RESOURCE_BARRIER, 5> barriers{};
  unsigned barrier_count{};
  for (unsigned i = 0; i < count; ++i) {
    const auto& copy = copies[i];
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition = {copy.source, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                          copy.source_state, D3D12_RESOURCE_STATE_COPY_SOURCE};
    const bool transition = copy.source_state != D3D12_RESOURCE_STATE_COPY_SOURCE;
    if (independent) {
      if (transition) barriers[barrier_count++] = barrier;
    } else {
      if (transition) commands->ResourceBarrier(1, &barrier);
      commands->CopyResource(copy.destination, copy.source);
      std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
      if (transition) commands->ResourceBarrier(1, &barrier);
    }
  }
  if (!independent) return;
  if (barrier_count) commands->ResourceBarrier(barrier_count, barriers.data());
  for (unsigned i = 0; i < count; ++i)
    commands->CopyResource(copies[i].destination, copies[i].source);
  for (unsigned i = 0; i < barrier_count; ++i)
    std::swap(barriers[i].Transition.StateBefore, barriers[i].Transition.StateAfter);
  if (barrier_count) commands->ResourceBarrier(barrier_count, barriers.data());
}
}
