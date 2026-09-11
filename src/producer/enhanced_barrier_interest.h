#pragma once
#include <d3d12.h>

namespace darktidevr::producer {
// The protected bookkeeping only logs textures or records PRESENT targets.
// PRESENT aliases COMMON, so COMMON must conservatively take this path too.
inline bool enhanced_barriers_need_capture_lock(
    UINT32 count, const D3D12_BARRIER_GROUP* groups, bool log_resources) noexcept {
  if (!groups) return false;
  for (UINT32 group_index = 0; group_index < count; ++group_index) {
    const auto& group = groups[group_index];
    if (group.Type != D3D12_BARRIER_TYPE_TEXTURE || !group.pTextureBarriers)
      continue;
    for (UINT32 index = 0; index < group.NumBarriers; ++index) {
      if (log_resources ||
          group.pTextureBarriers[index].LayoutAfter == D3D12_BARRIER_LAYOUT_PRESENT)
        return true;
    }
  }
  return false;
}
}
