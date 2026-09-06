#pragma once
#include <d3d12.h>

namespace darktidevr::producer {
// Replaying a draw over transparent black only produces premultiplied UI when
// both colour and coverage compose with source-over. Do not invent coverage
// for additive/destination-dependent materials or pipelines that omit alpha.
inline bool ui_capture_blend_supported(const D3D12_RENDER_TARGET_BLEND_DESC& blend,
                                       bool alpha_to_coverage) noexcept {
  return !alpha_to_coverage && blend.BlendEnable && !blend.LogicOpEnable &&
      (blend.SrcBlend == D3D12_BLEND_SRC_ALPHA || blend.SrcBlend == D3D12_BLEND_ONE) &&
      blend.DestBlend == D3D12_BLEND_INV_SRC_ALPHA && blend.BlendOp == D3D12_BLEND_OP_ADD &&
      blend.SrcBlendAlpha == D3D12_BLEND_ONE &&
      blend.DestBlendAlpha == D3D12_BLEND_INV_SRC_ALPHA &&
      blend.BlendOpAlpha == D3D12_BLEND_OP_ADD &&
      blend.RenderTargetWriteMask == D3D12_COLOR_WRITE_ENABLE_ALL;
}
}
