// Isolated hardware experiment. No game process, headset, rendering or publication.
#include "producer/stereo_input_copy.h"
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <chrono>
#include <iostream>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
using namespace darktidevr::producer;
void ok(HRESULT value) { if (FAILED(value)) throw std::runtime_error("D3D12 benchmark operation failed"); }
void serial_copy(ID3D12GraphicsCommandList* commands, const std::array<StereoInputCopy, 5>& copies) {
  for (unsigned i = 0; i < 4; ++i) {
    const auto& copy = copies[i];
    D3D12_RESOURCE_BARRIER barrier{}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition = {copy.source, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                          copy.source_state, D3D12_RESOURCE_STATE_COPY_SOURCE};
    if (copy.source_state != D3D12_RESOURCE_STATE_COPY_SOURCE) commands->ResourceBarrier(1, &barrier);
    commands->CopyResource(copy.destination, copy.source);
    std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    if (copy.source_state != D3D12_RESOURCE_STATE_COPY_SOURCE) commands->ResourceBarrier(1, &barrier);
  }
}
int main() {
  ComPtr<IDXGIFactory6> factory; ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
  ComPtr<IDXGIAdapter1> adapter;
  ok(factory->EnumAdapterByGpuPreference(0, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&adapter)));
  DXGI_ADAPTER_DESC1 adapter_desc{}; ok(adapter->GetDesc1(&adapter_desc));
  if (adapter_desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) throw std::runtime_error("Hardware adapter required");
  ComPtr<ID3D12Device> device; ok(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)));
  std::wcout << L"adapter=" << adapter_desc.Description << L"\n";
  ComPtr<ID3D12CommandQueue> queue; D3D12_COMMAND_QUEUE_DESC q{};
  ok(device->CreateCommandQueue(&q, IID_PPV_ARGS(&queue)));
  ComPtr<ID3D12CommandAllocator> allocator;
  ok(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)));
  ComPtr<ID3D12GraphicsCommandList> commands;
  ok(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr, IID_PPV_ARGS(&commands)));
  ok(commands->Close());
  std::array<ComPtr<ID3D12Resource>, 4> sources, targets;
  std::array<StereoInputCopy, 5> copies{};
  const DXGI_FORMAT formats[]{DXGI_FORMAT_R32G8X24_TYPELESS, DXGI_FORMAT_R16G16_TYPELESS,
                             DXGI_FORMAT_R8G8B8A8_TYPELESS, DXGI_FORMAT_R8G8B8A8_TYPELESS};
  const D3D12_RESOURCE_FLAGS flags[]{D3D12_RESOURCE_FLAG_ALLOW_DEPTH_STENCIL,
      D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET | D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS,
      D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET, D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET};
  D3D12_HEAP_PROPERTIES heap{}; heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  for (unsigned i = 0; i < 4; ++i) {
    D3D12_RESOURCE_DESC texture{}; texture.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    texture.Width = i < 2 ? 1664 : 2496; texture.Height = i < 2 ? 1792 : 2688;
    texture.DepthOrArraySize = 1; texture.MipLevels = 1; texture.SampleDesc.Count = 1;
    texture.Format = formats[i]; texture.Flags = flags[i];
    const auto state = i == 3 ? D3D12_RESOURCE_STATE_COMMON : D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
    ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &texture, state, nullptr, IID_PPV_ARGS(&sources[i])));
    ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &texture,
        D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&targets[i])));
    copies[i] = {sources[i].Get(), targets[i].Get(), state};
    std::cout << "role=" << i << " width=" << texture.Width << " height=" << texture.Height
              << " format=" << texture.Format << " flags=" << texture.Flags << " state=" << state << '\n';
  }
  ComPtr<ID3D12QueryHeap> queries; D3D12_QUERY_HEAP_DESC query_desc{};
  query_desc.Count = 2; query_desc.Type = D3D12_QUERY_HEAP_TYPE_TIMESTAMP;
  ok(device->CreateQueryHeap(&query_desc, IID_PPV_ARGS(&queries)));
  D3D12_RESOURCE_DESC buffer{}; buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  buffer.Width = 16; buffer.Height = buffer.DepthOrArraySize = buffer.MipLevels = 1;
  buffer.SampleDesc.Count = 1; buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  heap.Type = D3D12_HEAP_TYPE_READBACK; ComPtr<ID3D12Resource> readback;
  ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &buffer,
      D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&readback)));
  ComPtr<ID3D12Fence> fence; ok(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)));
  HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (!event) throw std::runtime_error("Fence event unavailable");
  UINT64 frequency{}; ok(queue->GetTimestampFrequency(&frequency));
  if (!frequency) throw std::runtime_error("GPU timestamp frequency unavailable");
  UINT64 ticket{};
  constexpr unsigned repetitions = 32;
  std::cout << "scope=isolated_repeated_copy no_render_writes=1 no_game=1 debug_layer=0 repetitions=" << repetitions << '\n';
  for (unsigned pair = 0; pair < 22; ++pair) for (unsigned order = 0; order < 2; ++order) {
    const bool batched = (pair + order) % 2 != 0;
    ok(allocator->Reset()); ok(commands->Reset(allocator.Get(), nullptr));
    commands->EndQuery(queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP, 0);
    const auto begin = std::chrono::steady_clock::now();
    for (unsigned i = 0; i < repetitions; ++i) {
      if (batched) record_stereo_input_copies(commands.Get(), copies, 4);
      else serial_copy(commands.Get(), copies);
    }
    const auto end = std::chrono::steady_clock::now();
    commands->EndQuery(queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP, 1);
    commands->ResolveQueryData(queries.Get(), D3D12_QUERY_TYPE_TIMESTAMP, 0, 2, readback.Get(), 0);
    ok(commands->Close()); ID3D12CommandList* lists[]{commands.Get()}; queue->ExecuteCommandLists(1, lists);
    ok(queue->Signal(fence.Get(), ++ticket)); ok(fence->SetEventOnCompletion(ticket, event));
    if (WaitForSingleObject(event, 10000) != WAIT_OBJECT_0 || fence->GetCompletedValue() == UINT64_MAX)
      throw std::runtime_error("GPU completion failed");
    void* mapped{}; D3D12_RANGE range{0, 16}; ok(readback->Map(0, &range, &mapped));
    const auto* times = static_cast<UINT64*>(mapped);
    if (times[1] < times[0]) throw std::runtime_error("Invalid timestamp order");
    const double gpu_us = static_cast<double>(times[1] - times[0]) * 1e6 / static_cast<double>(frequency) / repetitions;
    D3D12_RANGE none{0, 0}; readback->Unmap(0, &none);
    const double cpu_us = std::chrono::duration<double, std::micro>(end - begin).count() / repetitions;
    std::cout << "pair=" << pair << " order=" << order << " mode=" << (batched ? "batch" : "serial")
              << " warmup=" << (pair < 2 ? 1 : 0) << " cpu_us=" << cpu_us << " gpu_us=" << gpu_us << '\n';
  }
  CloseHandle(event);
}
