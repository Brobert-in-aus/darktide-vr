#pragma once
#include <d3d12.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <cstring>
#include <utility>

namespace darktidevr::producer {
// One instance per fence-retired command-list slot. Descriptors and references
// may only be updated after that slot's previous submission has completed.
class DesktopMirrorBlit {
 public:
  HRESULT record(ID3D12Device* device, ID3D12GraphicsCommandList* commands,
                 ID3D12Resource* source, ID3D12Resource* destination) {
    if (!device || !commands || !source || !destination || source == destination) return E_INVALIDARG;
    const auto src = source->GetDesc(), dst = destination->GetDesc();
    if (src.Format != DXGI_FORMAT_R8G8B8A8_UNORM || dst.Format != src.Format ||
        src.SampleDesc.Count != 1 || dst.SampleDesc.Count != 1 ||
        src.DepthOrArraySize != 1 || dst.DepthOrArraySize != 1 ||
        !(dst.Flags & D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET)) return E_INVALIDARG;
    if (!pipeline_) {
      const auto hr = initialize(device);
      if (FAILED(hr)) return hr;
    }
    // DXGI owns the destination across Present; retaining it in an idle slot
    // would prevent ResizeBuffers. The source is an independently owned image.
    source_ = source;
    D3D12_SHADER_RESOURCE_VIEW_DESC srv{};
    srv.Format = src.Format; srv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE2D;
    srv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    srv.Texture2D.MipLevels = 1;
    device->CreateShaderResourceView(source, &srv, srv_->GetCPUDescriptorHandleForHeapStart());
    device->CreateRenderTargetView(destination, nullptr, rtv_->GetCPUDescriptorHandleForHeapStart());
    D3D12_RESOURCE_BARRIER barriers[2]{};
    barriers[0].Type = barriers[1].Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barriers[0].Transition = {source, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE};
    barriers[1].Transition = {destination, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_RENDER_TARGET};
    commands->ResourceBarrier(2, barriers);
    ID3D12DescriptorHeap* heaps[]{srv_.Get()};
    commands->SetDescriptorHeaps(1, heaps);
    commands->SetGraphicsRootSignature(root_.Get());
    commands->SetPipelineState(pipeline_.Get());
    commands->SetGraphicsRootDescriptorTable(0, srv_->GetGPUDescriptorHandleForHeapStart());
    const auto target = rtv_->GetCPUDescriptorHandleForHeapStart();
    commands->OMSetRenderTargets(1, &target, FALSE, nullptr);
    const D3D12_VIEWPORT viewport{0, 0, static_cast<float>(dst.Width), static_cast<float>(dst.Height), 0, 1};
    const D3D12_RECT scissor{0, 0, static_cast<LONG>(dst.Width), static_cast<LONG>(dst.Height)};
    commands->RSSetViewports(1, &viewport); commands->RSSetScissorRects(1, &scissor);
    commands->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    commands->DrawInstanced(3, 1, 0, 0);
    for (auto& barrier : barriers) std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    commands->ResourceBarrier(2, barriers);
    return S_OK;
  }
 private:
  HRESULT initialize(ID3D12Device* device) {
    static constexpr char shader[] = R"(
Texture2D<float4> image : register(t0); SamplerState linearClamp : register(s0);
struct Vertex { float4 position : SV_Position; float2 uv : TEXCOORD0; };
Vertex vs(uint id : SV_VertexID) {
    Vertex v; v.uv=float2((id<<1)&2,id&2);
    v.position=float4(v.uv*float2(2,-2)+float2(-1,1),0,1); return v;
}
float4 ps(Vertex v) : SV_Target { return image.SampleLevel(linearClamp,v.uv,0); }
)";
    Microsoft::WRL::ComPtr<ID3DBlob> vs, ps, error, signature;
    auto hr = D3DCompile(shader, std::strlen(shader), nullptr, nullptr, nullptr,
        "vs", "vs_5_1", D3DCOMPILE_ENABLE_STRICTNESS, 0, &vs, &error);
    if (FAILED(hr)) return hr;
    hr = D3DCompile(shader, std::strlen(shader), nullptr, nullptr, nullptr,
        "ps", "ps_5_1", D3DCOMPILE_ENABLE_STRICTNESS, 0, &ps, &error);
    if (FAILED(hr)) return hr;
    D3D12_DESCRIPTOR_RANGE range{D3D12_DESCRIPTOR_RANGE_TYPE_SRV,1,0,0,0};
    D3D12_ROOT_PARAMETER parameter{};
    parameter.ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
    parameter.DescriptorTable = {1, &range}; parameter.ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
    D3D12_STATIC_SAMPLER_DESC sampler{};
    sampler.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
    sampler.AddressU = sampler.AddressV = sampler.AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
    sampler.ComparisonFunc = D3D12_COMPARISON_FUNC_ALWAYS; sampler.MaxLOD = D3D12_FLOAT32_MAX;
    sampler.ShaderVisibility = D3D12_SHADER_VISIBILITY_PIXEL;
    D3D12_ROOT_SIGNATURE_DESC root{1,&parameter,1,&sampler,D3D12_ROOT_SIGNATURE_FLAG_NONE};
    hr = D3D12SerializeRootSignature(&root,D3D_ROOT_SIGNATURE_VERSION_1,&signature,&error);
    if (FAILED(hr)) return hr;
    hr = device->CreateRootSignature(0,signature->GetBufferPointer(),signature->GetBufferSize(),IID_PPV_ARGS(&root_));
    if (FAILED(hr)) return hr;
    D3D12_DESCRIPTOR_HEAP_DESC heap{};
    heap.NumDescriptors=1; heap.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
    heap.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
    hr=device->CreateDescriptorHeap(&heap,IID_PPV_ARGS(&srv_)); if (FAILED(hr)) return hr;
    heap.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV; heap.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
    hr=device->CreateDescriptorHeap(&heap,IID_PPV_ARGS(&rtv_)); if (FAILED(hr)) return hr;
    D3D12_GRAPHICS_PIPELINE_STATE_DESC pso{};
    pso.pRootSignature=root_.Get(); pso.VS={vs->GetBufferPointer(),vs->GetBufferSize()};
    pso.PS={ps->GetBufferPointer(),ps->GetBufferSize()};
    pso.BlendState.RenderTarget[0].RenderTargetWriteMask=D3D12_COLOR_WRITE_ENABLE_ALL;
    pso.RasterizerState.FillMode=D3D12_FILL_MODE_SOLID; pso.RasterizerState.CullMode=D3D12_CULL_MODE_NONE;
    pso.RasterizerState.DepthClipEnable=TRUE; pso.SampleMask=UINT_MAX;
    pso.PrimitiveTopologyType=D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    pso.NumRenderTargets=1; pso.RTVFormats[0]=DXGI_FORMAT_R8G8B8A8_UNORM; pso.SampleDesc.Count=1;
    return device->CreateGraphicsPipelineState(&pso,IID_PPV_ARGS(&pipeline_));
  }
  Microsoft::WRL::ComPtr<ID3D12RootSignature> root_;
  Microsoft::WRL::ComPtr<ID3D12PipelineState> pipeline_;
  Microsoft::WRL::ComPtr<ID3D12DescriptorHeap> srv_, rtv_;
  Microsoft::WRL::ComPtr<ID3D12Resource> source_;
};
} // namespace darktidevr::producer
