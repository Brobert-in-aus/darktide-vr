#include "producer/ngx_gpu_timing.h"
#include <wrl/client.h>
#include <dxgi1_4.h>
#include <iostream>
#include <stdexcept>
#include <fstream>
#include <filesystem>
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
    expect(begin_ngx_gpu_timing(commands.Get(),0)==0);
    configure_ngx_gpu_timing(true);
    for (unsigned i=0;i<32;++i) expect(begin_ngx_gpu_timing(commands.Get(),i%2)!=0);
    expect(begin_ngx_gpu_timing(commands.Get(),0)==0); // Capacity never waits.
    reset_ngx_gpu_timing(commands.Get()); // Discard unsubmitted recordings.
    check(commands->Close()); check(allocator->Reset()); check(commands->Reset(allocator.Get(),nullptr));
    ComPtr<ID3D12Fence> done; check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&done)));
    HANDLE event=CreateEventW(nullptr,FALSE,FALSE,nullptr); expect(event!=nullptr);
    for (UINT64 frame=1;frame<=242;++frame) {
      for (unsigned eye=0;eye<2;++eye) {
        auto token=begin_ngx_gpu_timing(commands.Get(),eye); expect(token!=0);
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
    while (std::getline(input,line)) {
      expect(line.find("samples=120")!=std::string::npos);
      expect(line.find("evaluate_gpu_ms=")!=std::string::npos); ++rows;
    }
    expect(rows==4);
    std::cout << "ngx_gpu_timing=pass capacity reset completion readback both_eyes\n";
  } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
