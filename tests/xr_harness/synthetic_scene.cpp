#include "synthetic_scene.h"

#include "core/xr_math.h"

#include <d3dcompiler.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <string>

namespace darktidevr::harness {
namespace {

using Microsoft::WRL::ComPtr;

constexpr auto kShader = R"hlsl(
cbuffer SceneConstants : register(b0) {
  column_major float4x4 viewProjection;
  float4 timeEye;
};

struct VSInput {
  float3 position : POSITION;
  float3 normal : NORMAL;
  float4 colorMaterial : COLOR;
};

struct PSInput {
  float4 position : SV_POSITION;
  float3 world : TEXCOORD0;
  float3 normal : NORMAL;
  float4 colorMaterial : COLOR;
};

PSInput vs_main(VSInput input) {
  PSInput output;
  float3 world = input.position;
  float material = input.colorMaterial.a;
  if (material > 3.5 && material < 4.5) {
    float angle = timeEye.x * 6.2831853;
    float2 center = float2(-1.8, 0.45);
    float2 local = world.xy - center;
    world.xy = center + float2(local.x * cos(angle) - local.y * sin(angle),
                               local.x * sin(angle) + local.y * cos(angle));
  } else if (material > 4.5 && material < 5.5) {
    world.x += sin(timeEye.x * 6.2831853) * 3.2;
  }
  output.position = mul(viewProjection, float4(world, 1.0));
  output.world = world;
  output.normal = input.normal;
  output.colorMaterial = input.colorMaterial;
  return output;
}

float4 ps_main(PSInput input) : SV_TARGET {
  float3 normal = normalize(input.normal);
  float light = 0.20 + 0.80 * saturate(dot(normal, normalize(float3(-0.4, 0.8, 0.3))));
  float3 color = input.colorMaterial.rgb;
  float material = input.colorMaterial.a;
  if (material > 0.5 && material < 1.5) {
    float checker = fmod(floor(input.world.x * 2.0) + floor(-input.world.z * 2.0), 2.0);
    color = lerp(float3(0.035, 0.04, 0.05), float3(0.42, 0.46, 0.52), checker);
  } else if (material > 1.5 && material < 2.5) {
    float specular = pow(saturate(dot(reflect(normalize(float3(0.3, -0.5, -1.0)), normal),
                                      normalize(float3(0.0, 0.0, 1.0)))), 48.0);
    color = color * light + specular.xxx;
    return float4(color, 1.0);
  } else if (material > 2.5 && material < 3.5) {
    float cutout = frac((input.world.x + input.world.y * 0.71 - input.world.z * 0.23) * 18.0);
    clip(cutout - 0.48);
  } else if (material > 5.5) {
    color *= step(0.5, frac(timeEye.x * 12.0));
  }
  float pulse = 0.94 + 0.06 * sin(timeEye.x * 6.2831853 + timeEye.y);
  return float4(color * light * pulse, 1.0);
}
)hlsl";

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(static_cast<std::uint32_t>(result)) +
                             ")");
  }
}

ComPtr<ID3DBlob> compile_shader(const char* entry, const char* target) {
  ComPtr<ID3DBlob> shader;
  ComPtr<ID3DBlob> errors;
  const auto result = D3DCompile(kShader, std::strlen(kShader), "synthetic_scene",
                                 nullptr, nullptr, entry, target,
                                 D3DCOMPILE_ENABLE_STRICTNESS, 0, &shader,
                                 &errors);
  if (FAILED(result)) {
    const auto detail = errors
                            ? std::string(static_cast<const char*>(errors->GetBufferPointer()),
                                          errors->GetBufferSize())
                            : std::string("no compiler diagnostics");
    throw std::runtime_error("D3DCompile failed: " + detail);
  }
  return shader;
}

