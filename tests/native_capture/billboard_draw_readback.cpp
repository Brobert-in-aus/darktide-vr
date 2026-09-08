#include "producer/billboard_draw_readback.h"
#include "producer/billboard_resource_state.h"
#include <dxgi1_6.h>
#include <d3d12sdklayers.h>
#include <wrl/client.h>
#include <iostream>
#include <stdexcept>
#include <cstring>

using Microsoft::WRL::ComPtr;
using darktidevr::producer::BillboardDrawReadback;
void check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
void hr(HRESULT value) { check(SUCCEEDED(value), "D3D12 call failed"); }

struct Fixture {
  ComPtr<ID3D12Device> device;
  ComPtr<ID3D12InfoQueue> debug;
  ComPtr<ID3D12CommandQueue> queue, second_queue;
  ComPtr<ID3D12CommandAllocator> allocator, reset_allocator;
  ComPtr<ID3D12GraphicsCommandList> list;
  ComPtr<ID3D12Resource> target;
  ComPtr<ID3D12DescriptorHeap> heap;
  ComPtr<ID3D12Fence> gate, done;
  D3D12_CPU_DESCRIPTOR_HANDLE rtv{};
  UINT64 sequence{};
  Fixture(DXGI_FORMAT format) {
    ComPtr<ID3D12Debug> layer;
    hr(D3D12GetDebugInterface(IID_PPV_ARGS(&layer)));
    layer->EnableDebugLayer();
    ComPtr<IDXGIFactory4> factory;
    ComPtr<IDXGIAdapter> adapter;
    hr(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    hr(factory->EnumWarpAdapter(IID_PPV_ARGS(&adapter)));
    hr(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)));
    hr(device.As(&debug));
    D3D12_COMMAND_QUEUE_DESC q{};
    hr(device->CreateCommandQueue(&q, IID_PPV_ARGS(&queue)));
    hr(device->CreateCommandQueue(&q, IID_PPV_ARGS(&second_queue)));
    hr(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)));
    hr(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&reset_allocator)));
    hr(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr, IID_PPV_ARGS(&list)));
    D3D12_HEAP_PROPERTIES properties{};
    properties.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC desc{};
    desc.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    desc.Width = 3; desc.Height = 2; desc.DepthOrArraySize = 1; desc.MipLevels = 1;
    desc.Format = format; desc.SampleDesc.Count = 1;
    desc.Flags = D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    hr(device->CreateCommittedResource(&properties, D3D12_HEAP_FLAG_NONE, &desc,
        D3D12_RESOURCE_STATE_RENDER_TARGET, nullptr, IID_PPV_ARGS(&target)));
    D3D12_DESCRIPTOR_HEAP_DESC hd{};
    hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_RTV; hd.NumDescriptors = 1;
    hr(device->CreateDescriptorHeap(&hd, IID_PPV_ARGS(&heap)));
    rtv = heap->GetCPUDescriptorHandleForHeapStart();
    device->CreateRenderTargetView(target.Get(), nullptr, rtv);
    hr(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&gate)));
    hr(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&done)));
  }
  void clear(const float* color) { list->ClearRenderTargetView(rtv, color, 0, nullptr); }
  void wait(ID3D12CommandQueue* owner = nullptr) {
    hr((owner ? owner : queue.Get())->Signal(done.Get(), ++sequence));
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    check(event != nullptr, "CreateEvent failed");
    hr(done->SetEventOnCompletion(sequence, event));
    const auto result = WaitForSingleObject(event, 10000);
    CloseHandle(event);
    check(result == WAIT_OBJECT_0, "GPU wait timed out");
  }
  void execute(BillboardDrawReadback& capture, ID3D12CommandQueue* owner = nullptr) {
    if (!owner) owner = queue.Get();
    ID3D12CommandList* lists[]{list.Get()};
    const auto pending = capture.submitting(owner, 1, lists);
    owner->ExecuteCommandLists(1, lists);
    capture.submitted(owner, pending);
  }
  void retire(BillboardDrawReadback& capture) {
    hr(list->Reset(reset_allocator.Get(), nullptr));
    capture.retired(list.Get());
  }
  void errors() {
    for (UINT64 i = 0; i < debug->GetNumStoredMessages(); ++i) {
      SIZE_T size{}; hr(debug->GetMessage(i, nullptr, &size));
      std::vector<std::uint8_t> bytes(size);
      auto* message = reinterpret_cast<D3D12_MESSAGE*>(bytes.data());
      hr(debug->GetMessage(i, message, &size));
      if (message->Severity <= D3D12_MESSAGE_SEVERITY_ERROR) {
        std::cerr << message->pDescription << '\n';
        throw std::runtime_error("GPU validation error");
      }
    }
  }
};

