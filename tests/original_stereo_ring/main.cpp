#include "../isolated_transports.h"
#include "producer/generated_stereo.h"
#include "bridge/shared_eye_surfaces.h"
#include "core/shared_generated_frame_state.h"
#include "core/shared_object_name.h"
#include <Windows.h>
#include <dxgi1_4.h>
#include <d3d12.h>
#include <wrl/client.h>
#include <iostream>
#include <stdexcept>

using Microsoft::WRL::ComPtr;
void check(HRESULT hr) { if(FAILED(hr)) throw std::runtime_error("D3D12 operation failed"); }
void expect(bool value) { if(!value) throw std::runtime_error("Original ring invariant failed"); }
int main() {
  try {
    darktidevr::tests::isolate_transports();
    ComPtr<IDXGIFactory4> factory; check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter> warp; check(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
    ComPtr<ID3D12Device> device; check(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)));
    ComPtr<ID3D12CommandQueue> queue; D3D12_COMMAND_QUEUE_DESC queue_desc{};
    check(device->CreateCommandQueue(&queue_desc,IID_PPV_ARGS(&queue)));
    ComPtr<ID3D12CommandAllocator> allocator;
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)));
    ComPtr<ID3D12GraphicsCommandList> commands;
    check(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),nullptr,IID_PPV_ARGS(&commands)));
    D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC description{}; description.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    description.Width=8; description.Height=4; description.DepthOrArraySize=1; description.MipLevels=1;
    description.Format=DXGI_FORMAT_R8G8B8A8_UNORM; description.SampleDesc.Count=1;
    description.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
    ComPtr<ID3D12Resource> source;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&description,D3D12_RESOURCE_STATE_COMMON,nullptr,IID_PPV_ARGS(&source)));
    D3D12_DESCRIPTOR_HEAP_DESC rtv_desc{}; rtv_desc.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV; rtv_desc.NumDescriptors=1;
    ComPtr<ID3D12DescriptorHeap> rtv; check(device->CreateDescriptorHeap(&rtv_desc,IID_PPV_ARGS(&rtv)));
    device->CreateRenderTargetView(source.Get(),nullptr,rtv->GetCPUDescriptorHandleForHeapStart());
    ComPtr<ID3D12Fence> done; check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&done)));
    const auto event=CreateEventW(nullptr,FALSE,FALSE,nullptr); expect(event!=nullptr);
    std::uint64_t fence_value{};
    auto execute=[&] {
      check(commands->Close()); ID3D12CommandList* lists[]{commands.Get()}; queue->ExecuteCommandLists(1,lists);
      check(queue->Signal(done.Get(),++fence_value)); check(done->SetEventOnCompletion(fence_value,event));
      expect(WaitForSingleObject(event,10000)==WAIT_OBJECT_0);
    };
    auto reset=[&] { check(allocator->Reset()); check(commands->Reset(allocator.Get(),nullptr)); };
    auto barrier=[&](ID3D12Resource* texture,D3D12_RESOURCE_STATES before,D3D12_RESOURCE_STATES after) {
      D3D12_RESOURCE_BARRIER b{}; b.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      b.Transition={texture,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,before,after}; commands->ResourceBarrier(1,&b);
    };
    darktidevr::producer::configure_generated_stereo(true);
    for(std::uint64_t frame=1;frame<=3;++frame) {
      if(frame>1) reset();
      barrier(source.Get(),D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_RENDER_TARGET);
      const float colour[]{static_cast<float>(frame)/255.0F,0,1,1};
      commands->ClearRenderTargetView(rtv->GetCPUDescriptorHandleForHeapStart(),colour,0,nullptr);
      barrier(source.Get(),D3D12_RESOURCE_STATE_RENDER_TARGET,D3D12_RESOURCE_STATE_COMMON);
      expect(darktidevr::producer::stage_original_stereo(commands.Get(),source.Get(),frame,100+frame,9)==frame);
      execute(); expect(darktidevr::producer::submit_original_stereo(queue.Get(),frame));
    }
    darktidevr::core::SharedGeneratedFrameStateReader reader{L"Local\\DarktideVR-original-frame-state-v1"};
    darktidevr::core::SharedGeneratedFrameState state; expect(reader.read(state)); expect(state.latest_sequence==3);
    darktidevr::bridge::SharedGeneratedSurfaceNames names{{L"Local\\DarktideVR-original-stereo-0",L"Local\\DarktideVR-original-stereo-1",L"Local\\DarktideVR-original-stereo-2"},L"Local\\DarktideVR-original-stereo-ready",L"Local\\DarktideVR-original-stereo-consumed"};
    for(auto& name:names.textures) name=darktidevr::core::shared_object_name(name.c_str());
    names.ready_fence=darktidevr::core::shared_object_name(names.ready_fence.c_str());
    names.consumed_fence=darktidevr::core::shared_object_name(names.consumed_fence.c_str());
    auto opened=darktidevr::bridge::open_shared_generated_surfaces(device.Get(),names,{{8,4},DXGI_FORMAT_R8G8B8A8_UNORM});
    reset(); expect(darktidevr::producer::stage_original_stereo(commands.Get(),source.Get(),4,104,9)==0);
    check(opened.consumed_fence->Signal(1));
    expect(darktidevr::producer::stage_original_stereo(commands.Get(),source.Get(),4,104,9)==4);
    execute(); expect(darktidevr::producer::submit_original_stereo(queue.Get(),4));
    expect(reader.read(state) && state.latest_sequence==4 && state.slots[0].current_pose==104);
    // Read the untouched second slot: recycling slot zero must not overwrite
    // another unconsumed original, and the copied source pixels must survive.
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{}; UINT rows{}; UINT64 row_bytes{},bytes{};
    device->GetCopyableFootprints(&description,0,1,0,&footprint,&rows,&row_bytes,&bytes);
    D3D12_RESOURCE_DESC buffer{}; buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER; buffer.Width=bytes;
    buffer.Height=1; buffer.DepthOrArraySize=1; buffer.MipLevels=1; buffer.SampleDesc.Count=1; buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    heap.Type=D3D12_HEAP_TYPE_READBACK; ComPtr<ID3D12Resource> readback;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&buffer,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&readback)));
    reset(); barrier(opened.textures[1].Get(),D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_COPY_SOURCE);
    D3D12_TEXTURE_COPY_LOCATION from{}; from.pResource=opened.textures[1].Get(); from.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    D3D12_TEXTURE_COPY_LOCATION to{}; to.pResource=readback.Get(); to.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; to.PlacedFootprint=footprint;
    commands->CopyTextureRegion(&to,0,0,0,&from,nullptr);
    barrier(opened.textures[1].Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_COMMON); execute();
    void* pixels{}; const D3D12_RANGE range{0,static_cast<SIZE_T>(bytes)}; check(readback->Map(0,&range,&pixels));
    const auto* rgba=static_cast<const unsigned char*>(pixels); expect(rgba[0]==2 && rgba[2]==255 && rgba[3]==255);
    readback->Unmap(0,nullptr); CloseHandle(event);
    std::cout << "original_stereo_ring=pass\n"; return 0;
  } catch(const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
