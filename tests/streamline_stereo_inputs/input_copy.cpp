#include "producer/stereo_input_copy.h"
#include "producer/stereo_color_pack.h"
#include <d3d12sdklayers.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>
using Microsoft::WRL::ComPtr;
using namespace darktidevr::producer;
void check(bool value) { if (!value) throw std::runtime_error("stereo input copy mismatch"); }
void ok(HRESULT value) { check(SUCCEEDED(value)); }
struct CountedCommands {
  ID3D12GraphicsCommandList* commands;
  unsigned barriers{}, copies{};
  void ResourceBarrier(UINT count, const D3D12_RESOURCE_BARRIER* values) {
    ++barriers; commands->ResourceBarrier(count, values);
  }
  void CopyResource(ID3D12Resource* target, ID3D12Resource* source) {
    ++copies; commands->CopyResource(target, source);
  }
  void CopyTextureRegion(const D3D12_TEXTURE_COPY_LOCATION* target, UINT x, UINT y, UINT z,
      const D3D12_TEXTURE_COPY_LOCATION* source, const D3D12_BOX* box) {
    ++copies; commands->CopyTextureRegion(target, x, y, z, source, box);
  }
};
int main() {
  ComPtr<ID3D12Debug> debug;
  ok(D3D12GetDebugInterface(IID_PPV_ARGS(&debug)));
  debug->EnableDebugLayer();
  ComPtr<IDXGIFactory4> factory; ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
  ComPtr<IDXGIAdapter> warp; ok(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
  ComPtr<ID3D12Device> device;
  ok(D3D12CreateDevice(warp.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)));
  ComPtr<ID3D12InfoQueue> info; ok(device.As(&info));
  ComPtr<ID3D12CommandQueue> queue; D3D12_COMMAND_QUEUE_DESC q{};
  ok(device->CreateCommandQueue(&q, IID_PPV_ARGS(&queue)));
  ComPtr<ID3D12CommandAllocator> allocator;
  ok(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)));
  ComPtr<ID3D12GraphicsCommandList> commands;
  ok(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr, IID_PPV_ARGS(&commands)));
  D3D12_RESOURCE_DESC texture{};
  texture.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
  texture.Width = 4; texture.Height = 1; texture.DepthOrArraySize = 1;
  texture.MipLevels = 1; texture.SampleDesc.Count = 1; texture.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  D3D12_HEAP_PROPERTIES heap{}; heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  std::array<ComPtr<ID3D12Resource>, 5> sources, targets;
  for (unsigned i = 0; i < 5; ++i) {
    ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &texture,
        D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&sources[i])));
    ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &texture,
        D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&targets[i])));
  }
  D3D12_RESOURCE_DESC buffer{}; buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  buffer.Width = 2560; buffer.Height = 1; buffer.DepthOrArraySize = 1;
  buffer.MipLevels = 1; buffer.SampleDesc.Count = 1; buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  ComPtr<ID3D12Resource> upload;
  heap.Type = D3D12_HEAP_TYPE_UPLOAD;
  ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &buffer,
      D3D12_RESOURCE_STATE_GENERIC_READ, nullptr, IID_PPV_ARGS(&upload)));
  void* mapped{}; D3D12_RANGE none{0, 0}; ok(upload->Map(0, &none, &mapped));
  for (unsigned i = 0; i < 5; ++i) std::memset(static_cast<char*>(mapped) + i * 512, 30 + i, 16);
  upload->Unmap(0, nullptr);
  std::array<StereoInputCopy, 5> copies{};
  for (unsigned i = 0; i < 5; ++i) {
    D3D12_TEXTURE_COPY_LOCATION from{}, to{};
    from.pResource = upload.Get(); from.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    from.PlacedFootprint = {i * 512ULL, {texture.Format, 4, 1, 1, 256}};
    to.pResource = sources[i].Get(); to.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands->CopyTextureRegion(&to, 0, 0, 0, &from, nullptr);
    copies[i] = {sources[i].Get(), targets[i].Get(), D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE};
    D3D12_RESOURCE_BARRIER barrier{}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition = {sources[i].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                          D3D12_RESOURCE_STATE_COPY_DEST, copies[i].source_state};
    commands->ResourceBarrier(1, &barrier);
  }
  std::vector<ComPtr<ID3D12Resource>> readbacks;
  for (unsigned trial = 0; trial < 4; ++trial) {
    auto trial_copies = copies;
    if (trial == 3) for (auto& copy : trial_copies) {
      D3D12_RESOURCE_BARRIER barrier{}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition = {copy.source, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                            copy.source_state, D3D12_RESOURCE_STATE_COPY_SOURCE};
      commands->ResourceBarrier(1, &barrier);
      copy.source_state = D3D12_RESOURCE_STATE_COPY_SOURCE;
    }
    if (trial == 2) trial_copies[4].source = trial_copies[0].source;
    const unsigned count = trial == 0 ? 4U : 5U;
    CountedCommands counted{commands.Get()};
    record_stereo_input_copies(&counted, trial_copies, count);
    check(counted.copies == count && counted.barriers == (trial == 3 ? 0U : trial == 2 ? 10U : 2U));
    heap.Type = D3D12_HEAP_TYPE_READBACK;
    ComPtr<ID3D12Resource> readback;
    ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &buffer,
        D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&readback)));
    for (unsigned i = 0; i < count; ++i) {
      D3D12_RESOURCE_BARRIER barrier{}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition = {targets[i].Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                            D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COPY_SOURCE};
      commands->ResourceBarrier(1, &barrier);
      D3D12_TEXTURE_COPY_LOCATION from{}, to{};
      from.pResource = targets[i].Get(); from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
      to.pResource = readback.Get(); to.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
      to.PlacedFootprint = {i * 512ULL, {texture.Format, 4, 1, 1, 256}};
      commands->CopyTextureRegion(&to, 0, 0, 0, &from, nullptr);
      std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
      commands->ResourceBarrier(1, &barrier);
    }
    readbacks.push_back(readback);
  }
  ComPtr<ID3D12Resource> packed, packed_readback;
  heap.Type = D3D12_HEAP_TYPE_DEFAULT; texture.Width = 8;
  ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &texture,
      D3D12_RESOURCE_STATE_PRESENT, nullptr, IID_PPV_ARGS(&packed)));
  heap.Type = D3D12_HEAP_TYPE_READBACK;
  ok(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &buffer,
      D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&packed_readback)));
  for (unsigned trial = 0; trial < 2; ++trial) {
    CountedCommands counted{commands.Get()};
    record_stereo_color_pack(&counted, packed.Get(),
        {targets[0].Get(), targets[trial == 0 ? 1 : 0].Get()}, 4);
    check(counted.barriers == 2 && counted.copies == 2);
    D3D12_RESOURCE_BARRIER barrier{}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition = {packed.Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_PRESENT, D3D12_RESOURCE_STATE_COPY_SOURCE};
    commands->ResourceBarrier(1, &barrier);
    D3D12_TEXTURE_COPY_LOCATION from{}, to{};
    from.pResource = packed.Get(); from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    to.pResource = packed_readback.Get(); to.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    to.PlacedFootprint = {trial * 512ULL, {texture.Format, 8, 1, 1, 256}};
    commands->CopyTextureRegion(&to, 0, 0, 0, &from, nullptr);
    std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    commands->ResourceBarrier(1, &barrier);
  }
  ok(commands->Close()); ID3D12CommandList* lists[]{commands.Get()}; queue->ExecuteCommandLists(1, lists);
  ComPtr<ID3D12Fence> fence; ok(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)));
  ok(queue->Signal(fence.Get(), 1)); HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr); check(event != nullptr);
  ok(fence->SetEventOnCompletion(1, event)); const auto waited = WaitForSingleObject(event, 10000);
  CloseHandle(event); check(waited == WAIT_OBJECT_0 && fence->GetCompletedValue() != UINT64_MAX);
  for (unsigned trial = 0; trial < readbacks.size(); ++trial) {
    D3D12_RANGE range{0, 2560}; ok(readbacks[trial]->Map(0, &range, &mapped));
    for (unsigned i = 0; i < (trial == 0 ? 4U : 5U); ++i)
      for (unsigned byte = 0; byte < 16; ++byte)
        check(static_cast<unsigned char*>(mapped)[i * 512 + byte] == 30 + (trial == 2 && i == 4 ? 0 : i));
    readbacks[trial]->Unmap(0, &none);
  }
  D3D12_RANGE packed_range{0, 1024}; ok(packed_readback->Map(0, &packed_range, &mapped));
  for (unsigned trial = 0; trial < 2; ++trial)
    for (unsigned byte = 0; byte < 32; ++byte)
      check(static_cast<unsigned char*>(mapped)[trial * 512 + byte] ==
          30 + (trial == 0 && byte >= 16 ? 1 : 0));
  packed_readback->Unmap(0, &none);
  for (UINT64 i = 0; i < info->GetNumStoredMessages(); ++i) {
    SIZE_T length{}; ok(info->GetMessage(i, nullptr, &length)); std::vector<char> bytes(length);
    auto* message = reinterpret_cast<D3D12_MESSAGE*>(bytes.data()); ok(info->GetMessage(i, message, &length));
    if (message->Severity <= D3D12_MESSAGE_SEVERITY_WARNING) {
      std::cerr << message->pDescription << '\n'; check(false);
    }
  }
  std::cout << "stereo_input_copy=pass WARP pixels restored states four/five inputs alias fallback; barriers 8/10 -> 2\n";
}
