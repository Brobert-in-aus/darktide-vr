#include "panel_renderer.h"

#include "core/xr_math.h"

#include <d3dcompiler.h>

#include <algorithm>
#include <cstring>
#include <stdexcept>
#include <string>

using Microsoft::WRL::ComPtr;

namespace darktidevr::harness {
namespace {

constexpr UINT64 constant_slot_bytes = 256U;
constexpr float near_metres = 0.025F;
// The boards sit two metres out and the cuffs at arm's length, but the
// gameplay reticle is placed where the aim ray hits, which the mod clamps at
// 200 m (darktidevr.lua: publish_gameplay_aim_state). At a 100 m far plane
// the rasterizer clipped the whole quad away down any long hall, and with the
// quad layer standing down there was nothing to fall back to: the reticle
// simply vanished (review, 18 September). Nothing here reads or writes depth,
// so the range costs nothing.
constexpr float far_metres = 1000.0F;

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(
                                 static_cast<std::uint32_t>(result)) +
                             ")");
  }
}

ComPtr<ID3DBlob> compile_shader(const char* entry, const char* target) {
  // The quad's corners come from the vertex id (a four-vertex strip). The
  // texture is premultiplied, as the quad layers it replaces were blended.
  // Four rotated-grid taps soften minification of a board larger than its
  // footprint in the eye image; the coverage term fades the outermost pixel
  // so the board's edge does not stair-step.
  static constexpr char source[] = R"(
cbuffer PanelConstants : register(b0) {
  column_major float4x4 view_projection;
  column_major float4x4 model;
  float4 uv_rect;
  float2 quad_size;
  float2 half_texel;
};
Texture2D source_texture : register(t0);
SamplerState linear_clamp : register(s0);
struct VSOutput {
  float4 position : SV_Position;
  float2 uv : TEXCOORD0;
  float2 corner : TEXCOORD1;
};
VSOutput vs_main(uint id : SV_VertexID) {
  float2 corner = float2(id & 1, (id >> 1) & 1);
  float3 local = float3((corner.x - 0.5) * quad_size.x,
                        (0.5 - corner.y) * quad_size.y, 0.0);
  VSOutput output;
  output.position = mul(view_projection, mul(model, float4(local, 1.0)));
  output.uv = lerp(uv_rect.xy, uv_rect.zw, corner);
  output.corner = corner;
  return output;
}
float4 tap(float2 uv) {
  return source_texture.SampleLevel(
      linear_clamp,
      clamp(uv, uv_rect.xy + half_texel, uv_rect.zw - half_texel), 0);
}
float4 ps_main(VSOutput input) : SV_Target {
  float2 dx = ddx(input.uv);
  float2 dy = ddy(input.uv);
  float4 color = 0.25 * (tap(input.uv + 0.125 * dx + 0.375 * dy) +
                         tap(input.uv - 0.375 * dx + 0.125 * dy) +
                         tap(input.uv + 0.375 * dx - 0.125 * dy) +
                         tap(input.uv - 0.125 * dx - 0.375 * dy));
  float2 width = max(fwidth(input.corner), 1.0e-6);
  float2 distance = min(input.corner, 1.0 - input.corner) / width;
  float coverage = saturate(min(distance.x, distance.y) + 0.5);
  return color * coverage;
}
)";
  ComPtr<ID3DBlob> shader;
  ComPtr<ID3DBlob> errors;
  const auto result = D3DCompile(source, sizeof(source) - 1U, nullptr, nullptr,
                                 nullptr, entry, target,
                                 D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
                                 &shader, &errors);
  if (FAILED(result)) {
    const auto message = errors
                             ? std::string(
                                   static_cast<const char*>(
                                       errors->GetBufferPointer()),
                                   errors->GetBufferSize())
                             : std::string("unknown compiler error");
    throw std::runtime_error("Panel shader compilation failed: " + message);
  }
  return shader;
}

math::Pose to_pose(const XrPosef& pose) {
  return {{pose.orientation.x, pose.orientation.y, pose.orientation.z,
           pose.orientation.w},
          {pose.position.x, pose.position.y, pose.position.z}};
}

math::Matrix4 view_projection_matrix(const XrPosef& eye_pose,
                                     const XrFovf& fov) {
  const math::Fov eye_fov{fov.angleLeft, fov.angleRight, fov.angleUp,
                          fov.angleDown};
  return math::multiply(math::projection_d3d(eye_fov, near_metres, far_metres),
                        math::pose_matrix(math::inverse(to_pose(eye_pose))));
}