void pixels(DXGI_FORMAT format, std::uint32_t before, std::uint32_t after) {
  Fixture f(format);
  BillboardDrawReadback capture;
  const float black[]{0,0,0,1}, color[]{1,0,0,1};
  f.clear(black);
  auto id = capture.begin(f.list.Get(), f.target.Get(), 1, 2);
  check(id != 0, "Valid capture rejected");
  check(capture.begin(f.list.Get(), f.target.Get(), 1, 2) == 0, "Duplicate pair admitted");
  f.clear(color); capture.end(id, f.list.Get());
  hr(f.list->Close());
  f.execute(capture); f.wait();
  check(capture.collect().empty(), "Unretired recording published");
  // Repeat the same closed recording behind a deliberately unsignaled queue
  // gate. The old fence completion must not authorize reading the new writes.
  hr(f.queue->Wait(f.gate.Get(), 1));
  ID3D12CommandList* lists[]{f.list.Get()};
  const auto pending = capture.submitting(f.queue.Get(), 1, lists);
  f.queue->ExecuteCommandLists(1, lists);
  f.retire(capture);
  check(capture.collect().empty(), "Retirement raced post-execute bookkeeping");
  capture.submitted(f.queue.Get(), pending);
  check(capture.collect().empty(), "Incomplete replay published");
  hr(f.gate->Signal(1)); f.wait();
  const auto results = capture.collect();
  check(results.size() == 1, "Retired completed pair missing");
  const auto& result = results[0];
  check(result.width == 3 && result.height == 2 && result.row_pitch == 256 &&
        result.format == format && result.vertex_shader == 1 && result.pixel_shader == 2,
        "Wrong readback metadata");
  for (UINT y = 0; y < result.height; ++y) for (UINT x = 0; x < result.width; ++x) {
    const auto offset = y * result.row_pitch + x * 4;
    std::uint32_t a{}, b{};
    std::memcpy(&a, result.before.data() + offset, 4);
    std::memcpy(&b, result.after.data() + offset, 4);
    check(a == before && b == after, "Wrong before/after pixels or row stride");
  }
  check(capture.collect().empty(), "Pair published twice");
  for (UINT x = 12; x < result.row_pitch; ++x)
    check(result.before[x] == 0 && result.after[x] == 0, "Undefined row padding exported");
  hr(f.list->Close()); f.errors();
}

void exclusions(bool incomplete, bool multiqueue) {
  Fixture f(DXGI_FORMAT_R8G8B8A8_UNORM);
  BillboardDrawReadback capture;
  const float color[]{0,1,0,1}; f.clear(color);
  auto id = capture.begin(f.list.Get(), f.target.Get(), 3, 4);
  check(id != 0, "Capture rejected");
  if (!incomplete) capture.end(id, f.list.Get());
  hr(f.list->Close());
  if (incomplete || multiqueue) { f.execute(capture); f.wait(); }
  if (multiqueue) { f.execute(capture, f.second_queue.Get()); f.wait(f.second_queue.Get()); }
  f.retire(capture);
  check(capture.collect().empty(), "Abandoned/incomplete/multiqueue pair published");
  hr(f.list->Close()); f.errors();
}

void resource_states() {
  using darktidevr::producer::BillboardResourceState;
  BillboardResourceState state;
  auto* resource = reinterpret_cast<ID3D12Resource*>(1);
  check(!state.known_render_target(resource), "Unknown initial state admitted");
  D3D12_RESOURCE_BARRIER barrier{};
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barrier.Transition.pResource = resource;
  barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
  barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
  state.observe(1, &barrier);
  check(state.known_render_target(resource), "Explicit RT state missing");
  barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_BEGIN_ONLY; state.observe(1, &barrier);
  check(!state.known_render_target(resource), "Split transition admitted");
  barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_END_ONLY; state.observe(1, &barrier);
  check(!state.known_render_target(resource), "Split end admitted");
  barrier.Flags = D3D12_RESOURCE_BARRIER_FLAG_NONE;
  barrier.Transition.Subresource = 1; state.observe(1, &barrier);
  check(!state.known_render_target(resource), "Other subresource admitted");
  barrier.Transition.Subresource = 0; state.observe(1, &barrier);
  check(state.known_render_target(resource), "Subresource zero missing");
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_ALIASING; state.observe(1, &barrier);
  check(!state.known_render_target(resource), "Alias retained stale state");
  barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  state.unknown(); state.observe(1, &barrier);
  check(!state.known_render_target(resource), "Enhanced-barrier exclusion lost");
  state = {};
  for (std::uintptr_t i = 1; i <= 129; ++i) {
    barrier.Transition.pResource = reinterpret_cast<ID3D12Resource*>(i);
    state.observe(1, &barrier);
  }
  check(!state.known_render_target(resource) && state.excluded, "Capacity overflow admitted");
}

int main() {
  try {
    resource_states();
    pixels(DXGI_FORMAT_R8G8B8A8_UNORM, 0xff000000, 0xff0000ff);
    pixels(DXGI_FORMAT_B8G8R8A8_UNORM, 0xff000000, 0xffff0000);
    pixels(DXGI_FORMAT_R11G11B10_FLOAT, 0, 15 << 6);
    exclusions(false, false); exclusions(true, false); exclusions(false, true);
    std::cout << "PASS: 3 real GPU formats, padded rows, before/after pixels, retirement, replay fence, abandoned/incomplete/multiqueue guards; debug layer clean\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; return 1;
  }
}
