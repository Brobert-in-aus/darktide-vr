#include "producer/ngx_gpu_timing.h"
#include <wrl/client.h>
#include <dxgi1_4.h>
#include <iostream>
#include <stdexcept>
#include <fstream>
#include <filesystem>
#include <cstdio>
using namespace darktidevr::producer;
using Microsoft::WRL::ComPtr;
void check(HRESULT hr) { if (FAILED(hr)) throw std::runtime_error("D3D12 failure"); }
void expect(bool value) { if (!value) throw std::runtime_error("GPU profiler invariant failed"); }
int main(int argc, char**) {
  try {
    ComPtr<IDXGIFactory4> factory; check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter> warp; check(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
    ComPtr<ID3D12Device> device; check(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)));
    const auto type=argc>1 ? D3D12_COMMAND_LIST_TYPE_COMPUTE : D3D12_COMMAND_LIST_TYPE_DIRECT;
    D3D12_COMMAND_QUEUE_DESC q{}; q.Type=type; ComPtr<ID3D12CommandQueue> queue;
    check(device->CreateCommandQueue(&q,IID_PPV_ARGS(&queue)));
    ComPtr<ID3D12CommandAllocator> allocator;
    check(device->CreateCommandAllocator(type,IID_PPV_ARGS(&allocator)));
    ComPtr<ID3D12GraphicsCommandList> commands;
    check(device->CreateCommandList(0,type,allocator.Get(),nullptr,IID_PPV_ARGS(&commands)));
    const NgxGpuTimingWorkload initial{1,100,100};
    expect(begin_ngx_gpu_timing(commands.Get(),0,initial)==0);
    configure_ngx_gpu_timing(true);
    expect(begin_ngx_gpu_timing(commands.Get(),0,{0,100,100})==0);
    expect(begin_ngx_gpu_timing(commands.Get(),0,{1,0,100})==0);
    expect(begin_ngx_gpu_timing(commands.Get(),0,{1,100,0})==0);
    for (unsigned i=0;i<32;++i) expect(begin_ngx_gpu_timing(commands.Get(),i%2,initial)!=0);
    expect(begin_ngx_gpu_timing(commands.Get(),0,initial)==0); // Capacity never waits.
    reset_ngx_gpu_timing(commands.Get()); // Discard unsubmitted recordings.
    check(commands->Close()); check(allocator->Reset()); check(commands->Reset(allocator.Get(),nullptr));
    ComPtr<ID3D12Fence> done; check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&done)));
    HANDLE event=CreateEventW(nullptr,FALSE,FALSE,nullptr); expect(event!=nullptr);
    for (UINT64 frame=1;frame<=302;++frame) {
      const NgxGpuTimingWorkload workload{frame<=60 ? 1ULL : 2ULL,
          frame<=120 ? 100U : 200U,frame<=180 ? 100U : 200U};
      for (unsigned eye=0;eye<2;++eye) {
        auto token=begin_ngx_gpu_timing(commands.Get(),eye,workload); expect(token!=0);
        mark_ngx_gpu_timing(token,commands.Get());
        end_ngx_gpu_timing(token,commands.Get(),true);
      }
      check(commands->Close()); ID3D12CommandList* lists[]{commands.Get()};
      queue->ExecuteCommandLists(1,lists); submit_ngx_gpu_timing(queue.Get(),1,lists);
      // A reset notification must never recycle a submitted sample early.
      reset_ngx_gpu_timing(commands.Get());
      check(queue->Signal(done.Get(),frame)); check(done->SetEventOnCompletion(frame,event));
      expect(WaitForSingleObject(event,10000)==WAIT_OBJECT_0);
      check(allocator->Reset()); check(commands->Reset(allocator.Get(),nullptr));
    }
    check(commands->Close()); CloseHandle(event);
    const auto path=std::filesystem::temp_directory_path()/
        (L"darktidevr-ngx-gpu-timing-"+std::to_wstring(GetCurrentProcessId())+L".log");
    std::ifstream input(path); std::string line; unsigned rows=0;
    unsigned groups[4][2]{};
    while (std::getline(input,line)) {
      unsigned eye{},samples{},width{},height{};
      unsigned long long tick{},lifetime{};
      double evaluate{},post{};
      char boundary[32]{};
      expect(sscanf_s(line.c_str(),
          "NGX_GPU_TIMING tick_ms=%llu eye=%u samples=%u evaluate_gpu_ms=%lf post_evaluate_gpu_ms=%lf "
          "feature_lifetime=%llu eye_width=%u eye_height=%u boundary=%31s",
          &tick,&eye,&samples,&evaluate,&post,&lifetime,&width,&height,boundary,
          static_cast<unsigned>(sizeof(boundary)))==9);
      expect(eye<2 && evaluate>=0 && post>=0);
      const unsigned group=lifetime==1 ? 0U : width==100 ? 1U : height==100 ? 2U : 3U;
      expect(lifetime==(group==0 ? 1ULL : 2ULL));
      expect(width==(group<2 ? 100U : 200U) && height==(group<3 ? 100U : 200U));
      expect(samples==(group<3 ? 60U : 120U));
      expect(std::string(boundary)==(group<3 ? "workload_change" : "sample_limit"));
      ++groups[group][eye]; ++rows;
    }
    expect(rows==8);
    for (const auto& group:groups) for (const auto count:group) expect(count==1);
    std::cout << "ngx_gpu_timing=pass capacity reset completion readback both_eyes workload_boundaries\n";
  } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
