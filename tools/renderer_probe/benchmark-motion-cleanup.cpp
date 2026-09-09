// Manual isolated GPU comparison: no game, headset or shader substitution.
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <array>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
using Microsoft::WRL::ComPtr;
void ok(HRESULT hr) { if (FAILED(hr)) throw std::runtime_error("D3D12 operation failed"); }
struct Event { HANDLE value{CreateEventW(nullptr, FALSE, FALSE, nullptr)}; ~Event() { if(value) CloseHandle(value); } };
bool half_nan(unsigned value) { return (value & 0x7c00U) == 0x7c00U && (value & 0x3ffU); }
int wmain(int argc, wchar_t** argv) try {
  const bool debug = argc == 6 && std::wstring_view(argv[1]) == L"--debug";
  if ((!debug && argc != 5) || (argc == 6 && !debug)) {
    std::cerr << "Usage: benchmark-motion-cleanup [--debug] original.dxbc control32.dxil group8.dxil group4.dxil\n";
    return 2;
  }
  if(debug) { ComPtr<ID3D12Debug> layer; ok(D3D12GetDebugInterface(IID_PPV_ARGS(&layer))); layer->EnableDebugLayer(); }
  ComPtr<IDXGIFactory6> factory; ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
  ComPtr<IDXGIAdapter1> adapter;
  ok(factory->EnumAdapterByGpuPreference(0, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE, IID_PPV_ARGS(&adapter)));
  DXGI_ADAPTER_DESC1 desc{}; ok(adapter->GetDesc1(&desc));
  if(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) throw std::runtime_error("hardware adapter required");
  ComPtr<ID3D12Device> device; ok(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)));
  std::wcout << L"adapter=" << desc.Description << L"\n";
  D3D12_FEATURE_DATA_FORMAT_SUPPORT support{DXGI_FORMAT_R16G16_FLOAT};
  ok(device->CheckFeatureSupport(D3D12_FEATURE_FORMAT_SUPPORT, &support, sizeof(support)));
  if(!(support.Support2 & D3D12_FORMAT_SUPPORT2_UAV_TYPED_LOAD)) throw std::runtime_error("typed UAV load unavailable");
  D3D12_DESCRIPTOR_RANGE range{D3D12_DESCRIPTOR_RANGE_TYPE_UAV,1,0,0,0};
  D3D12_ROOT_PARAMETER parameter{}; parameter.ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
  parameter.DescriptorTable={1,&range}; parameter.ShaderVisibility=D3D12_SHADER_VISIBILITY_ALL;
  D3D12_ROOT_SIGNATURE_DESC root_desc{1,&parameter,0,nullptr,D3D12_ROOT_SIGNATURE_FLAG_NONE};
  ComPtr<ID3DBlob> root_blob, errors; ok(D3D12SerializeRootSignature(&root_desc,D3D_ROOT_SIGNATURE_VERSION_1,&root_blob,&errors));
  ComPtr<ID3D12RootSignature> root;
  ok(device->CreateRootSignature(0,root_blob->GetBufferPointer(),root_blob->GetBufferSize(),IID_PPV_ARGS(&root)));
  std::array<ComPtr<ID3D12PipelineState>,4> pipelines;
  for(unsigned i=0;i<4;++i) {
    std::ifstream input(std::filesystem::path(argv[i+1+(debug?1:0)]),std::ios::binary);
    if(!input) throw std::runtime_error("shader file unavailable");
    std::vector<char> bytes((std::istreambuf_iterator<char>(input)),{});
    D3D12_COMPUTE_PIPELINE_STATE_DESC pso{}; pso.pRootSignature=root.Get(); pso.CS={bytes.data(),bytes.size()};
    ok(device->CreateComputePipelineState(&pso,IID_PPV_ARGS(&pipelines[i])));
  }
  ComPtr<ID3D12CommandQueue> queue; D3D12_COMMAND_QUEUE_DESC queue_desc{};
  ok(device->CreateCommandQueue(&queue_desc,IID_PPV_ARGS(&queue)));
  ComPtr<ID3D12CommandAllocator> allocator; ok(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)));
  ComPtr<ID3D12GraphicsCommandList> commands;
  ok(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),nullptr,IID_PPV_ARGS(&commands))); ok(commands->Close());
  constexpr unsigned width=1664,height=1792;
  D3D12_RESOURCE_DESC texture_desc{}; texture_desc.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
  texture_desc.Width=width; texture_desc.Height=height; texture_desc.DepthOrArraySize=texture_desc.MipLevels=1;
  texture_desc.SampleDesc.Count=1; texture_desc.Format=DXGI_FORMAT_R16G16_TYPELESS;
  texture_desc.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET|D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
  D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
  ComPtr<ID3D12Resource> texture;
  ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&texture_desc,D3D12_RESOURCE_STATE_COPY_SOURCE,nullptr,IID_PPV_ARGS(&texture)));
  D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{}; UINT64 bytes{};
  device->GetCopyableFootprints(&texture_desc,0,1,0,&footprint,nullptr,nullptr,&bytes);
  auto buffer=[&](UINT64 size,D3D12_HEAP_TYPE type,D3D12_RESOURCE_STATES state) {
    D3D12_RESOURCE_DESC d{}; d.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER; d.Width=size;
    d.Height=d.DepthOrArraySize=d.MipLevels=1; d.SampleDesc.Count=1; d.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    D3D12_HEAP_PROPERTIES h{}; h.Type=type; ComPtr<ID3D12Resource> resource;
    ok(device->CreateCommittedResource(&h,D3D12_HEAP_FLAG_NONE,&d,state,nullptr,IID_PPV_ARGS(&resource))); return resource;
  };
  auto upload=buffer(bytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
  auto pixels=buffer(bytes,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
  auto timestamps=buffer(16,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
  ComPtr<ID3D12DescriptorHeap> descriptors;
  D3D12_DESCRIPTOR_HEAP_DESC hd{D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV,1,D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE,0};
  ok(device->CreateDescriptorHeap(&hd,IID_PPV_ARGS(&descriptors)));
  D3D12_UNORDERED_ACCESS_VIEW_DESC uav{}; uav.Format=DXGI_FORMAT_R16G16_FLOAT; uav.ViewDimension=D3D12_UAV_DIMENSION_TEXTURE2D;
  device->CreateUnorderedAccessView(texture.Get(),nullptr,&uav,descriptors->GetCPUDescriptorHandleForHeapStart());
  ComPtr<ID3D12QueryHeap> queries; D3D12_QUERY_HEAP_DESC qd{D3D12_QUERY_HEAP_TYPE_TIMESTAMP,2,0};
  ok(device->CreateQueryHeap(&qd,IID_PPV_ARGS(&queries)));
  ComPtr<ID3D12Fence> fence; ok(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)));
  Event event; if(!event.value) throw std::runtime_error("event unavailable");
  UINT64 ticket{},frequency{}; ok(queue->GetTimestampFrequency(&frequency)); if(!frequency) throw std::runtime_error("timestamp frequency unavailable");
  auto transition=[&](D3D12_RESOURCE_STATES before,D3D12_RESOURCE_STATES after) {
    D3D12_RESOURCE_BARRIER b{}; b.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    b.Transition={texture.Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,before,after}; commands->ResourceBarrier(1,&b);
  };
  const unsigned group_y[]{32,32,8,4};
  std::cout << "scope=isolated_cleanup width=" << width << " height=" << height << " debug=" << debug << '\n';
  for(unsigned mixed=0;mixed<2;++mixed) {
    std::vector<std::uint32_t> expected(width*height);
    void* mapped{}; D3D12_RANGE none{0,0}; ok(upload->Map(0,&none,&mapped));
    for(unsigned y=0;y<height;++y) for(unsigned x=0;x<width;++x) {
      const unsigned i=y*width+x;
      unsigned lo=0x3000U+(i%1024),hi=0xb400U+(i%1024);
      if(mixed && i%257==0) lo=0x7e01U;
      if(mixed && i%509==0) hi=0xfe01U;
      if(i%997==0) hi=0x7c00U; // Infinity is intentionally preserved, not NaN.
      const std::uint32_t value=lo|(hi<<16);
      std::memcpy(static_cast<char*>(mapped)+y*footprint.Footprint.RowPitch+x*4,&value,4);
      expected[i]=half_nan(lo)||half_nan(hi)?0:value;
    }
    upload->Unmap(0,nullptr);
    for(unsigned round=0;round<(debug?1U:22U);++round) for(unsigned order=0;order<4;++order) {
      const unsigned mode=(round+order)%4;
      ok(allocator->Reset()); ok(commands->Reset(allocator.Get(),pipelines[mode].Get()));
      transition(D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_COPY_DEST);
      D3D12_TEXTURE_COPY_LOCATION from{},to{};
      from.pResource=upload.Get(); from.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; from.PlacedFootprint=footprint;
      to.pResource=texture.Get(); to.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
      commands->CopyTextureRegion(&to,0,0,0,&from,nullptr);
      transition(D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
      ID3D12DescriptorHeap* heaps[]{descriptors.Get()}; commands->SetDescriptorHeaps(1,heaps);
      commands->SetComputeRootSignature(root.Get()); commands->SetComputeRootDescriptorTable(0,descriptors->GetGPUDescriptorHandleForHeapStart());
      commands->EndQuery(queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0);
      commands->Dispatch(width/32,height/group_y[mode],1);
      commands->EndQuery(queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,1);
      transition(D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);
      if(round==0) {
        from.pResource=texture.Get(); from.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; from.SubresourceIndex=0;
        to.pResource=pixels.Get(); to.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; to.PlacedFootprint=footprint;
        commands->CopyTextureRegion(&to,0,0,0,&from,nullptr);
      }
      commands->ResolveQueryData(queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0,2,timestamps.Get(),0);
      ok(commands->Close()); ID3D12CommandList* lists[]{commands.Get()}; queue->ExecuteCommandLists(1,lists);
      ok(queue->Signal(fence.Get(),++ticket)); ok(fence->SetEventOnCompletion(ticket,event.value));
      if(WaitForSingleObject(event.value,10000)!=WAIT_OBJECT_0 || fence->GetCompletedValue()==UINT64_MAX) throw std::runtime_error("GPU completion failed");
      D3D12_RANGE time_range{0,16}; ok(timestamps->Map(0,&time_range,&mapped));
      const auto* time=static_cast<UINT64*>(mapped); if(time[1]<time[0]) throw std::runtime_error("invalid timestamps");
      const double us=static_cast<double>(time[1]-time[0])*1e6/static_cast<double>(frequency); timestamps->Unmap(0,&none);
      if(round==0) {
        D3D12_RANGE pixel_range{0,static_cast<SIZE_T>(bytes)}; ok(pixels->Map(0,&pixel_range,&mapped));
        for(unsigned y=0;y<height;++y) for(unsigned x=0;x<width;++x) {
          std::uint32_t actual{}; std::memcpy(&actual,static_cast<char*>(mapped)+y*footprint.Footprint.RowPitch+x*4,4);
          if(actual!=expected[y*width+x]) throw std::runtime_error("pixel mismatch");
        }
        pixels->Unmap(0,&none);
      }
      std::cout << "mixed=" << mixed << " round=" << round << " order=" << order << " mode=" << mode
                << " group_y=" << group_y[mode] << " warmup=" << (round<2) << " gpu_us=" << us << " checked=" << (round==0) << '\n';
    }
  }
  if(debug) {
    ComPtr<ID3D12InfoQueue> info; ok(device.As(&info));
    for(UINT64 i=0;i<info->GetNumStoredMessagesAllowedByRetrievalFilter();++i) {
      SIZE_T length{}; ok(info->GetMessage(i,nullptr,&length));
      std::vector<char> storage(length); auto* message=reinterpret_cast<D3D12_MESSAGE*>(storage.data());
      ok(info->GetMessage(i,message,&length));
      if(message->Severity<=D3D12_MESSAGE_SEVERITY_WARNING) {
        std::cerr << message->pDescription << '\n'; throw std::runtime_error("D3D12 debug validation failed");
      }
    }
    std::cout << "debug_validation=pass\n";
  }
  return 0;
} catch(const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