void transition(ID3D12GraphicsCommandList* command_list,
                ID3D12Resource* resource, D3D12_RESOURCE_STATES before,
                D3D12_RESOURCE_STATES after) {
  D3D12_RESOURCE_BARRIER barrier{};
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barrier.Transition.pResource = resource;
  barrier.Transition.StateBefore = before;
  barrier.Transition.StateAfter = after;
  barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  command_list->ResourceBarrier(1, &barrier);
}

}  // namespace

std::array<float, 4> panel_point_clip(const XrPosef& eye_pose,
                                      const XrFovf& fov,
                                      const XrPosef& quad_pose,
                                      XrExtent2Df size, float u, float v) {
  const auto point = math::transform_point(
      to_pose(quad_pose),
      {(u - 0.5F) * size.width, (0.5F - v) * size.height, 0.0F});
  return math::transform(view_projection_matrix(eye_pose, fov),
                         {point.x, point.y, point.z, 1.0F});
}

bool panel_quad_centre_visible(const XrPosef& eye_pose, const XrFovf& fov,
                               const XrPosef& quad_pose, XrExtent2Df size) {
  const auto clip =
      panel_point_clip(eye_pose, fov, quad_pose, size, 0.5F, 0.5F);
  // D3D clip space: 0 <= z <= w, and w is the view depth.
  return clip[3] > 0.0F && clip[2] >= 0.0F && clip[2] <= clip[3];
}

