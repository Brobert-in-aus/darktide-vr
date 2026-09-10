// Manual fixture for a locally supplied decoded writer; never loads the game.
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>
using Microsoft::WRL::ComPtr;
void ok(HRESULT hr) { if(FAILED(hr)) throw std::runtime_error("D3D12 operation failed"); }
struct Event {
  HANDLE value{CreateEventW(nullptr,FALSE,FALSE,nullptr)};
  ~Event() { if(value) CloseHandle(value); }
};
int wmain(int argc,wchar_t** argv) try {
  bool debug{},buffer_input{},deferred_trace{};
  std::filesystem::path shader_path,native_path;
  for(int i=1;i<argc;++i) {
    const std::wstring_view argument=argv[i];
    if(argument==L"--debug") debug=true;
    else if(argument==L"--buffer-input") buffer_input=true;
    else if(argument==L"--deferred-trace") deferred_trace=true;
    else if(argument==L"--native-dll" && i+1<argc) native_path=argv[++i];
    else if(!shader_path.empty() || argument.starts_with(L"--")) throw std::runtime_error("Unknown argument");
    else shader_path=argv[i];
  }
  if(shader_path.empty()) {
    std::cerr << "Usage: benchmark-cluster-list [--debug] [--buffer-input] [--native-dll PATH [--deferred-trace]] decoded-writer.dxbc\n";
    return 2;
  }
  if(deferred_trace && native_path.empty()) throw std::runtime_error("Deferred trace requires a native DLL and its trace flag");
  if(debug) { ComPtr<ID3D12Debug> layer; ok(D3D12GetDebugInterface(IID_PPV_ARGS(&layer))); layer->EnableDebugLayer(); }
  ComPtr<IDXGIFactory6> factory; ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
  ComPtr<IDXGIAdapter1> adapter;
  ok(factory->EnumAdapterByGpuPreference(0,DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,IID_PPV_ARGS(&adapter)));
  DXGI_ADAPTER_DESC1 adapter_desc{}; ok(adapter->GetDesc1(&adapter_desc));
  if(adapter_desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) throw std::runtime_error("Hardware required");
  std::wcout << L"adapter=" << adapter_desc.Description << L'\n';
  ComPtr<ID3D12Device> device; ok(D3D12CreateDevice(adapter.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)));
  int (*set_projection)(int){};
  if(!native_path.empty()) {
    if(!SetEnvironmentVariableW(L"DARKTIDEVR_TEST_TRANSPORTS",L"1")) throw std::runtime_error("Transport isolation failed");
    // Hooks remain installed until process exit; do not unload their module.
    const auto module=LoadLibraryW(std::filesystem::absolute(native_path).c_str());
    if(!module) throw std::runtime_error("Native fixture DLL unavailable");
    const auto enable=reinterpret_cast<int(*)()>(GetProcAddress(module,"dtvr_enable_cluster_trace"));
    const auto install=reinterpret_cast<int(*)(ID3D12Device*)>(GetProcAddress(module,"dtvr_install_for_device"));
    const auto deferred=reinterpret_cast<int(*)()>(GetProcAddress(module,"dtvr_install"));
    set_projection=reinterpret_cast<int(*)(int)>(GetProcAddress(module,"dtvr_set_projection_active"));
    if(!enable || !install || !deferred || !set_projection)
      throw std::runtime_error("Native fixture exports unavailable");
    const auto result=deferred_trace?deferred():(enable()==0?install(device.Get()):43);
    if(result!=0 || set_projection(1)!=0)
      throw std::runtime_error("Native trace installation failed");
  }
  std::ifstream input(shader_path,std::ios::binary);
  if(!input) throw std::runtime_error("Shader unavailable");
  std::vector<char> shader((std::istreambuf_iterator<char>(input)),{});
  if(shader.empty() || shader.size()>16*1024*1024) throw std::runtime_error("Invalid shader size");
  std::array<D3D12_DESCRIPTOR_RANGE,2> ranges{{
      {D3D12_DESCRIPTOR_RANGE_TYPE_SRV,1,0,0,0},
      {D3D12_DESCRIPTOR_RANGE_TYPE_UAV,4,0,0,0}}};
  std::array<D3D12_ROOT_PARAMETER,3> parameters{};
  for(unsigned i=0;i<2;++i) {
    parameters[i].ParameterType=D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
    parameters[i].DescriptorTable={1,&ranges[i]};
  }
  parameters[2].ParameterType=D3D12_ROOT_PARAMETER_TYPE_CBV;
  parameters[2].Descriptor={0,0};
  D3D12_ROOT_SIGNATURE_DESC root_desc{3,parameters.data(),0,nullptr,D3D12_ROOT_SIGNATURE_FLAG_NONE};
  ComPtr<ID3DBlob> root_blob,errors;
  ok(D3D12SerializeRootSignature(&root_desc,D3D_ROOT_SIGNATURE_VERSION_1,&root_blob,&errors));
  ComPtr<ID3D12RootSignature> root;
  ok(device->CreateRootSignature(0,root_blob->GetBufferPointer(),root_blob->GetBufferSize(),IID_PPV_ARGS(&root)));
  D3D12_COMPUTE_PIPELINE_STATE_DESC pso_desc{}; pso_desc.pRootSignature=root.Get();
  pso_desc.CS={shader.data(),shader.size()};
  ComPtr<ID3D12PipelineState> pipeline; ok(device->CreateComputePipelineState(&pso_desc,IID_PPV_ARGS(&pipeline)));
  auto buffer=[&](UINT64 bytes,D3D12_HEAP_TYPE type,D3D12_RESOURCE_STATES state,bool uav=false) {
    D3D12_RESOURCE_DESC desc{}; desc.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
    desc.Width=bytes; desc.Height=desc.DepthOrArraySize=desc.MipLevels=1;
    desc.SampleDesc.Count=1; desc.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    if(uav) desc.Flags=D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS;
    D3D12_HEAP_PROPERTIES heap{}; heap.Type=type; ComPtr<ID3D12Resource> resource;
    ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,state,nullptr,IID_PPV_ARGS(&resource)));
    return resource;
  };
  constexpr unsigned grid=30*17*64,capacity=1U<<22,poison=0xf00dbaad;
  const std::array<unsigned,4> words{grid,grid,1,capacity};
  std::array<ComPtr<ID3D12Resource>,4> buffers,readbacks;
  for(unsigned i=0;i<4;++i) {
    buffers[i]=buffer(UINT64(words[i])*4,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_COMMON,true);
    readbacks[i]=buffer(UINT64(words[i])*4,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
  }
  auto poison_upload=buffer(UINT64(capacity)*4,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
  void* mapped{}; D3D12_RANGE no_read{}; ok(poison_upload->Map(0,&no_read,&mapped));
  std::fill_n(static_cast<unsigned*>(mapped),capacity,poison); poison_upload->Unmap(0,nullptr);
  auto constants=buffer(256,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
  ok(constants->Map(0,&no_read,&mapped)); std::memset(mapped,0,256);
  const std::array<float,3> dimensions{30,17,64}; std::memcpy(mapped,dimensions.data(),sizeof(dimensions));
  constants->Unmap(0,nullptr);
  D3D12_RESOURCE_DESC texture_desc{}; texture_desc.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
  texture_desc.Width=30; texture_desc.Height=17; texture_desc.DepthOrArraySize=500;
  texture_desc.MipLevels=1; texture_desc.Format=DXGI_FORMAT_R32G32_FLOAT; texture_desc.SampleDesc.Count=1;
  D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
  ComPtr<ID3D12Resource> lights;
  if(buffer_input) lights=buffer(30*17*500*8,D3D12_HEAP_TYPE_DEFAULT,D3D12_RESOURCE_STATE_COMMON);
  else ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&texture_desc,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&lights)));
  std::array<D3D12_PLACED_SUBRESOURCE_FOOTPRINT,500> footprints{}; UINT64 texture_bytes{};
  if(buffer_input) texture_bytes=30*17*500*8;
  else device->GetCopyableFootprints(&texture_desc,0,500,0,footprints.data(),nullptr,nullptr,&texture_bytes);
  auto texture_upload=buffer(texture_bytes,D3D12_HEAP_TYPE_UPLOAD,D3D12_RESOURCE_STATE_GENERIC_READ);
  ok(texture_upload->Map(0,&no_read,&mapped)); std::memset(mapped,0,static_cast<std::size_t>(texture_bytes));
  texture_upload->Unmap(0,nullptr); // Bounds (0,0) span all 64 depth slices.
  D3D12_DESCRIPTOR_HEAP_DESC descriptors{}; descriptors.Type=D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
  descriptors.NumDescriptors=5; descriptors.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
  ComPtr<ID3D12DescriptorHeap> visible,cpu;
  ok(device->CreateDescriptorHeap(&descriptors,IID_PPV_ARGS(&visible)));
  descriptors.NumDescriptors=4; descriptors.Flags=D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
  ok(device->CreateDescriptorHeap(&descriptors,IID_PPV_ARGS(&cpu)));
  const auto stride=device->GetDescriptorHandleIncrementSize(descriptors.Type);
  auto cpu_handle=[&](unsigned index,bool shader_visible) {
    auto handle=(shader_visible?visible:cpu)->GetCPUDescriptorHandleForHeapStart();
    handle.ptr+=SIZE_T(index)*stride; return handle;
  };
  auto gpu_handle=[&](unsigned index) {
    auto handle=visible->GetGPUDescriptorHandleForHeapStart(); handle.ptr+=UINT64(index)*stride; return handle;
  };
  D3D12_SHADER_RESOURCE_VIEW_DESC srv{}; srv.Format=texture_desc.Format;
  srv.ViewDimension=D3D12_SRV_DIMENSION_TEXTURE2DARRAY; srv.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
  srv.Texture2DArray.MipLevels=1; srv.Texture2DArray.ArraySize=500;
  if(buffer_input) {
    srv={}; srv.Format=DXGI_FORMAT_R32_TYPELESS; srv.ViewDimension=D3D12_SRV_DIMENSION_BUFFER;
    srv.Shader4ComponentMapping=D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    srv.Buffer.NumElements=30*17*500*2; srv.Buffer.Flags=D3D12_BUFFER_SRV_FLAG_RAW;
  }
  device->CreateShaderResourceView(lights.Get(),&srv,cpu_handle(0,true));
  for(unsigned i=0;i<4;++i) {
    D3D12_UNORDERED_ACCESS_VIEW_DESC uav{}; uav.Format=DXGI_FORMAT_R32_TYPELESS;
    uav.ViewDimension=D3D12_UAV_DIMENSION_BUFFER; uav.Buffer.NumElements=words[i]; uav.Buffer.Flags=D3D12_BUFFER_UAV_FLAG_RAW;
    device->CreateUnorderedAccessView(buffers[i].Get(),nullptr,&uav,cpu_handle(i,false));
    device->CreateUnorderedAccessView(buffers[i].Get(),nullptr,&uav,cpu_handle(i+1,true));
  }
  ComPtr<ID3D12CommandQueue> queue; D3D12_COMMAND_QUEUE_DESC queue_desc{};
  ok(device->CreateCommandQueue(&queue_desc,IID_PPV_ARGS(&queue)));
  ComPtr<ID3D12CommandAllocator> allocator;
  ok(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)));
  ComPtr<ID3D12GraphicsCommandList> commands;
  ok(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),pipeline.Get(),IID_PPV_ARGS(&commands)));
  ComPtr<ID3D12Fence> fence; ok(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&fence)));
  Event event; if(!event.value) throw std::runtime_error("Event unavailable");
  UINT64 fence_value{};
  auto submit=[&] {
    ok(commands->Close()); ID3D12CommandList* lists[]{commands.Get()}; queue->ExecuteCommandLists(1,lists);
    ok(queue->Signal(fence.Get(),++fence_value)); ok(fence->SetEventOnCompletion(fence_value,event.value));
    if(WaitForSingleObject(event.value,30000)!=WAIT_OBJECT_0) throw std::runtime_error("GPU timeout");
  };
  auto transition=[&](ID3D12Resource* resource,D3D12_RESOURCE_STATES from,D3D12_RESOURCE_STATES to) {
    D3D12_RESOURCE_BARRIER barrier{}; barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition={resource,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,from,to}; commands->ResourceBarrier(1,&barrier);
  };
  auto uav_barrier=[&] { D3D12_RESOURCE_BARRIER barrier{}; barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_UAV; commands->ResourceBarrier(1,&barrier); };
  for(auto& resource:buffers)
    transition(resource.Get(),D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
  if(buffer_input) {
    transition(lights.Get(),D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_COPY_DEST);
    commands->CopyBufferRegion(lights.Get(),0,texture_upload.Get(),0,texture_bytes);
  } else for(unsigned i=0;i<500;++i) {
    D3D12_TEXTURE_COPY_LOCATION source{}; source.pResource=texture_upload.Get(); source.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    source.PlacedFootprint=footprints[i]; D3D12_TEXTURE_COPY_LOCATION target{}; target.pResource=lights.Get();
    target.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; target.SubresourceIndex=i;
    commands->CopyTextureRegion(&target,0,0,0,&source,nullptr);
  }
  transition(lights.Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE); submit();
  D3D12_QUERY_HEAP_DESC query_desc{D3D12_QUERY_HEAP_TYPE_TIMESTAMP,3,0};
  ComPtr<ID3D12QueryHeap> queries; ok(device->CreateQueryHeap(&query_desc,IID_PPV_ARGS(&queries)));
  auto timings=buffer(24,D3D12_HEAP_TYPE_READBACK,D3D12_RESOURCE_STATE_COPY_DEST);
  UINT64 frequency{}; ok(queue->GetTimestampFrequency(&frequency));
  for(unsigned light_count:{1U,128U,129U,500U}) for(unsigned iteration=0;iteration<4;++iteration) {
    const bool clear=(iteration%2)==0;
    ok(allocator->Reset()); ok(commands->Reset(allocator.Get(),pipeline.Get()));
    commands->SetPipelineState(pipeline.Get());
    ID3D12DescriptorHeap* heaps[]{visible.Get()}; commands->SetDescriptorHeaps(1,heaps);
    commands->SetComputeRootSignature(root.Get()); commands->SetComputeRootDescriptorTable(0,gpu_handle(0));
    commands->SetComputeRootDescriptorTable(1,gpu_handle(1)); commands->SetComputeRootConstantBufferView(2,constants->GetGPUVirtualAddress());
    transition(buffers[3].Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_DEST);
    commands->CopyBufferRegion(buffers[3].Get(),0,poison_upload.Get(),0,UINT64(capacity)*4);
    transition(buffers[3].Get(),D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    const UINT zero[4]{},ones[4]{0xffffffffU,0xffffffffU,0xffffffffU,0xffffffffU};
    for(unsigned i=0;i<3;++i) commands->ClearUnorderedAccessViewUint(gpu_handle(i+1),cpu_handle(i,false),buffers[i].Get(),i?zero:ones,0,nullptr);
    uav_barrier();
    if(set_projection && light_count==1 && iteration==0) {
      if(set_projection(0)!=0) throw std::runtime_error("Flat trace arm failed");
      commands->Dispatch(1,1,1);
      if(set_projection(1)!=0) throw std::runtime_error("World trace arm failed");
      uav_barrier();
      // Retire the arm dispatch and reset its heads/counters. Its short node
      // prefix is overwritten by the first measured full-grid dispatch.
      for(unsigned i=0;i<3;++i) commands->ClearUnorderedAccessViewUint(gpu_handle(i+1),cpu_handle(i,false),buffers[i].Get(),i?zero:ones,0,nullptr);
      uav_barrier();
    }
    commands->EndQuery(queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0);
    if(clear) commands->ClearUnorderedAccessViewUint(gpu_handle(4),cpu_handle(3,false),buffers[3].Get(),ones,0,nullptr);
    uav_barrier(); commands->EndQuery(queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,1);
    commands->Dispatch(4,3,light_count); uav_barrier(); commands->EndQuery(queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,2);
    commands->ResolveQueryData(queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0,3,timings.Get(),0);
    for(unsigned i=0;i<4;++i) {
      transition(buffers[i].Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);
      commands->CopyResource(readbacks[i].Get(),buffers[i].Get());
      transition(buffers[i].Get(),D3D12_RESOURCE_STATE_COPY_SOURCE,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    }
    submit();
    const unsigned allocated=grid*light_count,prefix=std::min(allocated,capacity);
    for(unsigned i=0;i<4;++i) {
      D3D12_RANGE range{0,SIZE_T(words[i])*4}; ok(readbacks[i]->Map(0,&range,&mapped));
      const auto* values=static_cast<const unsigned*>(mapped);
      bool valid=true;
      for(unsigned j=0;j<words[i];++j) {
        if(i==0) valid &= values[j]==capacity-1 || values[j]<prefix;
        else if(i==1) valid &= values[j]==light_count;
        else if(i==2) valid &= values[j]==allocated;
        else if(j<prefix) valid &= (values[j]>>22)<light_count &&
            ((values[j]&(capacity-1))==capacity-1 || (values[j]&(capacity-1))<prefix);
        else valid &= values[j]==(clear?0xffffffffU:poison);
      }
      D3D12_RANGE no_write{}; readbacks[i]->Unmap(0,&no_write);
      if(!valid) throw std::runtime_error("Initialization contract failed for buffer "+std::to_string(i));
    }
    D3D12_RANGE timing_range{0,24}; ok(timings->Map(0,&timing_range,&mapped));
    const auto* ticks=static_cast<const UINT64*>(mapped);
    const double clear_us=double(ticks[1]-ticks[0])*1e6/double(frequency);
    const double writer_us=double(ticks[2]-ticks[1])*1e6/double(frequency);
    D3D12_RANGE no_write{}; timings->Unmap(0,&no_write);
    std::cout << "lights=" << light_count << " allocated=" << allocated << " clear=" << clear
              << " iteration=" << iteration << " clear_us=" << clear_us << " writer_us=" << writer_us
              << " initialized_prefix=" << prefix << " contract=pass\n";
  }
  // Exercise float forwarding too, using a correctly typed R32_FLOAT view.
  // This is outside timed trials. Native mode exceeds the trace cap and checks
  // the last clear's exact bits, establishing continued forwarding after it.
  D3D12_UNORDERED_ACCESS_VIEW_DESC float_view{}; float_view.Format=DXGI_FORMAT_R32_FLOAT;
  float_view.ViewDimension=D3D12_UAV_DIMENSION_BUFFER; float_view.Buffer.NumElements=capacity;
  device->CreateUnorderedAccessView(buffers[3].Get(),nullptr,&float_view,cpu_handle(3,false));
  device->CreateUnorderedAccessView(buffers[3].Get(),nullptr,&float_view,cpu_handle(4,true));
  ok(allocator->Reset()); ok(commands->Reset(allocator.Get(),nullptr));
  ID3D12DescriptorHeap* final_heaps[]{visible.Get()}; commands->SetDescriptorHeaps(1,final_heaps);
  FLOAT final_value{};
  for(unsigned repeat=0;repeat<(native_path.empty()?1U:70U);++repeat) {
    final_value=1.5F+static_cast<FLOAT>(repeat);
    const FLOAT float_values[4]{final_value,0,0,0};
    commands->ClearUnorderedAccessViewFloat(gpu_handle(4),cpu_handle(3,false),buffers[3].Get(),float_values,0,nullptr);
    uav_barrier();
  }
  transition(buffers[3].Get(),D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE);
  commands->CopyResource(readbacks[3].Get(),buffers[3].Get()); submit();
  D3D12_RANGE float_range{0,SIZE_T(capacity)*4}; ok(readbacks[3]->Map(0,&float_range,&mapped));
  const auto* float_bits=static_cast<const UINT*>(mapped);
  UINT expected_bits{}; std::memcpy(&expected_bits,&final_value,sizeof(expected_bits));
  const bool float_valid=std::all_of(float_bits,float_bits+capacity,[&](UINT value) { return value==expected_bits; });
  D3D12_RANGE no_write{}; readbacks[3]->Unmap(0,&no_write);
  if(!float_valid) throw std::runtime_error("Float clear forwarding failed");
  std::cout << "float_clear=pass native_hooks=" << !native_path.empty() << '\n';
  if(debug) {
    ComPtr<ID3D12InfoQueue> info; ok(device.As(&info));
    for(UINT64 i=0;i<info->GetNumStoredMessagesAllowedByRetrievalFilter();++i) {
      SIZE_T size{}; ok(info->GetMessage(i,nullptr,&size)); std::vector<char> bytes(size);
      auto* message=reinterpret_cast<D3D12_MESSAGE*>(bytes.data()); ok(info->GetMessage(i,message,&size));
      if(message->Severity<=D3D12_MESSAGE_SEVERITY_WARNING) {
        std::cerr << message->pDescription << '\n'; throw std::runtime_error("Debug-layer diagnostic");
      }
    }
  }
  std::cout << "result=pass scope=isolated_writer_not_game\n";
  return 0;
} catch(const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
