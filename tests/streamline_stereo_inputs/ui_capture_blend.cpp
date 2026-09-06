#include "producer/ui_capture_blend.h"
#include <stdexcept>
#include <iostream>

void check(bool value) { if (!value) throw std::runtime_error("UI blend contract"); }
int main() {
  using darktidevr::producer::ui_capture_blend_supported;
  D3D12_RENDER_TARGET_BLEND_DESC valid{};
  valid.BlendEnable = TRUE;
  valid.SrcBlend = D3D12_BLEND_SRC_ALPHA;
  valid.DestBlend = D3D12_BLEND_INV_SRC_ALPHA;
  valid.BlendOp = D3D12_BLEND_OP_ADD;
  valid.SrcBlendAlpha = D3D12_BLEND_ONE;
  valid.DestBlendAlpha = D3D12_BLEND_INV_SRC_ALPHA;
  valid.BlendOpAlpha = D3D12_BLEND_OP_ADD;
  valid.RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
  check(ui_capture_blend_supported(valid, false));
  valid.SrcBlend = D3D12_BLEND_ONE; // Already-premultiplied material.
  check(ui_capture_blend_supported(valid, false));
  check(!ui_capture_blend_supported(valid, true));
  using darktidevr::producer::ui_capture_blend_needs_alpha_fix;
  check(!ui_capture_blend_needs_alpha_fix(valid, false));
  auto opaque_gui = valid;
  opaque_gui.SrcBlend = D3D12_BLEND_SRC_ALPHA;
  opaque_gui.SrcBlendAlpha = D3D12_BLEND_SRC_ALPHA;
  check(!ui_capture_blend_supported(opaque_gui, false));
  check(ui_capture_blend_needs_alpha_fix(opaque_gui, false));
  check(!ui_capture_blend_needs_alpha_fix(opaque_gui, true));
  opaque_gui.DestBlend = D3D12_BLEND_ONE;
  check(!ui_capture_blend_needs_alpha_fix(opaque_gui, false)); // Additive colour is still unsafe.
  for (unsigned scenario = 0; scenario < 9; ++scenario) {
    auto invalid = valid;
    switch (scenario) {
      case 0: invalid.BlendEnable = FALSE; break;
      case 1: invalid.LogicOpEnable = TRUE; break;
      case 2: invalid.SrcBlend = D3D12_BLEND_DEST_COLOR; break;
      case 3: invalid.DestBlend = D3D12_BLEND_ONE; break;
      case 4: invalid.BlendOp = D3D12_BLEND_OP_MAX; break;
      case 5: invalid.SrcBlendAlpha = D3D12_BLEND_SRC_ALPHA; break;
      case 6: invalid.DestBlendAlpha = D3D12_BLEND_ZERO; break;
      case 7: invalid.BlendOpAlpha = D3D12_BLEND_OP_MAX; break;
      case 8: invalid.RenderTargetWriteMask = 7; break;
    }
    check(!ui_capture_blend_supported(invalid, false));
  }
  std::cout << "ui_capture_blend=pass\n";
}
