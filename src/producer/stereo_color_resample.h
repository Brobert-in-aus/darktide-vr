#pragma once
#include <d3d12.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <array>
#include <cstring>

namespace darktidevr::producer {
// One-shot owner: keep this and its input references alive until the submitting
// queue fence completes. All outputs are linear RGBA8; full-image normalized
// sampling preserves the camera projection instead of cropping half the eye.
class StereoColorResample {
 public:
  HRESULT record(ID3D12Device* device, ID3D12GraphicsCommandList* commands,
                 ID3D12Resource* left, ID3D12Resource* right,
                 UINT width, UINT height) {
    if (recorded_ || !device || !commands || !left || !right ||
        !width || width > 8192 || !height || height > 16384) return E_INVALIDARG;
    inputs_ = {left, right};
    for (const auto& input : inputs_) {
      const auto d = input->GetDesc();
      if (d.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
          (d.Format != DXGI_FORMAT_R8G8B8A8_UNORM &&
           d.Format != DXGI_FORMAT_R8G8B8A8_TYPELESS) ||
          d.SampleDesc.Count != 1 || d.DepthOrArraySize != 1 || d.MipLevels != 1 ||
          (d.Flags & D3D12_RESOURCE_FLAG_DENY_SHADER_RESOURCE)) return E_INVALIDARG;
    }
    static constexpr char shader[] = R"(
Texture2D<float4> leftEye : register(t0);
Texture2D<float4> rightEye : register(t1);
SamplerState linearClamp : register(s0);
RWTexture2D<float4> leftOut : register(u0);
RWTexture2D<float4> rightOut : register(u1);
RWTexture2D<float4> packedOut : register(u2);
[numthreads(8,8,1)] void main(uint3 id : SV_DispatchThreadID) {
    uint w,h; leftOut.GetDimensions(w,h);
    if (id.x >= w || id.y >= h) return;
    float2 uv = (float2(id.xy)+0.5)/float2(w,h);
    float4 l=leftEye.SampleLevel(linearClamp,uv,0);
    float4 r=rightEye.SampleLevel(linearClamp,uv,0);
    leftOut[id.xy]=l; rightOut[id.xy]=r;
    packedOut[id.xy]=l; packedOut[id.xy+uint2(w,0)]=r;
})";
    Microsoft::WRL::ComPtr<ID3DBlob> code, errors, serialized;
    auto hr = D3DCompile(shader, std::strlen(shader), nullptr, nullptr, nullptr,
        "main", "cs_5_1", D3DCOMPILE_ENABLE_STRICTNESS, 0, &code, &errors);
    if (FAILED(hr)) return hr;
    std::array<D3D12_DESCRIPTOR_RANGE, 2> ranges{{
        {D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 2, 0, 0, 0},
        {D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 3, 0, 0, 2}}};
    D3D12_ROOT_PARAMETER root{};
    root.ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
    root.DescriptorTable = {2, ranges.data()};
    D3D12_STATIC_SAMPLER_DESC sampler{};
    sampler.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
    sampler.AddressU = sampler.AddressV = sampler.AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
    sampler.MaxLOD = D3D12_FLOAT32_MAX;
    sampler.ComparisonFunc = D3D12_COMPARISON_FUNC_ALWAYS;
    sampler.ShaderVisibility = D3D12_SHADER_VISIBILITY_ALL;
    D3D12_ROOT_SIGNATURE_DESC signature{1, &root, 1, &sampler, D3D12_ROOT_SIGNATURE_FLAG_NONE};
    hr = D3D12SerializeRootSignature(&signature, D3D_ROOT_SIGNATURE_VERSION_1,
                                    &serialized, &errors);
    if (FAILED(hr)) return hr;
    hr = device->CreateRootSignature(0, serialized->GetBufferPointer(),
        serialized->GetBufferSize(), IID_PPV_ARGS(&root_));
    if (FAILED(hr)) return hr;
    D3D12_COMPUTE_PIPELINE_STATE_DESC pipeline{};
    pipeline.pRootSignature = root_.Get();
    pipeline.CS = {code->GetBufferPointer(), code->GetBufferSize()};
    hr = device->CreateComputePipelineState(&pipeline, IID_PPV_ARGS(&pipeline_));
    if (FAILED(hr)) return hr;
    D3D12_DESCRIPTOR_HEAP_DESC heap{D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 5,
        D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE, 0};
    hr = device->CreateDescriptorHeap(&heap, IID_PPV_ARGS(&descriptors_));
    if (FAILED(hr)) return hr;
    auto handle = descriptors_->GetCPUDescriptorHandleForHeapStart();
    const auto step = device->GetDescriptorHandleIncrementSize(heap.Type);
    D3D12_SHADER_RESOURCE_VIEW_DESC srv{};
    srv.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    srv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
    srv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    srv.Texture2D.MipLevels = 1;
    for (const auto& input : inputs_) {
      device->CreateShaderResourceView(input.Get(), &srv, handle); handle.ptr += step;
    }
    D3D12_HEAP_PROPERTIES properties{}; properties.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC texture{};
    texture.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    texture.Height = height; texture.DepthOrArraySize = 1; texture.MipLevels = 1;
    texture.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    texture.SampleDesc.Count = 1; texture.Flags = D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
    D3D12_UNORDERED_ACCESS_VIEW_DESC uav{};
    uav.Format = texture.Format; uav.ViewDimension = D3D12_UAV_DIMENSION_TEXTURE2D;
    for (UINT i = 0; i < 3; ++i) {
      texture.Width = i == 2 ? width * 2 : width;
      hr = device->CreateCommittedResource(&properties, D3D12_HEAP_FLAG_NONE,
          &texture, D3D12_RESOURCE_STATE_UNORDERED_ACCESS, nullptr, IID_PPV_ARGS(&outputs_[i]));
      if (FAILED(hr)) return hr;
      device->CreateUnorderedAccessView(outputs_[i].Get(), nullptr, &uav, handle);
      handle.ptr += step;
    }
    std::array<D3D12_RESOURCE_BARRIER, 2> sources{};
    for (UINT i = 0; i < 2; ++i) {
      sources[i].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      sources[i].Transition = {inputs_[i].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
          D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE};
    }
    commands->ResourceBarrier(2, sources.data());
    ID3D12DescriptorHeap* heaps[]{descriptors_.Get()};
    commands->SetDescriptorHeaps(1, heaps);
    commands->SetComputeRootSignature(root_.Get());
    commands->SetPipelineState(pipeline_.Get());
    commands->SetComputeRootDescriptorTable(0, descriptors_->GetGPUDescriptorHandleForHeapStart());
    commands->Dispatch((width+7)/8, (height+7)/8, 1);
    for (auto& source : sources)
      std::swap(source.Transition.StateBefore, source.Transition.StateAfter);
    commands->ResourceBarrier(2, sources.data());
    std::array<D3D12_RESOURCE_BARRIER, 3> destinations{};
    for (UINT i = 0; i < 3; ++i) {
      destinations[i].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      destinations[i].Transition = {outputs_[i].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
          D3D12_RESOURCE_STATE_UNORDERED_ACCESS,
          i == 2 ? D3D12_RESOURCE_STATE_PRESENT : D3D12_RESOURCE_STATE_COPY_SOURCE};
    }
    commands->ResourceBarrier(3, destinations.data());
    recorded_ = true;
    return S_OK;
  }
  ID3D12Resource* output(UINT index) const { return index < 3 ? outputs_[index].Get() : nullptr; }
 private:
  bool recorded_{};
  std::array<Microsoft::WRL::ComPtr<ID3D12Resource>, 2> inputs_;
  std::array<Microsoft::WRL::ComPtr<ID3D12Resource>, 3> outputs_;
  Microsoft::WRL::ComPtr<ID3D12RootSignature> root_;
  Microsoft::WRL::ComPtr<ID3D12PipelineState> pipeline_;
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> descriptors_;
};
} // namespace darktidevr::producer
