#include "../isolated_transports.h"
#include <Windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <array>
#include <chrono>
#include <iostream>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
void ok(HRESULT hr) {if(FAILED(hr)) throw std::runtime_error("D3D12 operation failed");}
int wmain(int argc,wchar_t** argv) {
  try {
    if(argc!=2) throw std::invalid_argument("Expected copied native DLL path");
    darktidevr::tests::isolate_transports();
    const auto module=LoadLibraryW(argv[1]);
    if(!module) throw std::runtime_error("DLL load failed");
    const auto install=reinterpret_cast<int(*)()>(GetProcAddress(module,"dtvr_install"));
    const auto diagnostics=reinterpret_cast<int(*)(int)>(GetProcAddress(module,"dtvr_set_diagnostic_render_hooks"));
    if(!install||!diagnostics||diagnostics(1)!=0||install()!=0) throw std::runtime_error("Hook installation failed");
    ComPtr<ID3D12Device> device;
    ok(D3D12CreateDevice(nullptr,D3D_FEATURE_LEVEL_12_0,IID_PPV_ARGS(&device)));
    ComPtr<IDXGIFactory4> factory;
    ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter1> adapter;
    ok(factory->EnumAdapterByLuid(device->GetAdapterLuid(),IID_PPV_ARGS(&adapter)));
    DXGI_ADAPTER_DESC1 adapter_desc{};
    ok(adapter->GetDesc1(&adapter_desc));
    LARGE_INTEGER driver{};
    ok(adapter->CheckInterfaceSupport(__uuidof(IDXGIDevice),&driver));
    std::cout << "adapter_vendor=" << adapter_desc.VendorId
      << " adapter_device=" << adapter_desc.DeviceId
      << " adapter_software=" << ((adapter_desc.Flags&DXGI_ADAPTER_FLAG_SOFTWARE)!=0)
      << " driver_version=" << driver.QuadPart << '\n';
    ComPtr<ID3D12CommandAllocator> allocator;
    ok(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)));
    ComPtr<ID3D12GraphicsCommandList> commands;
    ok(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),nullptr,IID_PPV_ARGS(&commands)));
    D3D12_HEAP_PROPERTIES heap{};heap.Type=D3D12_HEAP_TYPE_DEFAULT;
    for(const unsigned workload:{0U,1U,2U}) {
      D3D12_RESOURCE_DESC desc{};desc.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
      desc.Width=workload==0?2112:1920;desc.Height=workload==0?1188:workload==1?2160:1080;
      desc.DepthOrArraySize=1;desc.MipLevels=1;desc.Format=DXGI_FORMAT_R16G16B16A16_FLOAT;
      desc.SampleDesc.Count=1;desc.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
      ComPtr<ID3D12Resource> resource;
      ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,
        D3D12_RESOURCE_STATE_RENDER_TARGET,nullptr,IID_PPV_ARGS(&resource)));
      ok(resource->SetName(L"0x0123456789abcdef"));
      std::array<D3D12_RESOURCE_BARRIER,2> barriers{};
      for(auto& barrier:barriers) {
        barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Transition.pResource=resource.Get();
        barrier.Transition.Subresource=D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
      }
      const auto sampled=D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE|D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE;
      barriers[0].Transition.StateBefore=D3D12_RESOURCE_STATE_RENDER_TARGET;
      barriers[0].Transition.StateAfter=sampled;
      barriers[1].Transition.StateBefore=sampled;
      barriers[1].Transition.StateAfter=D3D12_RESOURCE_STATE_RENDER_TARGET;
      const auto record=[&](unsigned pairs) {
        for(unsigned i=0;i<pairs;++i) commands->ResourceBarrier(2,barriers.data());
      };
      record(5000); // Exhaust bounded diagnostics before the measured window.
      ok(commands->Close());ok(allocator->Reset());ok(commands->Reset(allocator.Get(),nullptr));
      const auto begin=std::chrono::steady_clock::now();record(20000);
      const auto elapsed=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
      ok(commands->Close());ok(allocator->Reset());ok(commands->Reset(allocator.Get(),nullptr));
      std::cout << "workload=" << workload << " pairs=20000 barriers=40000 record_ms=" << elapsed << '\n';
    }
    ok(commands->Close());
    // No queue execution, Present, OpenXR session, image capture or game process.
    // Keep the module loaded until process exit so hook callbacks remain valid.
    std::cout << "PASS recorded_only=1 gpu_submissions=0\n";
    return 0;
  } catch(const std::exception& e) {std::cerr << e.what() << '\n';return 1;}
}
