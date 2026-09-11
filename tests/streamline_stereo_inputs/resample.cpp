#include "producer/stereo_color_resample.h"
#include "producer/engine_eye_backbuffers.h"
#include "producer/desktop_mirror_blit.h"
#include "core/shared_surface_policy.h"
#include <dxgi1_6.h>
#include <iostream>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
void ok(HRESULT result) { if (FAILED(result)) throw std::runtime_error("GPU operation failed"); }
void check(bool value) { if (!value) throw std::runtime_error("resample mismatch"); }
int main() {
  using Mode = darktidevr::core::SharedPresentationMode;
  for (const auto mode : {Mode::disabled, Mode::stereo_world,
                          Mode::flat_loading_or_cinematic, Mode::world_anchored_menu,
                          Mode::flat_menu, Mode::flat_interactive,
                          Mode::flat_interactive_native_aspect, Mode::error}) {
    check(!darktidevr::producer::suppress_gameplay_mirror(false, mode));
    check(darktidevr::producer::suppress_gameplay_mirror(true, mode) ==
          (mode == Mode::stereo_world));
  }
  for (const auto mode : {Mode::flat_loading_or_cinematic, Mode::flat_interactive,
                          Mode::flat_interactive_native_aspect}) {
    check(darktidevr::producer::engine_flat_mirror_required(true, mode));
    check(!darktidevr::producer::engine_flat_mirror_required(false, mode));
  }
  // Returning to immersive rendering must resume the completed-eye mirror.
  check(!darktidevr::producer::engine_flat_mirror_required(true, Mode::stereo_world));
  check(!darktidevr::producer::engine_flat_mirror_required(true, Mode::world_anchored_menu));
  check(!darktidevr::producer::engine_flat_mirror_required(true, Mode::flat_menu));
  ComPtr<IDXGIFactory4> factory; ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
  ComPtr<IDXGIAdapter> warp; ok(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
  ComPtr<ID3D12Device> device; ok(D3D12CreateDevice(warp.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)));
  {
    darktidevr::producer::EngineEyeBackbuffers proxies;
    D3D12_RESOURCE_DESC description{};
    description.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    description.Width=128; description.Height=48; description.DepthOrArraySize=1;
    description.MipLevels=1; description.SampleDesc.Count=1;
    description.Format=DXGI_FORMAT_R8G8B8A8_UNORM;
    description.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    ComPtr<ID3D12Resource> first, repeated, second, resized;
    ok(proxies.acquire(device.Get(),1,1,0,description,64,48,IID_PPV_ARGS(&first)));
    ok(proxies.acquire(device.Get(),1,1,0,description,64,48,IID_PPV_ARGS(&repeated)));
    ok(proxies.acquire(device.Get(),1,1,1,description,64,48,IID_PPV_ARGS(&second)));
    check(first.Get()==repeated.Get() && first.Get()!=second.Get());
    check(first->GetDesc().Width==64 && first->GetDesc().Height==48);
    description.Width=160; description.Height=96;
    ok(proxies.acquire(device.Get(),1,2,0,description,80,96,IID_PPV_ARGS(&resized)));
    check(resized.Get()!=first.Get() && resized->GetDesc().Width==80);
    check(first->GetDesc().Width==64); // Prior GPU generation remains alive.
    ComPtr<ID3D12Resource> invalid;
    check(FAILED(proxies.acquire(device.Get(),1,2,0,description,79,96,IID_PPV_ARGS(&invalid))));
    D3D12_DESCRIPTOR_HEAP_DESC rtv_heap_desc{};
    rtv_heap_desc.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV; rtv_heap_desc.NumDescriptors=1;
    ComPtr<ID3D12DescriptorHeap> rtv_heap;
    ok(device->CreateDescriptorHeap(&rtv_heap_desc,IID_PPV_ARGS(&rtv_heap)));
    device->CreateRenderTargetView(first.Get(),nullptr,rtv_heap->GetCPUDescriptorHandleForHeapStart());
  }
  ComPtr<ID3D12CommandQueue> queue; D3D12_COMMAND_QUEUE_DESC queue_desc{};
  ok(device->CreateCommandQueue(&queue_desc, IID_PPV_ARGS(&queue)));
  ComPtr<ID3D12CommandAllocator> allocator;
  ok(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)));
  ComPtr<ID3D12GraphicsCommandList> commands;
  ok(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr, IID_PPV_ARGS(&commands)));
  D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
  D3D12_RESOURCE_DESC texture{}; texture.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
  texture.Width=4; texture.Height=1; texture.DepthOrArraySize=1; texture.MipLevels=1;
  texture.Format=DXGI_FORMAT_R8G8B8A8_TYPELESS; texture.SampleDesc.Count=1;
  std::array<ComPtr<ID3D12Resource>,2> inputs;
  for (auto& input:inputs) ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,
      &texture,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&input)));
  D3D12_RESOURCE_DESC buffer{}; buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
  buffer.Width=1024; buffer.Height=1; buffer.DepthOrArraySize=1; buffer.MipLevels=1;
  buffer.SampleDesc.Count=1; buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  heap.Type=D3D12_HEAP_TYPE_UPLOAD; ComPtr<ID3D12Resource> upload;
  ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&buffer,
      D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&upload)));
  void* mapped{}; D3D12_RANGE no_read{0,0}; ok(upload->Map(0,&no_read,&mapped));
  const std::array<UINT,4> left{0xff0000ff,0xff0000ff,0xff00ff00,0xff00ff00};
  const std::array<UINT,4> right{0xffff0000,0xffff0000,0xffffffff,0xffffffff};
  std::memcpy(mapped,left.data(),16);
  std::memcpy(static_cast<char*>(mapped)+512,right.data(),16); upload->Unmap(0,nullptr);
  for (UINT i=0;i<2;++i) {
    D3D12_TEXTURE_COPY_LOCATION src{},dst{}; src.pResource=upload.Get();
    src.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    src.PlacedFootprint={i*512ULL,{texture.Format,4,1,1,256}};
    dst.pResource=inputs[i].Get(); dst.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands->CopyTextureRegion(&dst,0,0,0,&src,nullptr);
  }
  // The engine's offscreen targets are typeless. Cross-process eye textures
  // must expose the negotiated UNORM format, with a bit-preserving copy.
  auto shared_texture = texture;
  shared_texture.Format = static_cast<DXGI_FORMAT>(
      darktidevr::core::canonical_shared_copy_format(texture.Format));
  check(shared_texture.Format == DXGI_FORMAT_R8G8B8A8_UNORM);
  heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  std::array<ComPtr<ID3D12Resource>,2> shared_inputs;
  for (UINT i=0;i<2;++i) {
    ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_SHARED,&shared_texture,
        D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&shared_inputs[i])));
    D3D12_RESOURCE_BARRIER copy_barrier{};
    copy_barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    copy_barrier.Transition={inputs[i].Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_COPY_SOURCE};
    commands->ResourceBarrier(1,&copy_barrier);
    commands->CopyResource(shared_inputs[i].Get(),inputs[i].Get());
    HANDLE shared_handle{};
    ok(device->CreateSharedHandle(shared_inputs[i].Get(),nullptr,GENERIC_ALL,nullptr,&shared_handle));
    ComPtr<ID3D12Device> consumer;
    ok(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&consumer)));
    ComPtr<ID3D12Resource> opened;
    const auto open_result=consumer->OpenSharedHandle(shared_handle,IID_PPV_ARGS(&opened));
    CloseHandle(shared_handle); ok(open_result);
    check(opened->GetDesc().Format==DXGI_FORMAT_R8G8B8A8_UNORM);
  }
  darktidevr::producer::StereoColorResample resample;
  check(FAILED(resample.record(device.Get(),commands.Get(),inputs[0].Get(),inputs[1].Get(),0,1)));
  ok(resample.record(device.Get(),commands.Get(),shared_inputs[0].Get(),shared_inputs[1].Get(),2,1));
  check(FAILED(resample.record(device.Get(),commands.Get(),inputs[0].Get(),inputs[1].Get(),2,1)));
  check(resample.output(0)->GetDesc().Width==2 && resample.output(1)->GetDesc().Width==2);
  heap.Type=D3D12_HEAP_TYPE_READBACK; ComPtr<ID3D12Resource> readback;
  ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&buffer,
      D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&readback)));
  D3D12_RESOURCE_BARRIER barrier{}; barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barrier.Transition={resample.output(2),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_PRESENT,D3D12_RESOURCE_STATE_COPY_SOURCE};
  commands->ResourceBarrier(1,&barrier);
  D3D12_TEXTURE_COPY_LOCATION src{},dst{}; src.pResource=resample.output(2);
  src.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; dst.pResource=readback.Get();
  dst.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
  dst.PlacedFootprint={0,{shared_texture.Format,4,1,1,256}};
  commands->CopyTextureRegion(&dst,0,0,0,&src,nullptr);
  // A monoscopic eye must fill a wider presentation target, including its
  // right edge; leaving a retained/black half is not a successful mirror.
  auto mirror_description=shared_texture;
  mirror_description.Width=8; mirror_description.Height=2;
  mirror_description.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
  heap.Type=D3D12_HEAP_TYPE_DEFAULT;
  ComPtr<ID3D12Resource> mirror;
  ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&mirror_description,
      D3D12_RESOURCE_STATE_PRESENT,nullptr,IID_PPV_ARGS(&mirror)));
  barrier.Transition={shared_inputs[0].Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_COMMON};
  commands->ResourceBarrier(1,&barrier);
  darktidevr::producer::DesktopMirrorBlit mirror_blit;
  ok(mirror_blit.record(device.Get(),commands.Get(),shared_inputs[0].Get(),mirror.Get()));
  barrier.Transition={mirror.Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_PRESENT,D3D12_RESOURCE_STATE_COPY_SOURCE};
  commands->ResourceBarrier(1,&barrier);
  src.pResource=mirror.Get(); dst.PlacedFootprint={512,{shared_texture.Format,8,2,1,256}};
  commands->CopyTextureRegion(&dst,0,0,0,&src,nullptr);
  ok(commands->Close()); ID3D12CommandList* lists[]{commands.Get()};
  queue->ExecuteCommandLists(1,lists);
  ComPtr<ID3D12Fence> fence; ok(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)));
  ok(queue->Signal(fence.Get(),1));
  HANDLE event=CreateEventW(nullptr,FALSE,FALSE,nullptr); check(event!=nullptr);
  ok(fence->SetEventOnCompletion(1,event)); const auto waited=WaitForSingleObject(event,10000);
  CloseHandle(event); check(waited==WAIT_OBJECT_0 && fence->GetCompletedValue()!=UINT64_MAX);
  D3D12_RANGE range{0,1024}; ok(readback->Map(0,&range,&mapped));
  const std::array<UINT,4> expected{left[0],left[2],right[0],right[2]};
  check(std::memcmp(mapped,expected.data(),16)==0);
  for (UINT row=0;row<2;++row) {
    const auto* pixels=reinterpret_cast<const UINT*>(static_cast<const char*>(mapped)+512+row*256);
    check(pixels[0]==left[0] && pixels[7]==left[2]);
    check((pixels[3]&0xff)!=0 && (pixels[3]&0xff00)!=0);
  }
  readback->Unmap(0,&no_read);
  std::cout<<"stereo_color_resample=pass full-image halves preserved on WARP\n";
}
