#include "producer/enhanced_barrier_interest.h"
#include <array>
#include <cstdio>

int main() {
  using darktidevr::producer::enhanced_barriers_need_capture_lock;
  std::array<D3D12_TEXTURE_BARRIER, 2> textures{};
  textures[0].LayoutAfter = D3D12_BARRIER_LAYOUT_RENDER_TARGET;
  textures[1].LayoutAfter = D3D12_BARRIER_LAYOUT_SHADER_RESOURCE;
  std::array<D3D12_BARRIER_GROUP, 3> groups{};
  groups[0].Type = D3D12_BARRIER_TYPE_GLOBAL;
  groups[1].Type = D3D12_BARRIER_TYPE_BUFFER;
  groups[2].Type = D3D12_BARRIER_TYPE_TEXTURE;
  groups[2].NumBarriers = 2;
  groups[2].pTextureBarriers = textures.data();
  if (enhanced_barriers_need_capture_lock(3, nullptr, true) ||
      enhanced_barriers_need_capture_lock(0, groups.data(), true) ||
      enhanced_barriers_need_capture_lock(3, groups.data(), false) ||
      !enhanced_barriers_need_capture_lock(3, groups.data(), true)) return 1;
  textures[1].LayoutAfter = D3D12_BARRIER_LAYOUT_PRESENT;
  if (!enhanced_barriers_need_capture_lock(3, groups.data(), false)) return 2;
  textures[1].LayoutAfter = D3D12_BARRIER_LAYOUT_COMMON;
  if (!enhanced_barriers_need_capture_lock(3, groups.data(), false)) return 3;
  groups[2].NumBarriers = 0;
  if (enhanced_barriers_need_capture_lock(3, groups.data(), true)) return 4;
  groups[2].NumBarriers = 2;
  groups[2].pTextureBarriers = nullptr;
  if (enhanced_barriers_need_capture_lock(3, groups.data(), true)) return 5;
  std::puts("enhanced_barrier_interest=pass mixed_groups diagnostic present common empty");
}