PanelRenderer::PanelRenderer(ID3D12Device* device, DXGI_FORMAT view_format,
                             D3D12_RESOURCE_DESC board_description,
                             D3D12_RESOURCE_DESC swatch_description) {
  D3D12_DESCRIPTOR_RANGE range{};
  range.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV;
  range.NumDescriptors = 1;
  range.BaseShaderRegister = 0;
  std::array<D3D12_ROOT_PARAMETER, 2> parameters{};
  parameters[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
  parameters[0].Descriptor.ShaderRegister = 0;
  parameters[0].ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
  parameters[1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
  parameters[1].DescriptorTable.NumDescriptorRanges = 1;
  parameters[1].DescriptorTable.pDescriptorRanges = &range;
  parameters[1].ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
  D3D12_STATIC_SAMPLER_DESC sampler{};
  sampler.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
  sampler.AddressU = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
  sampler.AddressV = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
  sampler.AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
  sampler.MaxLOD = D3D12_FLOAT32_MAX;
  sampler.ShaderRegister = 0;
  sampler.ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
  D3D12_ROOT_SIGNATURE_DESC root_info{};
  root_info.NumParameters = static_cast<UINT>(parameters.size());
  root_info.pParameters = parameters.data();
  root_info.NumStaticSamplers = 1;
  root_info.pStaticSamplers = &sampler;
  ComPtr<ID3DBlob> root_blob;
  ComPtr<ID3DBlob> root_errors;
  check(D3D12SerializeRootSignature(&root_info, D3D_ROOT_SIGNATURE_VERSION_1,
                                    &root_blob, &root_errors),
        "D3D12SerializeRootSignature(panel)");
  check(device->CreateRootSignature(0, root_blob->GetBufferPointer(),
                                    root_blob->GetBufferSize(),
                                    IID_PPV_ARGS(&root_signature_)),
        "CreateRootSignature(panel)");

  const auto vertex_shader = compile_shader("vs_main", "vs_5_1");
  const auto pixel_shader = compile_shader("ps_main", "ps_5_1");
  D3D12_GRAPHICS_PIPELINE_STATE_DESC pipeline{};
  pipeline.pRootSignature = root_signature_.Get();
  pipeline.VS = {vertex_shader->GetBufferPointer(),
                 vertex_shader->GetBufferSize()};
  pipeline.PS = {pixel_shader->GetBufferPointer(),
                 pixel_shader->GetBufferSize()};
  pipeline.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
  pipeline.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
  // A quad layer is visible from its front (+Z) only. The strip's first
  // triangle (top-left, top-right, bottom-left) is clockwise seen from the
  // front, D3D12's default front face.
  pipeline.RasterizerState.CullMode = D3D12_CULL_MODE_BACK;
  pipeline.RasterizerState.DepthClipEnable = TRUE;
  // Premultiplied source over the eye image: what a quad layer with
  // BLEND_TEXTURE_SOURCE_ALPHA and no UNPREMULTIPLIED bit asks for.
  auto& blend = pipeline.BlendState.RenderTarget[0];
  blend.BlendEnable = TRUE;
  blend.SrcBlend = D3D12_BLEND_ONE;
  blend.DestBlend = D3D12_BLEND_INV_SRC_ALPHA;
  blend.BlendOp = D3D12_BLEND_OP_ADD;
  blend.SrcBlendAlpha = D3D12_BLEND_ONE;
  blend.DestBlendAlpha = D3D12_BLEND_INV_SRC_ALPHA;
  blend.BlendOpAlpha = D3D12_BLEND_OP_ADD;
  blend.RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
  pipeline.DepthStencilState.DepthEnable = FALSE;
  pipeline.NumRenderTargets = 1;
  pipeline.RTVFormats[0] = view_format;
  pipeline.SampleDesc.Count = 1;
  pipeline.SampleMask = UINT_MAX;
  check(device->CreateGraphicsPipelineState(&pipeline,
                                            IID_PPV_ARGS(&pipeline_)),
        "CreateGraphicsPipelineState(panel)");

  D3D12_HEAP_PROPERTIES default_heap{};
  default_heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  const auto create_texture = [&](D3D12_RESOURCE_DESC description,
                                  ComPtr<ID3D12Resource>& texture,
                                  const char* operation) {
    description.Flags = D3D12_RESOURCE_FLAG_NONE;
    description.MipLevels = 1;
    description.DepthOrArraySize = 1;
    description.SampleDesc = {1, 0};
    description.Alignment = 0;
    check(device->CreateCommittedResource(
              &default_heap, D3D12_HEAP_FLAG_NONE, &description,
              D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&texture)),
          operation);
  };
  create_texture(board_description, board_,
                 "CreateCommittedResource(panel board)");
  create_texture(swatch_description, swatch_,
                 "CreateCommittedResource(panel swatch)");
  texture_extent_[0] = {static_cast<float>(board_description.Width),
                        static_cast<float>(board_description.Height)};
  texture_extent_[1] = {static_cast<float>(swatch_description.Width),
                        static_cast<float>(swatch_description.Height)};

  D3D12_DESCRIPTOR_HEAP_DESC srv_info{};
  srv_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
  srv_info.NumDescriptors = 2;
  srv_info.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
  check(device->CreateDescriptorHeap(&srv_info, IID_PPV_ARGS(&srv_heap_)),
        "CreateDescriptorHeap(panel SRV)");
  srv_increment_ = device->GetDescriptorHandleIncrementSize(
      D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
  auto srv = srv_heap_->GetCPUDescriptorHandleForHeapStart();
  D3D12_SHADER_RESOURCE_VIEW_DESC view{};
  view.Format = view_format;
  view.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
  view.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
  view.Texture2D.MipLevels = 1;
  device->CreateShaderResourceView(board_.Get(), &view, srv);
  srv.ptr += srv_increment_;
  device->CreateShaderResourceView(swatch_.Get(), &view, srv);

  D3D12_HEAP_PROPERTIES upload_heap{};
  upload_heap.Type = D3D12_HEAP_TYPE_UPLOAD;
  D3D12_RESOURCE_DESC constant_description{};
  constant_description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  constant_description.Width =
      constant_slot_bytes * 2U * maximum_quads_per_eye;
  constant_description.Height = 1;
  constant_description.DepthOrArraySize = 1;
  constant_description.MipLevels = 1;
  constant_description.SampleDesc.Count = 1;
  constant_description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  check(device->CreateCommittedResource(
            &upload_heap, D3D12_HEAP_FLAG_NONE, &constant_description,
            D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
            IID_PPV_ARGS(&constant_buffer_)),
        "CreateCommittedResource(panel constants)");
  check(constant_buffer_->Map(
            0, nullptr, reinterpret_cast<void**>(&constants_mapped_)),
        "Map(panel constants)");
}

PanelRenderer::~PanelRenderer() {
  if (constant_buffer_ && constants_mapped_) {
    constant_buffer_->Unmap(0, nullptr);
  }
}

void PanelRenderer::upload_swatch(
    ID3D12GraphicsCommandList* command_list, ID3D12Resource* upload,
    const D3D12_PLACED_SUBRESOURCE_FOOTPRINT& footprint) {
  if (swatch_ready_) {
    return;
  }
  D3D12_TEXTURE_COPY_LOCATION source{};
  source.pResource = upload;
  source.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
  source.PlacedFootprint = footprint;
  D3D12_TEXTURE_COPY_LOCATION destination{};
  destination.pResource = swatch_.Get();
  destination.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
  command_list->CopyTextureRegion(&destination, 0, 0, 0, &source, nullptr);
  transition(command_list, swatch_.Get(), D3D12_RESOURCE_STATE_COPY_DEST,
             D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
  swatch_ready_ = true;
}

void PanelRenderer::begin(ID3D12GraphicsCommandList* command_list) {
  transition(command_list, board_.Get(), D3D12_RESOURCE_STATE_COPY_DEST,
             D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE);
  ID3D12DescriptorHeap* heaps[]{srv_heap_.Get()};
  command_list->SetDescriptorHeaps(1, heaps);
  command_list->SetPipelineState(pipeline_.Get());
  command_list->SetGraphicsRootSignature(root_signature_.Get());
  command_list->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
}

std::uint32_t PanelRenderer::record(
    ID3D12GraphicsCommandList* command_list,
    D3D12_CPU_DESCRIPTOR_HANDLE render_target, const XrRect2Di& image_rect,
    std::size_t eye, const XrPosef& eye_pose, const XrFovf& fov,
    const PanelQuad* quads, std::size_t quad_count, bool clear_transparent) {
  const D3D12_VIEWPORT viewport{
      static_cast<float>(image_rect.offset.x),
      static_cast<float>(image_rect.offset.y),
      static_cast<float>(image_rect.extent.width),
      static_cast<float>(image_rect.extent.height), 0.0F, 1.0F};
  const D3D12_RECT scissor{
      image_rect.offset.x, image_rect.offset.y,
      image_rect.offset.x + image_rect.extent.width,
      image_rect.offset.y + image_rect.extent.height};
  command_list->RSSetViewports(1, &viewport);
  command_list->RSSetScissorRects(1, &scissor);
  command_list->OMSetRenderTargets(1, &render_target, FALSE, nullptr);
  if (clear_transparent) {
    constexpr std::array<float, 4> transparent{0.0F, 0.0F, 0.0F, 0.0F};
    command_list->ClearRenderTargetView(render_target, transparent.data(), 1,
                                        &scissor);
  }
  const auto view_projection = view_projection_matrix(eye_pose, fov);
  const auto srv_start = srv_heap_->GetGPUDescriptorHandleForHeapStart();
  std::uint32_t drawn{};
  for (std::size_t index = 0;
       index < quad_count && index < maximum_quads_per_eye; ++index) {
    const auto& quad = quads[index];
    const auto source = static_cast<std::size_t>(quad.source);
    if (quad.source == PanelQuad::Source::swatch && !swatch_ready_) {
      continue;
    }
    const auto& extent = texture_extent_[source];
    Constants constants{};
    const auto model = math::pose_matrix(to_pose(quad.pose));
    std::copy(view_projection.m.begin(), view_projection.m.end(),
              constants.view_projection);
    std::copy(model.m.begin(), model.m.end(), constants.model);
    constants.uv_rect[0] =
        static_cast<float>(quad.texels.offset.x) / extent[0];
    constants.uv_rect[1] =
        static_cast<float>(quad.texels.offset.y) / extent[1];
    constants.uv_rect[2] = static_cast<float>(quad.texels.offset.x +
                                              quad.texels.extent.width) /
                           extent[0];
    constants.uv_rect[3] = static_cast<float>(quad.texels.offset.y +
                                              quad.texels.extent.height) /
                           extent[1];
    constants.size[0] = quad.size.width;
    constants.size[1] = quad.size.height;
    constants.half_texel[0] = 0.5F / extent[0];
    constants.half_texel[1] = 0.5F / extent[1];
    const auto slot = (eye % 2U) * maximum_quads_per_eye + index;
    std::memcpy(constants_mapped_ + slot * constant_slot_bytes, &constants,
                sizeof(constants));
    command_list->SetGraphicsRootConstantBufferView(
        0, constant_buffer_->GetGPUVirtualAddress() +
               slot * constant_slot_bytes);
    command_list->SetGraphicsRootDescriptorTable(
        1, {srv_start.ptr + static_cast<UINT64>(source) * srv_increment_});
    command_list->DrawInstanced(4, 1, 0, 0);
    ++drawn;
  }
  return drawn;
}

void PanelRenderer::end(ID3D12GraphicsCommandList* command_list) {
  transition(command_list, board_.Get(),
             D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE,
             D3D12_RESOURCE_STATE_COPY_DEST);
}

}  // namespace darktidevr::harness