D3D12_HEAP_PROPERTIES heap_properties(D3D12_HEAP_TYPE type) {
  D3D12_HEAP_PROPERTIES properties{};
  properties.Type = type;
  properties.CPUPageProperty = D3D12_CPU_PAGE_PROPERTY_UNKNOWN;
  properties.MemoryPoolPreference = D3D12_MEMORY_POOL_UNKNOWN;
  properties.CreationNodeMask = 1;
  properties.VisibleNodeMask = 1;
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

void add_triangle(std::vector<SyntheticScene::Vertex>& vertices,
                  std::array<float, 3> a, std::array<float, 3> b,
                  std::array<float, 3> c, std::array<float, 3> normal,
                  std::array<float, 4> color) {
  for (const auto& point : {a, b, c}) {
    vertices.push_back({{point[0], point[1], point[2]},
                        {normal[0], normal[1], normal[2]},
                        {color[0], color[1], color[2], color[3]}});
  }
}

void add_quad(std::vector<SyntheticScene::Vertex>& vertices,
              std::array<float, 3> a, std::array<float, 3> b,
              std::array<float, 3> c, std::array<float, 3> d,
              std::array<float, 3> normal, std::array<float, 4> color) {
  add_triangle(vertices, a, b, c, normal, color);
  add_triangle(vertices, a, c, d, normal, color);
}

void add_box(std::vector<SyntheticScene::Vertex>& vertices, float x, float y,
             float z, float sx, float sy, float sz,
             std::array<float, 4> color) {
  const float x0 = x - sx * 0.5F, x1 = x + sx * 0.5F;
  const float y0 = y - sy * 0.5F, y1 = y + sy * 0.5F;
  const float z0 = z - sz * 0.5F, z1 = z + sz * 0.5F;
  add_quad(vertices, {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1},
           {0, 0, 1}, color);
  add_quad(vertices, {x1, y0, z0}, {x0, y0, z0}, {x0, y1, z0}, {x1, y1, z0},
           {0, 0, -1}, color);
  add_quad(vertices, {x0, y0, z0}, {x0, y0, z1}, {x0, y1, z1}, {x0, y1, z0},
           {-1, 0, 0}, color);
  add_quad(vertices, {x1, y0, z1}, {x1, y0, z0}, {x1, y1, z0}, {x1, y1, z1},
           {1, 0, 0}, color);
  add_quad(vertices, {x0, y1, z1}, {x1, y1, z1}, {x1, y1, z0}, {x0, y1, z0},
           {0, 1, 0}, color);
  add_quad(vertices, {x0, y0, z0}, {x1, y0, z0}, {x1, y0, z1}, {x0, y0, z1},
           {0, -1, 0}, color);
}

void add_sphere(std::vector<SyntheticScene::Vertex>& vertices, float cx,
                float cy, float cz, float radius) {
  constexpr int rings = 12;
  constexpr int segments = 20;
  constexpr float pi = 3.14159265358979323846F;
  const auto point = [&](int ring, int segment) {
    const float phi = pi * static_cast<float>(ring) / rings;
    const float theta = 2.0F * pi * static_cast<float>(segment) / segments;
    const std::array<float, 3> normal{std::sin(phi) * std::cos(theta),
                                      std::cos(phi),
                                      std::sin(phi) * std::sin(theta)};
    return std::pair{std::array<float, 3>{cx + radius * normal[0],
                                          cy + radius * normal[1],
                                          cz + radius * normal[2]},
                     normal};
  };
  for (int ring = 0; ring < rings; ++ring) {
    for (int segment = 0; segment < segments; ++segment) {
      const auto [p00, n00] = point(ring, segment);
      const auto [p10, n10] = point(ring + 1, segment);
      const auto [p11, n11] = point(ring + 1, segment + 1);
      const auto [p01, n01] = point(ring, segment + 1);
      const std::array<float, 4> color{0.30F, 0.36F, 0.44F, 2.0F};
      vertices.push_back({{p00[0], p00[1], p00[2]}, {n00[0], n00[1], n00[2]},
                          {color[0], color[1], color[2], color[3]}});
      vertices.push_back({{p10[0], p10[1], p10[2]}, {n10[0], n10[1], n10[2]},
                          {color[0], color[1], color[2], color[3]}});
      vertices.push_back({{p11[0], p11[1], p11[2]}, {n11[0], n11[1], n11[2]},
                          {color[0], color[1], color[2], color[3]}});
      vertices.push_back({{p00[0], p00[1], p00[2]}, {n00[0], n00[1], n00[2]},
                          {color[0], color[1], color[2], color[3]}});
      vertices.push_back({{p11[0], p11[1], p11[2]}, {n11[0], n11[1], n11[2]},
                          {color[0], color[1], color[2], color[3]}});
      vertices.push_back({{p01[0], p01[1], p01[2]}, {n01[0], n01[1], n01[2]},
                          {color[0], color[1], color[2], color[3]}});
    }
  }
}

}  // namespace

