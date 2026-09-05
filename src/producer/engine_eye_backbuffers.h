#pragma once
#include <d3d12.h>
#include <wrl/client.h>
#include <cstdint>
#include <map>
#include <mutex>
#include <tuple>

namespace darktidevr::producer {
// Bounded diagnostic owner. Retain old generations until process teardown:
// the external wrapper's GPU queues do not yet expose a retirement fence.
// Never retain a real DXGI backbuffer (which would prevent ResizeBuffers).
class EngineEyeBackbuffers {
 public:
  Microsoft::WRL::ComPtr<ID3D12Resource> find(std::uintptr_t swapchain,
                                           std::uint64_t generation, UINT index) {
    std::scoped_lock lock(mutex_);
    const auto found = images_.find(std::make_tuple(swapchain, generation, index));
    return found == images_.end() ? Microsoft::WRL::ComPtr<ID3D12Resource>{} : found->second;
  }
  HRESULT acquire(ID3D12Device* device, std::uintptr_t swapchain,
                  std::uint64_t generation, UINT index,
                  D3D12_RESOURCE_DESC source, UINT width, UINT height,
                  REFIID iid, void** result) {
    if (!device || !swapchain || !result || !width || !height ||
        source.Width != std::uint64_t(width) * 2 || source.Height != height ||
        source.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
        source.SampleDesc.Count != 1 || source.DepthOrArraySize != 1 ||
        source.MipLevels != 1 || source.Format != DXGI_FORMAT_R8G8B8A8_UNORM)
      return E_INVALIDARG;
    *result = nullptr;
    std::scoped_lock lock(mutex_);
    const auto key = std::make_tuple(swapchain, generation, index);
    auto found = images_.find(key);
    if (found != images_.end()) {
      const auto existing = found->second->GetDesc();
      if (existing.Width != width || existing.Height != height) return E_INVALIDARG;
      return found->second->QueryInterface(iid, result);
    }
    if (images_.size() >= 16) return E_OUTOFMEMORY;
    source.Width = width;
    source.Alignment = 0;
    source.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    Microsoft::WRL::ComPtr<ID3D12Resource> image;
    auto hr = device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE,
        &source, D3D12_RESOURCE_STATE_PRESENT, nullptr, IID_PPV_ARGS(&image));
    if (FAILED(hr)) return hr;
    image->SetName(L"DarktideVR engine eye backbuffer");
    hr = image->QueryInterface(iid, result);
    if (SUCCEEDED(hr)) images_.emplace(key, std::move(image));
    return hr;
  }
 private:
  std::mutex mutex_;
  std::map<std::tuple<std::uintptr_t, std::uint64_t, UINT>,
      Microsoft::WRL::ComPtr<ID3D12Resource>> images_;
};
} // namespace darktidevr::producer
