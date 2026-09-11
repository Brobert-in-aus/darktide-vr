#include "tracked_cuff_renderer.h"

#include "core/xr_math.h"
#include "tracked_cuff_mesh.h"

#include <d3dcompiler.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <stdexcept>
#include <string>

using Microsoft::WRL::ComPtr;

namespace darktidevr::harness {
namespace {

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(
                                 static_cast<std::uint32_t>(result)) +
                             ")");
  }
}

D3D12_HEAP_PROPERTIES upload_heap() {
  D3D12_HEAP_PROPERTIES properties{};
  properties.Type = D3D12_HEAP_TYPE_UPLOAD;
  return properties;
}

D3D12_RESOURCE_DESC buffer_description(UINT64 bytes) {
  D3D12_RESOURCE_DESC description{};
  description.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  description.Width = bytes;
  description.Height = 1;
  description.DepthOrArraySize = 1;
  description.MipLevels = 1;
  description.SampleDesc.Count = 1;
  description.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  return description;
}

ComPtr<ID3DBlob> compile_shader(const char* entry, const char* target) {
  static constexpr char source[] = R"(
cbuffer CuffConstants : register(b0) {
  column_major float4x4 view_projection;
  column_major float4x4 model;
  float4 cuff_color;
};
struct VSInput { float3 position : POSITION; float3 normal : NORMAL; };
struct VSOutput { float4 position : SV_Position; float3 normal : NORMAL; };
VSOutput vs_main(VSInput input) {
  VSOutput output;
  output.position = mul(view_projection,
                        mul(model, float4(input.position, 1.0)));
  output.normal = normalize(mul((float3x3)model, input.normal));
  return output;
}
float4 ps_main(VSOutput input) : SV_Target {
  float lighting = 0.48 + 0.52 * abs(dot(normalize(input.normal),
                                        normalize(float3(0.35, 0.75, -0.56))));
  return float4(cuff_color.rgb * lighting, cuff_color.a);
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
    throw std::runtime_error("Tracked cuff shader compilation failed: " +
                             message);
  }
  return shader;
}

}  // namespace

std::array<float, 4> tracked_cuff_clip_center(
    const XrPosef& view_pose, const XrFovf& fov,
    const core::ControllerHandState& hand) {
  using namespace darktidevr::math;
  const Pose eye_pose{{view_pose.orientation.x, view_pose.orientation.y,
                       view_pose.orientation.z, view_pose.orientation.w},
                      {view_pose.position.x, view_pose.position.y,
                       view_pose.position.z}};
  const Fov eye_fov{fov.angleLeft, fov.angleRight, fov.angleUp,
                    fov.angleDown};
  const auto view_projection =
      multiply(projection_d3d(eye_fov, 0.025F, 100.0F),
               pose_matrix(inverse(eye_pose)));
  const Pose grip{hand.grip_pose.orientation, hand.grip_pose.position};
  const auto centre = transform_point(grip, {0.0F, 0.050F, 0.0F});
  return transform(view_projection, {centre.x, centre.y, centre.z, 1.0F});
}