SyntheticScene::SyntheticScene(
    ID3D12Device* device, DXGI_FORMAT color_format,
    const std::vector<std::vector<XrSwapchainImageD3D12KHR>>& images,
    const std::vector<XrViewConfigurationView>& view_configurations)
    : view_configurations_(view_configurations) {
  create_pipeline(device, color_format);
  create_mesh(device);
  create_targets(device, color_format, images, view_configurations);
}

void SyntheticScene::create_pipeline(ID3D12Device* device,
                                     DXGI_FORMAT color_format) {
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
        "D3D12SerializeRootSignature");
  check(device->CreateRootSignature(0, root_blob->GetBufferPointer(),
                                    root_blob->GetBufferSize(),
                                    IID_PPV_ARGS(&root_signature_)),
        "ID3D12Device::CreateRootSignature");

  const auto vertex_shader = compile_shader("vs_main", "vs_5_1");
  const auto pixel_shader = compile_shader("ps_main", "ps_5_1");
  const std::array<D3D12_INPUT_ELEMENT_DESC, 3> layout{{
      {"POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 0,
       D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
      {"NORMAL", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, 12,
       D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
      {"COLOR", 0, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, 24,
       D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0},
  }};

  D3D12_GRAPHICS_PIPELINE_STATE_DESC pipeline{};
  pipeline.pRootSignature = root_signature_.Get();
  pipeline.VS = {vertex_shader->GetBufferPointer(), vertex_shader->GetBufferSize()};
  pipeline.PS = {pixel_shader->GetBufferPointer(), pixel_shader->GetBufferSize()};
  pipeline.InputLayout = {layout.data(), static_cast<UINT>(layout.size())};
  pipeline.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
  pipeline.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID;
  pipeline.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
  pipeline.RasterizerState.DepthClipEnable = TRUE;
  pipeline.BlendState.RenderTarget[0].RenderTargetWriteMask =
      D3D12_COLOR_WRITE_ENABLE_ALL;
  pipeline.DepthStencilState.DepthEnable = TRUE;
  pipeline.DepthStencilState.DepthWriteMask = D3D12_DEPTH_WRITE_MASK_ALL;
  pipeline.DepthStencilState.DepthFunc = D3D12_COMPARISON_FUNC_LESS;
  pipeline.DSVFormat = DXGI_FORMAT_D32_FLOAT;
  pipeline.NumRenderTargets = 1;
  pipeline.RTVFormats[0] = color_format;
  pipeline.SampleDesc.Count = 1;
  pipeline.SampleMask = UINT_MAX;
  check(device->CreateGraphicsPipelineState(&pipeline, IID_PPV_ARGS(&pipeline_)),
        "ID3D12Device::CreateGraphicsPipelineState");
}

void SyntheticScene::create_mesh(ID3D12Device* device) {
  std::vector<Vertex> vertices;
  add_quad(vertices, {-8, -1, -1}, {8, -1, -1}, {8, -1, -24}, {-8, -1, -24},
           {0, 1, 0}, {1, 1, 1, 1});
  add_quad(vertices, {-8, -1, -24}, {8, -1, -24}, {8, 7, -24}, {-8, 7, -24},
           {0, 0, 1}, {0.08F, 0.09F, 0.12F, 0});
  const std::array<float, 5> depths{-2.5F, -4.0F, -6.5F, -10.0F, -16.0F};
  for (std::size_t index = 0; index < depths.size(); ++index) {
    const float hue = static_cast<float>(index) / depths.size();
    add_box(vertices, -2.4F + static_cast<float>(index) * 1.2F, 0.0F,
            depths[index], 0.22F, 2.0F + 0.35F * index, 0.22F,
            {0.15F + 0.65F * hue, 0.65F - 0.35F * hue, 0.85F, 0});
  }
  add_box(vertices, 0.0F, -0.15F, -1.8F, 0.18F, 1.7F, 0.18F,
          {0.95F, 0.18F, 0.08F, 0});
  add_sphere(vertices, 2.1F, -0.05F, -5.0F, 0.95F);
  add_quad(vertices, {2.8F, -0.985F, -3.5F}, {7.0F, -0.985F, -3.5F},
           {7.0F, -0.985F, -14.0F}, {2.8F, -0.985F, -14.0F}, {0, 1, 0},
           {0.12F, 0.18F, 0.24F, 2.0F});
  for (int index = 0; index < 7; ++index) {
    const float x = -3.2F + index * 0.42F;
    add_quad(vertices, {x, -1.0F, -7.5F}, {x + 0.5F, -1.0F, -7.5F},
             {x + 0.5F, 1.8F, -7.5F}, {x, 1.8F, -7.5F}, {0, 0, 1},
             {0.12F, 0.72F, 0.18F, 3.0F});
  }
  add_box(vertices, -1.8F, 0.45F, -4.5F, 2.2F, 0.10F, 0.10F,
          {0.95F, 0.72F, 0.08F, 4.0F});
  add_box(vertices, -1.8F, 0.45F, -4.5F, 0.10F, 2.2F, 0.10F,
          {0.95F, 0.72F, 0.08F, 4.0F});
  add_box(vertices, 0.0F, 1.35F, -6.0F, 0.16F, 0.16F, 0.16F,
          {0.95F, 0.15F, 0.55F, 5.0F});
  add_box(vertices, 3.4F, 1.4F, -8.0F, 0.65F, 0.65F, 0.65F,
          {1.0F, 1.0F, 1.0F, 6.0F});

  // Dense high-contrast world panel: a geometry-only proxy for small HUD text.
  add_quad(vertices, {-1.45F, 0.15F, -2.25F}, {1.45F, 0.15F, -2.25F},
           {1.45F, 1.65F, -2.25F}, {-1.45F, 1.65F, -2.25F}, {0, 0, 1},
           {0.015F, 0.02F, 0.028F, 0.0F});
  for (int row = 0; row < 14; ++row) {
    const float y = 0.24F + row * 0.095F;
    const float width = 0.35F + static_cast<float>((row * 7) % 17) * 0.105F;
    add_box(vertices, -1.25F + width * 0.5F, y, -2.20F, width, 0.022F, 0.018F,
            row % 3 == 0 ? std::array<float, 4>{0.95F, 0.74F, 0.18F, 0.0F}
                         : std::array<float, 4>{0.72F, 0.82F, 0.93F, 0.0F});
  }
  vertex_count_ = static_cast<std::uint32_t>(vertices.size());
  triangle_count_ = vertex_count_ / 3;
  const auto bytes = static_cast<UINT64>(vertices.size() * sizeof(Vertex));
  const auto upload = heap_properties(D3D12_HEAP_TYPE_UPLOAD);
  const auto description = buffer_description(bytes);
  check(device->CreateCommittedResource(
            &upload, D3D12_HEAP_FLAG_NONE, &description,
            D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
            IID_PPV_ARGS(&vertex_buffer_)),
        "ID3D12Device::CreateCommittedResource(vertices)");
  void* mapped{};
  check(vertex_buffer_->Map(0, nullptr, &mapped), "ID3D12Resource::Map(vertices)");
  std::memcpy(mapped, vertices.data(), static_cast<std::size_t>(bytes));
  vertex_buffer_->Unmap(0, nullptr);
  vertex_view_ = {vertex_buffer_->GetGPUVirtualAddress(), static_cast<UINT>(bytes),
                  sizeof(Vertex)};

  const auto constant_description = buffer_description(512);
  check(device->CreateCommittedResource(
            &upload, D3D12_HEAP_FLAG_NONE, &constant_description,
            D3D12_RESOURCE_STATE_GENERIC_READ, nullptr,
            IID_PPV_ARGS(&constant_buffer_)),
        "ID3D12Device::CreateCommittedResource(constants)");
  check(constant_buffer_->Map(0, nullptr,
                              reinterpret_cast<void**>(&constants_mapped_)),
        "ID3D12Resource::Map(constants)");
}

void SyntheticScene::create_targets(
    ID3D12Device* device, DXGI_FORMAT color_format,
    const std::vector<std::vector<XrSwapchainImageD3D12KHR>>& images,
    const std::vector<XrViewConfigurationView>& view_configurations) {
  std::size_t image_count{};
  for (const auto& eye : images) image_count += eye.size();
  D3D12_DESCRIPTOR_HEAP_DESC rtv_info{};
  rtv_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
  rtv_info.NumDescriptors = static_cast<UINT>(image_count);
  check(device->CreateDescriptorHeap(&rtv_info, IID_PPV_ARGS(&rtv_heap_)),
        "ID3D12Device::CreateDescriptorHeap(scene RTV)");
  rtv_increment_ = device->GetDescriptorHandleIncrementSize(
      D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
  auto rtv = rtv_heap_->GetCPUDescriptorHandleForHeapStart();
  std::uint32_t offset{};
  for (const auto& eye : images) {
    std::vector<std::uint32_t> offsets;
    for (const auto& image : eye) {
      D3D12_RENDER_TARGET_VIEW_DESC view{};
      view.Format = color_format;
      view.ViewDimension = D3D12_RTV_DIMENSION_TEXTURE2D;
      device->CreateRenderTargetView(image.texture, &view, rtv);
      offsets.push_back(offset++);
      rtv.ptr += rtv_increment_;
    }
    rtv_offsets_.push_back(std::move(offsets));
  }

  D3D12_DESCRIPTOR_HEAP_DESC dsv_info{};
  dsv_info.Type = D3D12_DESCRIPTOR_HEAP_TYPE_DSV;
  dsv_info.NumDescriptors = static_cast<UINT>(view_configurations.size());
  check(device->CreateDescriptorHeap(&dsv_info, IID_PPV_ARGS(&dsv_heap_)),
        "ID3D12Device::CreateDescriptorHeap(scene DSV)");
  dsv_increment_ = device->GetDescriptorHandleIncrementSize(
      D3D12_DESCRIPTOR_HEAP_TYPE_DSV);
  auto dsv = dsv_heap_->GetCPUDescriptorHandleForHeapStart();
  for (const auto& view : view_configurations) {
    D3D12_RESOURCE_DESC depth{};
    depth.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    depth.Width = view.recommendedImageRectWidth;
    depth.Height = view.recommendedImageRectHeight;
    depth.DepthOrArraySize = 1;
    depth.MipLevels = 1;
    depth.Format = DXGI_FORMAT_D32_FLOAT;
    depth.SampleDesc.Count = 1;
    depth.Flags = D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL;
    D3D12_CLEAR_VALUE clear{DXGI_FORMAT_D32_FLOAT};
    clear.DepthStencil.Depth = 1.0F;
    const auto heap = heap_properties(D3D12_HEAP_TYPE_DEFAULT);
    ComPtr<ID3D12Resource> resource;
    check(device->CreateCommittedResource(
              &heap, D3D12_HEAP_FLAG_NONE, &depth,
              D3D12_RESOURCE_STATE_DEPTH_WRITE, &clear,
              IID_PPV_ARGS(&resource)),
          "ID3D12Device::CreateCommittedResource(depth)");
    device->CreateDepthStencilView(resource.Get(), nullptr, dsv);
    depth_buffers_.push_back(std::move(resource));
    dsv.ptr += dsv_increment_;
  }
}

void SyntheticScene::record(ID3D12GraphicsCommandList* command_list,
                            std::size_t eye, std::uint32_t image_index,
                            const XrView& view, std::uint32_t frame_number) {
  using namespace darktidevr::math;
  const Pose eye_pose{{view.pose.orientation.x, view.pose.orientation.y,
                       view.pose.orientation.z, view.pose.orientation.w},
                      {view.pose.position.x, view.pose.position.y,
                       view.pose.position.z}};
  const Fov fov{view.fov.angleLeft, view.fov.angleRight, view.fov.angleUp,
                view.fov.angleDown};
  const auto view_projection = multiply(projection_d3d(fov, 0.05F, 100.0F),
                                        pose_matrix(inverse(eye_pose)));
  Constants constants{};
  std::copy(view_projection.m.begin(), view_projection.m.end(),
            constants.view_projection);
  constants.time_eye[0] = static_cast<float>(frame_number % 120) / 120.0F;
  constants.time_eye[1] = static_cast<float>(eye);
  std::memcpy(constants_mapped_ + eye * 256, &constants, sizeof(constants));

  const auto rtv_start = rtv_heap_->GetCPUDescriptorHandleForHeapStart();
  const D3D12_CPU_DESCRIPTOR_HANDLE rtv{
      rtv_start.ptr + static_cast<SIZE_T>(rtv_offsets_[eye][image_index]) *
                          rtv_increment_};
  const auto dsv_start = dsv_heap_->GetCPUDescriptorHandleForHeapStart();
  const D3D12_CPU_DESCRIPTOR_HANDLE dsv{
      dsv_start.ptr + static_cast<SIZE_T>(eye) * dsv_increment_};
  const auto& config = view_configurations_[eye];
  const D3D12_VIEWPORT viewport{0.0F, 0.0F,
                                static_cast<float>(config.recommendedImageRectWidth),
                                static_cast<float>(config.recommendedImageRectHeight),
                                0.0F, 1.0F};
  const D3D12_RECT scissor{0, 0,
                           static_cast<LONG>(config.recommendedImageRectWidth),
                           static_cast<LONG>(config.recommendedImageRectHeight)};
  const std::array<float, 4> clear{0.008F, 0.012F, 0.022F, 1.0F};
  command_list->SetPipelineState(pipeline_.Get());
  command_list->SetGraphicsRootSignature(root_signature_.Get());
  command_list->SetGraphicsRootConstantBufferView(
      0, constant_buffer_->GetGPUVirtualAddress() + eye * 256);
  command_list->RSSetViewports(1, &viewport);
  command_list->RSSetScissorRects(1, &scissor);
  command_list->OMSetRenderTargets(1, &rtv, FALSE, &dsv);
  command_list->ClearRenderTargetView(rtv, clear.data(), 0, nullptr);
  command_list->ClearDepthStencilView(dsv, D3D12_CLEAR_FLAG_DEPTH, 1.0F, 0, 0,
                                      nullptr);
  command_list->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  command_list->IASetVertexBuffers(0, 1, &vertex_view_);
  command_list->DrawInstanced(vertex_count_, 1, 0, 0);
}

}  // namespace darktidevr::harness
