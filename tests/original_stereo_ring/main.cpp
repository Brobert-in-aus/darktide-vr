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
#include <string_view>
#include <fstream>
#include <filesystem>
#include <iterator>

using Microsoft::WRL::ComPtr;
void check(HRESULT hr) { if(FAILED(hr)) throw std::runtime_error("D3D12 operation failed"); }
void expect(bool value) { if(!value) throw std::runtime_error("Original ring invariant failed"); }
int main(int argc, char** argv) {
  try {
    const bool with_ui = argc == 2 && std::string_view(argv[1]) == "ui";
    darktidevr::tests::isolate_transports();
    if (argc == 2 && std::string_view(argv[1]) == "health") {
      using namespace darktidevr::producer;
      wchar_t temp[MAX_PATH]{}; expect(GetTempPathW(MAX_PATH,temp)>0);
      const auto path=std::filesystem::path(temp) /
          (L"darktidevr-generated-stereo-"+std::to_wstring(GetCurrentProcessId())+L".log");
      const auto read_log=[&]() {
        std::ifstream file(path); expect(file.good());
        return std::string(std::istreambuf_iterator<char>(file),{});
      };
      configure_generated_stereo(true);
      generated_stereo_health(100,10,false,99.0);
      configure_generated_stereo(false);
      Sleep(1050); // A real disabled interval exceeds the native reporting period.
      configure_generated_stereo(true);
      generated_stereo_health(10000,1000,true,2.5);
      auto text=read_log();
      if (text.find("health ")!=std::string::npos || text!="enabled\ndisabled\nenabled\n") {
        throw std::runtime_error("Resumed health window retained disabled time or lost boundaries");
      }
      configure_generated_stereo(true); // Repeated configuration is not a boundary.
      generated_stereo_health(10001,1001,true,2.5);
      expect(read_log()==text);
      Sleep(1050);
      generated_stereo_health(10100,1100,true,2.5);
      text=read_log();
      expect(text.find("health ")!=std::string::npos);
      expect(text.find("present_mean_ms=2.5000")!=std::string::npos);
      expect(text.find("focus_changes=0")!=std::string::npos);
      // Eye-surface recreation resets its ready fence value independently of
      // bridge enablement. Detect the decrease before unsigned FPS subtraction.
      generated_stereo_health(10101,0,true,4.5);
      expect(read_log()==text+"health_boundary reason=counter_regression\n");
      Sleep(1050);
      generated_stereo_health(10201,100,true,4.5);
      text=read_log();
      expect(text.find("present_mean_ms=4.5000")!=std::string::npos);
      configure_generated_stereo(false);
      generated_stereo_health(20000,2000,false,999.0);
      expect(read_log()==text+"disabled\n");
      std::cout << "generated_health_session=pass\n";
      return 0;
    }
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
    D3D12_DESCRIPTOR_HEAP_DESC rtv_desc{}; rtv_desc.Type=D3D12_DESCRIPTOR_HEAP_TYPE_RTV; rtv_desc.NumDescriptors=with_ui ? 3 : 1;
    ComPtr<ID3D12DescriptorHeap> rtv; check(device->CreateDescriptorHeap(&rtv_desc,IID_PPV_ARGS(&rtv)));
    device->CreateRenderTargetView(source.Get(),nullptr,rtv->GetCPUDescriptorHandleForHeapStart());
    std::array<ComPtr<ID3D12Resource>, 2> ui_sources;
    std::array<ID3D12Resource*, 2> ui_inputs{};
    std::array<D3D12_CPU_DESCRIPTOR_HANDLE, 2> ui_rtvs{};
    if (with_ui) for (unsigned eye = 0; eye < 2; ++eye) {
      auto desc = description; desc.Width /= 2;
      check(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &desc,
          D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&ui_sources[eye])));
      ui_inputs[eye] = ui_sources[eye].Get();
      ui_rtvs[eye] = rtv->GetCPUDescriptorHandleForHeapStart();
      ui_rtvs[eye].ptr += (eye + 1) * device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_RTV);
      device->CreateRenderTargetView(ui_inputs[eye], nullptr, ui_rtvs[eye]);
    }
    const auto* ui = with_ui ? &ui_inputs : nullptr;
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
      if (with_ui) {
        for (unsigned eye = 0; eye < 2; ++eye) {
          barrier(ui_inputs[eye], D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_RENDER_TARGET);
          const float alpha = static_cast<float>((eye + 1) * 64) / 255.0F;
          const float pixel[]{static_cast<float>(frame) / 255.0F, alpha, 0, alpha};
          commands->ClearRenderTargetView(ui_rtvs[eye], pixel, 0, nullptr);
          barrier(ui_inputs[eye], D3D12_RESOURCE_STATE_RENDER_TARGET, D3D12_RESOURCE_STATE_COPY_DEST);
        }
        const std::array<ID3D12Resource*, 2> invalid{source.Get(), ui_inputs[1]};
        expect(darktidevr::producer::stage_original_stereo(commands.Get(), source.Get(), frame, 100+frame, 9, &invalid)==0);
      }
      expect(darktidevr::producer::stage_original_stereo(commands.Get(),source.Get(),frame,100+frame,9,ui)==frame);
      execute(); expect(darktidevr::producer::submit_original_stereo(queue.Get(),frame));
    }
    darktidevr::core::SharedGeneratedFrameStateReader reader{L"Local\\DarktideVR-original-frame-state-v1"};
    darktidevr::core::SharedGeneratedFrameState state; expect(reader.read(state)); expect(state.latest_sequence==3);
    expect(state.slots[1].frame_index == (with_ui ? darktidevr::core::kOriginalFrameSeparateUi : 0));
    darktidevr::bridge::SharedGeneratedSurfaceNames names{{L"Local\\DarktideVR-original-stereo-0",L"Local\\DarktideVR-original-stereo-1",L"Local\\DarktideVR-original-stereo-2"},L"Local\\DarktideVR-original-stereo-ready",L"Local\\DarktideVR-original-stereo-consumed"};
    for(auto& name:names.textures) name=darktidevr::core::shared_object_name(name.c_str());
    names.ready_fence=darktidevr::core::shared_object_name(names.ready_fence.c_str());
    names.consumed_fence=darktidevr::core::shared_object_name(names.consumed_fence.c_str());
    auto opened=darktidevr::bridge::open_shared_generated_surfaces(device.Get(),names,{{8,4},DXGI_FORMAT_R8G8B8A8_UNORM});
    reset(); expect(darktidevr::producer::stage_original_stereo(commands.Get(),source.Get(),4,104,9,ui)==0);
    check(opened.consumed_fence->Signal(1));
    expect(darktidevr::producer::stage_original_stereo(commands.Get(),source.Get(),4,104,9,ui)==4);
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
    readback->Unmap(0,nullptr);
    if (with_ui) {
      for (unsigned i = 0; i < 3; ++i)
        names.textures[i] = darktidevr::core::shared_object_name((L"Local\\DarktideVR-original-ui-" + std::to_wstring(i)).c_str());
      auto opened_ui = darktidevr::bridge::open_shared_generated_surfaces(device.Get(), names,
          {{8,4},DXGI_FORMAT_R8G8B8A8_UNORM});
      reset(); barrier(opened_ui.textures[1].Get(), D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_SOURCE);
      from.pResource = opened_ui.textures[1].Get();
      commands->CopyTextureRegion(&to,0,0,0,&from,nullptr);
      barrier(opened_ui.textures[1].Get(), D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_COMMON);
      execute(); check(readback->Map(0,&range,&pixels));
      const auto* data = static_cast<const unsigned char*>(pixels);
      for (unsigned y = 0; y < 4; ++y) for (unsigned x = 0; x < 8; ++x) {
        const auto* pixel = data + footprint.Offset + y * footprint.Footprint.RowPitch + x * 4;
        const auto expected = x < 4 ? 64 : 128;
        expect(pixel[0] == 2 && pixel[1] == expected && pixel[2] == 0 && pixel[3] == expected);
      }
      readback->Unmap(0,nullptr);
    }
    CloseHandle(event);
    std::cout << "original_stereo_ring=pass\n"; return 0;
  } catch(const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