TrackedCuffRenderer::TrackedCuffRenderer(
    ID3D12Device* device, DXGI_FORMAT color_format,
    const std::vector<std::vector<XrSwapchainImageD3D12KHR>>& images,
    const std::vector<XrViewConfigurationView>& view_configurations)
    : view_configurations_(view_configurations) {
  D3D12_ROOT_PARAMETER parameter{};
  parameter.ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
  parameter.Descriptor.ShaderRegister = 0;
  parameter.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
  D3D12_ROOT_SIGNATURE_DESC root_info{};
  root_info.NumParameters = 1;
  root_info.pParameters = &parameter;
  root_info.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;
  ComPtr<ID3DBlob> root_blob;
  ComPtr<ID3DBlob> root_errors;
  check(D3D12SerializeRootSignature(&root_info, D3D_ROOT_SIGNATURE_VERSION_1,
                                    &root_blob, &root_errors),
        "D3D12SerializeRootSignature(tracked cuff)");
  check(device->CreateRootSignature(0, root_blob->GetBufferPointer(),
                                    root_blob->GetBufferSize(),
                                    IID_PPV_ARGS(&root_signature_)),
        "CreateRootSignature(tracked cuff)");

  const auto vertex_shader = compile_shader("vs_main", "vs_5_1");
  const auto pixel_shader = compile_shader("ps_main", "ps_5_1");
  const std::array<D3D12_INPUT_ELEMENT_DESC, 2> layout{{
      {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0,
       D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
      {"NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12,
       D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
  }};
  D3D12_GRAPHICS_PIPELINE_STATE_DESC pipeline{};
  pipeline.pRootSignature = root_signature_.Get();
  pipeline.VS = {vertex_shader->GetBufferPointer(),
                 vertex_shader->GetBufferSize()};
  pipeline.PS = {pixel_shader->GetBufferPointer(),
                 pixel_shader->GetBufferSize()};
  pipeline.InputLayout = {layout.data(), static_cast<UINT>(layout.size())};
  pipeline.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
  pipeline.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
  pipeline.RasterizerState.CullMode = D3D12_CULL_MODE_BACK;
  // tracked_cuff_mesh_tests enforces counter-clockwise outward winding, so
  // counter-clockwise triangles are the front faces.
  pipeline.RasterizerState.FrontCounterClockwise = TRUE;
  pipeline.RasterizerState.DepthClipEnable = TRUE;
  pipeline.BlendState.RenderTarget[0].RenderTargetWriteMask =
      D3D12_COLOR_WRITE_ENABLE_ALL;
  pipeline.DepthStencilState.DepthEnable = FALSE;
  pipeline.NumRenderTargets = 1;
  pipeline.RTVFormats[0] = color_format;
  pipeline.SampleDesc.Count = 1;
  pipeline.SampleMask = UINT_MAX;
  check(device->CreateGraphicsPipelineState(&pipeline,
                                            IID_PPV_ARGS(&pipeline_)),
        "CreateGraphicsPipelineState(tracked cuff)");

  const auto cuff = make_tracked_cuff_mesh();
  std::vector<Vertex> vertices;
  vertices.reserve(cuff.size());
  for (const auto& vertex : cuff) {
    vertices.push_back({{vertex.position.x, vertex.position.y,
                         vertex.position.z},
                        {vertex.normal.x, vertex.normal.y, vertex.normal.z}});
  }
  vertex_count_ = static_cast<std::uint32_t>(vertices.size());
  const auto vertex_bytes =
      static_cast<UINT64>(vertices.size() * sizeof(Vertex));
  const auto upload = upload_heap();
  const auto vertex_description = buffer_description(vertex_bytes);
  check(device->CreateCommittedResource(
            &upload, D3D12_HEAP_FLAG_NONE, &vertex_description,
            D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
            IID_PPV_ARGS(&vertex_buffer_)),
        "CreateCommittedResource(tracked cuff vertices)");
  void* mapped{};
  check(vertex_buffer_->Map(0, nullptr, &mapped),
        "Map(tracked cuff vertices)");
  std::memcpy(mapped, vertices.data(), static_cast<std::size_t>(vertex_bytes));
  vertex_buffer_->Unmap(0, nullptr);
  vertex_view_ = {vertex_buffer_->GetGPUVirtualAddress(),
                  static_cast<UINT>(vertex_bytes), sizeof(Vertex)};

  constexpr UINT64 constant_bytes = 4U * 256U;
  const auto constant_description = buffer_description(constant_bytes);
  check(device->CreateCommittedResource(
            &upload, D3D12_HEAP_FLAG_NONE, &constant_description,
            D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
            IID_PPV_ARGS(&constant_buffer_)),
        "CreateCommittedResource(tracked cuff constants)");
  check(constant_buffer_->Map(
            0, nullptr, reinterpret_cast<void**>(&constants_mapped_)),
        "Map(tracked cuff constants)");

  std::size_t image_count{};
  for (const auto& eye_images : images) {
    image_count += eye_images.size();
  }
  D3D12_DESCRIPTOR_HEAP_DESC rtv_info{};
  rtv_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
  rtv_info.NumDescriptors = static_cast<UINT>(image_count);
  check(device->CreateDescriptorHeap(&rtv_info, IID_PPV_ARGS(&rtv_heap_)),
        "CreateDescriptorHeap(tracked cuff RTV)");
  rtv_increment_ = device->GetDescriptorHandleIncrementSize(
      D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
  auto rtv = rtv_heap_->GetCPUDescriptorHandleForHeapStart();
  std::uint32_t offset{};
  for (const auto& eye_images : images) {
    std::vector<std::uint32_t> offsets;
    for (const auto& image : eye_images) {
      D3D12_RENDER_TARGET_VIEW_DESC view{};
      view.Format = color_format;
      view.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
      device->CreateRenderTargetView(image.texture, &view, rtv);
      offsets.push_back(offset++);
      rtv.ptr += rtv_increment_;
    }
    rtv_offsets_.push_back(std::move(offsets));
  }
}

TrackedCuffRenderer::~TrackedCuffRenderer() {
  if (constant_buffer_ && constants_mapped_) {
    constant_buffer_->Unmap(0, nullptr);
  }
}

std::uint32_t TrackedCuffRenderer::record(
    ID3D12GraphicsCommandList* command_list, std::size_t eye,
    std::uint32_t image_index, const XrPosef& view_pose, const XrFovf& fov,
    const std::array<core::ControllerHandState, 2>& hands) {
  using namespace darktidevr::math;
  const Pose eye_pose{{view_pose.orientation.x, view_pose.orientation.y,
                       view_pose.orientation.z, view_pose.orientation.w},
                      {view_pose.position.x, view_pose.position.y,
                       view_pose.position.z}};
  const Fov eye_fov{fov.angleLeft, fov.angleRight, fov.angleUp,
                    fov.angleDown};
  const auto view_projection =
      multiply(projection_d3d(eye_fov, 0.025F, 100.0F),
               pose_matrix(inverse(eye_pose)));
  const auto rtv_start = rtv_heap_->GetCPUDescriptorHandleForHeapStart();
  const D3D12_CPU_DESCRIPTOR_HANDLE rtv{
      rtv_start.ptr + static_cast<SIZE_T>(rtv_offsets_[eye][image_index]) *
                          rtv_increment_};
  const auto& view = view_configurations_[eye];
  const D3D12_VIEWPORT viewport{
      0.0F, 0.0F, static_cast<float>(view.recommendedImageRectWidth),
      static_cast<float>(view.recommendedImageRectHeight), 0.0F, 1.0F};
  const D3D12_RECT scissor{
      0, 0, static_cast<LONG>(view.recommendedImageRectWidth),
      static_cast<LONG>(view.recommendedImageRectHeight)};
  command_list->SetPipelineState(pipeline_.Get());
  command_list->SetGraphicsRootSignature(root_signature_.Get());
  command_list->RSSetViewports(1, &viewport);
  command_list->RSSetScissorRects(1, &scissor);
  command_list->OMSetRenderTargets(1, &rtv, FALSE, nullptr);
  command_list->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  command_list->IASetVertexBuffers(0, 1, &vertex_view_);

  std::uint32_t drawn{};
  constexpr auto valid_flags = core::controller_orientation_valid |
                               core::controller_position_valid;
  for (std::size_t hand_index = 0; hand_index < hands.size(); ++hand_index) {
    const auto& hand = hands[hand_index];
    if ((hand.grip_tracking_flags & valid_flags) != valid_flags) {
      continue;
    }
    const Pose grip{hand.grip_pose.orientation, hand.grip_pose.position};
    const Pose wrist_offset{{}, {0.0F, 0.050F, 0.0F}};
    const auto model = pose_matrix(compose(grip, wrist_offset));
    Constants constants{};
    std::copy(view_projection.m.begin(), view_projection.m.end(),
              constants.view_projection);
    std::copy(model.m.begin(), model.m.end(), constants.model);
    const std::array<float, 4> color =
        hand_index == 0U ? std::array<float, 4>{0.16F, 0.13F, 0.10F, 1.0F}
                         : std::array<float, 4>{0.13F, 0.11F, 0.09F, 1.0F};
    std::copy(color.begin(), color.end(), constants.color);
    const auto constant_index = eye * hands.size() + hand_index;
    std::memcpy(constants_mapped_ + constant_index * 256U, &constants,
                sizeof(constants));
    command_list->SetGraphicsRootConstantBufferView(
        0, constant_buffer_->GetGPUVirtualAddress() + constant_index * 256U);
    command_list->DrawInstanced(vertex_count_, 1, 0, 0);
    ++drawn;
  }
  return drawn;
}

}  // namespace darktidevr::harness
