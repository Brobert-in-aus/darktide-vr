// Optional GPU source-integration fixture. Original game bytecode stays local.
#include <d3d12.h>
#include <d3d12sdklayers.h>
#include <d3d12shader.h>
#include <dxcapi.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <array>
#include <algorithm>
#include <bit>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
using V4 = std::array<float, 4>;
void require(bool good, const char* message) { if (!good) throw std::runtime_error(message); }
void hr(HRESULT code, const char* operation) {
  if (FAILED(code)) { std::ostringstream s; s << operation << " HRESULT=0x" << std::hex << code; throw std::runtime_error(s.str()); }
}
std::vector<char> read(const std::filesystem::path& path) {
  std::ifstream file(path, std::ios::binary);
  std::vector<char> bytes((std::istreambuf_iterator<char>(file)), {});
  require(!bytes.empty() && bytes.size() < 64 * 1024 * 1024, "Invalid shader file"); return bytes;
}
struct Parameter { std::string name; UINT index{}; BYTE mask{}; D3D_NAME system{}; };
struct Shader {
  std::vector<char> bytes;
  ComPtr<ID3D12ShaderReflection> reflection;
  std::vector<Parameter> inputs, outputs;
  Shader(const std::filesystem::path& path, DxcCreateInstanceProc create) : bytes(read(path)) {
    ComPtr<IDxcLibrary> library; ComPtr<IDxcBlobEncoding> blob; ComPtr<IDxcContainerReflection> container;
    hr(create(CLSID_DxcLibrary, IID_PPV_ARGS(&library)), "DXC library");
    hr(create(CLSID_DxcContainerReflection, IID_PPV_ARGS(&container)), "DXC container");
    hr(library->CreateBlobWithEncodingFromPinned(bytes.data(), static_cast<UINT32>(bytes.size()), 0, &blob), "DXC blob");
    hr(container->Load(blob.Get()), "DXC load");
    UINT32 part{}; hr(container->FindFirstPartKind(DXC_PART_DXIL, &part), "DXIL part");
    hr(container->GetPartReflection(part, IID_PPV_ARGS(&reflection)), "DXIL reflection");
    D3D12_SHADER_DESC desc{}; hr(reflection->GetDesc(&desc), "Shader descriptor");
    for (UINT i = 0; i < desc.InputParameters; ++i) {
      D3D12_SIGNATURE_PARAMETER_DESC p{}; hr(reflection->GetInputParameterDesc(i, &p), "Input signature");
      if (p.SystemValueType == D3D_NAME_INSTANCE_ID) continue;
      require(p.ComponentType == D3D_REGISTER_COMPONENT_FLOAT32, "Fixture requires floating input");
      inputs.push_back({p.SemanticName, p.SemanticIndex, p.Mask, p.SystemValueType});
    }
    for (UINT i = 0; i < desc.OutputParameters; ++i) {
      D3D12_SIGNATURE_PARAMETER_DESC p{}; hr(reflection->GetOutputParameterDesc(i, &p), "Output signature");
      require(p.ComponentType == D3D_REGISTER_COMPONENT_FLOAT32, "Fixture requires floating output");
      outputs.push_back({p.SemanticName, p.SemanticIndex, p.Mask, p.SystemValueType});
    }
  }
};

struct Fixture {
  ComPtr<ID3D12Device> device; ComPtr<ID3D12InfoQueue> messages;
  ComPtr<ID3D12CommandQueue> queue; ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> commands; ComPtr<ID3D12Fence> fence;
  ComPtr<ID3D12RootSignature> root; ComPtr<ID3D12DescriptorHeap> heap;
  ComPtr<ID3D12Resource> volume, cube, atlas, vertices;
  std::array<ComPtr<ID3D12Resource>, 4> constants;
  std::vector<ComPtr<ID3D12Resource>> retained;
  UINT64 fence_value{}; UINT vertex_stride{}, output_stride{};
  std::vector<D3D12_INPUT_ELEMENT_DESC> layout;
  std::vector<D3D12_SO_DECLARATION_ENTRY> output;

  ComPtr<ID3D12Resource> buffer(UINT64 bytes, D3D12_HEAP_TYPE type,
                              D3D12_RESOURCE_STATES state, const void* data = nullptr) {
    D3D12_HEAP_PROPERTIES hp{}; hp.Type = type;
    D3D12_RESOURCE_DESC d{}; d.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    d.Width = bytes; d.Height = 1; d.DepthOrArraySize = 1; d.MipLevels = 1;
    d.SampleDesc.Count = 1; d.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    ComPtr<ID3D12Resource> result;
    hr(device->CreateCommittedResource(&hp, D3D12_HEAP_FLAG_NONE, &d, state, nullptr, IID_PPV_ARGS(&result)), "Buffer");
    if (data) write(result.Get(), data, static_cast<std::size_t>(bytes));
    return result;
  }
  void write(ID3D12Resource* target, const void* data, std::size_t bytes) {
    void* mapped{}; D3D12_RANGE no_read{0, 0}; hr(target->Map(0, &no_read, &mapped), "Upload map");
    std::memcpy(mapped, data, bytes); D3D12_RANGE written{0, bytes}; target->Unmap(0, &written);
  }
  void transition(ID3D12Resource* target, D3D12_RESOURCE_STATES before, D3D12_RESOURCE_STATES after) {
    D3D12_RESOURCE_BARRIER b{}; b.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    b.Transition = {target, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES, before, after};
    commands->ResourceBarrier(1, &b);
  }
  void submit() {
    hr(commands->Close(), "Close"); ID3D12CommandList* lists[]{commands.Get()}; queue->ExecuteCommandLists(1, lists);
    hr(queue->Signal(fence.Get(), ++fence_value), "Fence signal");
    HANDLE event = CreateEventW(nullptr, FALSE, FALSE, nullptr); require(event != nullptr, "Fence event");
    hr(fence->SetEventOnCompletion(fence_value, event), "Fence event completion");
    const auto waited = WaitForSingleObject(event, 10000); CloseHandle(event);
    require(waited == WAIT_OBJECT_0, "GPU timeout");
    hr(allocator->Reset(), "Allocator reset"); hr(commands->Reset(allocator.Get(), nullptr), "List reset");
  }
  ComPtr<ID3D12Resource> texture(bool is_cube, UINT descriptor_index) {
    D3D12_RESOURCE_DESC d{}; d.Dimension = is_cube ? D3D12_RESOURCE_DIMENSION_TEXTURE2D : D3D12_RESOURCE_DIMENSION_TEXTURE3D;
    d.Width = 2; d.Height = 2; d.DepthOrArraySize = is_cube ? 6 : 2; d.MipLevels = 1;
    d.Format = DXGI_FORMAT_R32G32B32A32_FLOAT; d.SampleDesc.Count = 1;
    D3D12_HEAP_PROPERTIES hp{}; hp.Type = D3D12_HEAP_TYPE_DEFAULT;
    ComPtr<ID3D12Resource> result;
    hr(device->CreateCommittedResource(&hp, D3D12_HEAP_FLAG_NONE, &d, D3D12_RESOURCE_STATE_COPY_DEST,
                                       nullptr, IID_PPV_ARGS(&result)), "Texture");
    const UINT count = is_cube ? 6 : 1;
    std::array<D3D12_PLACED_SUBRESOURCE_FOOTPRINT, 6> footprints{};
    UINT64 bytes{}; device->GetCopyableFootprints(&d, 0, count, 0, footprints.data(), nullptr, nullptr, &bytes);
    std::vector<std::uint8_t> data(static_cast<std::size_t>(bytes));
    for (UINT part = 0; part < count; ++part) {
      const auto& f = footprints[part];
      for (UINT z = 0; z < f.Footprint.Depth; ++z) for (UINT y = 0; y < 2; ++y) for (UINT x = 0; x < 2; ++x) {
        V4 color{.05f * (part + 1), .1f + x * .05f, .15f + y * .05f, .3f + z * .05f};
        const auto offset = f.Offset + (z * 2 + y) * f.Footprint.RowPitch + x * 16;
        std::memcpy(data.data() + offset, color.data(), 16);
      }
    }
    auto upload = buffer(bytes, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, data.data());
    for (UINT part = 0; part < count; ++part) {
      D3D12_TEXTURE_COPY_LOCATION src{}, dst{};
      src.pResource = upload.Get(); src.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; src.PlacedFootprint = footprints[part];
      dst.pResource = result.Get(); dst.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX; dst.SubresourceIndex = part;
      commands->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);
    }
    retained.push_back(upload); transition(result.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    D3D12_SHADER_RESOURCE_VIEW_DESC srv{}; srv.Format = d.Format;
    srv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    if (is_cube) { srv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURECUBE; srv.TextureCube.MipLevels = 1; }
    else { srv.ViewDimension = D3D12_SRV_DIMENSION_TEXTURE3D; srv.Texture3D.MipLevels = 1; }
    auto handle = heap->GetCPUDescriptorHandleForHeapStart();
    handle.ptr += descriptor_index * device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
    device->CreateShaderResourceView(result.Get(), &srv, handle); return result;
  }
  Fixture(const Shader& shader, bool hardware) {
    ComPtr<ID3D12Debug> debug; hr(D3D12GetDebugInterface(IID_PPV_ARGS(&debug)), "Debug interface"); debug->EnableDebugLayer();
    ComPtr<IDXGIFactory6> factory; ComPtr<IDXGIAdapter1> adapter;
    hr(CreateDXGIFactory1(IID_PPV_ARGS(&factory)), "DXGI");
    if (hardware) hr(factory->EnumAdapterByGpuPreference(0, DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,
                                                       IID_PPV_ARGS(&adapter)), "Hardware adapter");
    else hr(factory->EnumWarpAdapter(IID_PPV_ARGS(&adapter)), "WARP");
    DXGI_ADAPTER_DESC1 adapter_desc{}; hr(adapter->GetDesc1(&adapter_desc), "Adapter identity");
    require(!hardware || !(adapter_desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE), "Hardware mode selected a software adapter");
    std::cout << "adapter_vendor=" << adapter_desc.VendorId << " adapter_device=" << adapter_desc.DeviceId
              << " software=" << ((adapter_desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) ? 1 : 0) << '\n';
    hr(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)), "Device");
    hr(device.As(&messages), "Info queue");
    D3D12_COMMAND_QUEUE_DESC q{}; hr(device->CreateCommandQueue(&q, IID_PPV_ARGS(&queue)), "Queue");
    hr(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT, IID_PPV_ARGS(&allocator)), "Allocator");
    hr(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT, allocator.Get(), nullptr, IID_PPV_ARGS(&commands)), "List");
    hr(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)), "Fence");
    std::array<D3D12_ROOT_PARAMETER, 5> parameters{};
    for (UINT i = 0; i < 4; ++i) { parameters[i].ParameterType = D3D12_ROOT_PARAMETER_TYPE_CBV;
      parameters[i].Descriptor.ShaderRegister = i; parameters[i].ShaderVisibility = D3D12_SHADER_VISIBILITY_VERTEX;
      constants[i] = buffer(2048, D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ); }
    D3D12_DESCRIPTOR_RANGE range{}; range.RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV; range.NumDescriptors = 3;
    parameters[4].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
    parameters[4].DescriptorTable = {1, &range}; parameters[4].ShaderVisibility = D3D12_SHADER_VISIBILITY_VERTEX;
    std::array<D3D12_STATIC_SAMPLER_DESC, 2> samplers{};
    for (UINT i = 0; i < 2; ++i) { auto& s = samplers[i]; s.Filter = D3D12_FILTER_MIN_MAG_MIP_LINEAR;
      s.AddressU = s.AddressV = s.AddressW = D3D12_TEXTURE_ADDRESS_MODE_CLAMP; s.MaxAnisotropy = 1;
      s.ComparisonFunc = D3D12_COMPARISON_FUNC_ALWAYS; s.MaxLOD = std::numeric_limits<float>::max();
      s.ShaderRegister = i; s.ShaderVisibility = D3D12_SHADER_VISIBILITY_VERTEX; }
    D3D12_ROOT_SIGNATURE_DESC rs{}; rs.NumParameters = 5; rs.pParameters = parameters.data();
    rs.NumStaticSamplers = 2; rs.pStaticSamplers = samplers.data();
    rs.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT | D3D12_ROOT_SIGNATURE_FLAG_ALLOW_STREAM_OUTPUT;
    ComPtr<ID3DBlob> serialized, error; hr(D3D12SerializeRootSignature(&rs, D3D_ROOT_SIGNATURE_VERSION_1, &serialized, &error), "Root serialize");
    hr(device->CreateRootSignature(0, serialized->GetBufferPointer(), serialized->GetBufferSize(), IID_PPV_ARGS(&root)), "Root");
    D3D12_DESCRIPTOR_HEAP_DESC hd{}; hd.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
    hd.NumDescriptors = 3; hd.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
    hr(device->CreateDescriptorHeap(&hd, IID_PPV_ARGS(&heap)), "SRV heap");
    volume = texture(false, 0); cube = texture(true, 1);
    std::array<std::uint32_t, 32> ids{};
    const std::array<std::uint32_t, 8> seeds{0, 1, 0x01000002, 0x02000101, 0x03000011, 0x04000077, 0x05000000, 0xffffffff};
    for (std::size_t i = 0; i < ids.size(); ++i) ids[i] = seeds[i % seeds.size()];
    atlas = buffer(sizeof(ids), D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, ids.data());
    D3D12_SHADER_RESOURCE_VIEW_DESC srv{}; srv.ViewDimension = D3D12_SRV_DIMENSION_BUFFER;
    srv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING; srv.Buffer.NumElements = 32; srv.Buffer.StructureByteStride = 4;
    auto handle = heap->GetCPUDescriptorHandleForHeapStart();
    handle.ptr += 2 * device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
    device->CreateShaderResourceView(atlas.Get(), &srv, handle);
    for (const auto& p : shader.inputs) {
      layout.push_back({p.name.c_str(), p.index, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, vertex_stride, D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA, 0});
      vertex_stride += 16;
    }
    std::vector<V4> data(shader.inputs.size() * 4);
    for (UINT vertex = 0; vertex < 4; ++vertex) for (std::size_t i = 0; i < shader.inputs.size(); ++i) {
      const auto& p = shader.inputs[i]; V4 v{.2f,.3f,.4f,.8f};
      if (p.name == "POSITION" && p.index == 0) v = {1.f, 8.f, 2.f, 1.f};
      if (p.name == "POSITION" && p.index == 1) v = {(vertex & 1) ? 1.f : -1.f, (vertex & 2) ? 1.f : -1.f, 0, 0};
      if (p.name == "TEXCOORD" && p.index == 7) v = {2.f, 3.f, 0, 0};
      if (p.name == "TEXCOORD" && p.index == 1) v = {.47f,0,0,0};
      data[vertex * shader.inputs.size() + i] = v;
    }
    vertices = buffer(data.size() * sizeof(V4), D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, data.data());
    for (const auto& p : shader.outputs) { const auto count = static_cast<BYTE>(std::popcount(static_cast<unsigned>(p.mask)));
      output.push_back({0, p.name.c_str(), p.index, 0, count, 0}); output_stride += count * 4; }
    submit(); retained.clear();
  }
  ComPtr<ID3D12PipelineState> pipeline(const Shader& shader) {
    D3D12_GRAPHICS_PIPELINE_STATE_DESC p{}; p.pRootSignature = root.Get(); p.VS = {shader.bytes.data(), shader.bytes.size()};
    p.InputLayout = {layout.data(), static_cast<UINT>(layout.size())};
    p.StreamOutput = {output.data(), static_cast<UINT>(output.size()), &output_stride, 1, D3D12_SO_NO_RASTERIZED_STREAM};
    p.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_POINT; p.SampleDesc.Count = 1; p.SampleMask = UINT_MAX;
    p.RasterizerState.FillMode = D3D12_FILL_MODE_SOLID; p.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
    p.BlendState.RenderTarget[0].RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
    ComPtr<ID3D12PipelineState> result; hr(device->CreateGraphicsPipelineState(&p, IID_PPV_ARGS(&result)), "Stream-output PSO"); return result;
  }
  void inputs(float yaw, float pitch, float roll, unsigned fog) {
    std::array<V4, 128> global{}, lighting{}, billboard{}, material{};
    global.fill({.1f,.2f,.3f,.4f}); lighting.fill({.2f,.3f,.4f,.5f}); material.fill({.3f,.4f,.5f,.6f});
    global[10] = {1,0,0,0}; global[11] = {0,1,0,0}; global[12] = {0,0,1,0};
    global[99][2] = .2f; global[106][0] = .1f;
    lighting[16][0] = fog ? 1.f : 0.f; lighting[19][2] = fog >= 2 ? 1.f : 0.f;
    lighting[20] = {.1f, fog == 3 ? 3.f : 20.f, .3f, .02f};
    lighting[17] = {.05f,4,8,0}; lighting[18] = {.01f,2,10,0};
    const V4 right{std::cos(yaw),std::sin(yaw),0,0};
    const V4 forward{-right[1]*std::cos(pitch),right[0]*std::cos(pitch),std::sin(pitch),0};
    const V4 up{right[1]*std::sin(pitch),-right[0]*std::sin(pitch),std::cos(pitch),0};
    for (UINT i = 0; i < 3; ++i) { billboard[0][i] = right[i]*std::cos(roll)+up[i]*std::sin(roll);
      billboard[1][i] = forward[i]; billboard[2][i] = up[i]*std::cos(roll)-right[i]*std::sin(roll); }
    for (UINT i = 0; i < 4; ++i) billboard[4+i][i] = 1;
    write(constants[0].Get(), global.data(), sizeof(global)); write(constants[1].Get(), lighting.data(), sizeof(lighting));
    write(constants[2].Get(), billboard.data(), sizeof(billboard)); write(constants[3].Get(), material.data(), sizeof(material));
  }
  std::vector<float> run(ID3D12PipelineState* pipeline, UINT first_instance) {
    const UINT64 output_bytes = output_stride * 32ULL;
    std::vector<std::uint8_t> zeros(static_cast<std::size_t>(output_bytes + 8));
    auto zero = buffer(zeros.size(), D3D12_HEAP_TYPE_UPLOAD, D3D12_RESOURCE_STATE_GENERIC_READ, zeros.data());
    auto target = buffer(zeros.size(), D3D12_HEAP_TYPE_DEFAULT, D3D12_RESOURCE_STATE_COPY_DEST);
    auto readback = buffer(zeros.size(), D3D12_HEAP_TYPE_READBACK, D3D12_RESOURCE_STATE_COPY_DEST);
    commands->CopyResource(target.Get(), zero.Get()); transition(target.Get(), D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_STREAM_OUT);
    commands->SetPipelineState(pipeline); commands->SetGraphicsRootSignature(root.Get());
    ID3D12DescriptorHeap* heaps[]{heap.Get()}; commands->SetDescriptorHeaps(1, heaps);
    for (UINT i = 0; i < 4; ++i) commands->SetGraphicsRootConstantBufferView(i, constants[i]->GetGPUVirtualAddress());
    commands->SetGraphicsRootDescriptorTable(4, heap->GetGPUDescriptorHandleForHeapStart());
    D3D12_VERTEX_BUFFER_VIEW vb{vertices->GetGPUVirtualAddress(), vertex_stride * 4, vertex_stride};
    commands->IASetVertexBuffers(0, 1, &vb); commands->IASetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_POINTLIST);
    D3D12_STREAM_OUTPUT_BUFFER_VIEW so{target->GetGPUVirtualAddress(), output_bytes, target->GetGPUVirtualAddress()+output_bytes};
    commands->SOSetTargets(0, 1, &so); commands->DrawInstanced(4, 8, 0, first_instance); commands->SOSetTargets(0, 0, nullptr);
    transition(target.Get(), D3D12_RESOURCE_STATE_STREAM_OUT, D3D12_RESOURCE_STATE_COPY_SOURCE);
    commands->CopyResource(readback.Get(), target.Get()); submit();
    void* mapped{}; D3D12_RANGE range{0, zeros.size()}; hr(readback->Map(0, &range, &mapped), "Read SO");
    UINT64 written{}; std::memcpy(&written, static_cast<const char*>(mapped)+output_bytes, 8);
    std::vector<float> values(static_cast<std::size_t>(output_bytes/4)); std::memcpy(values.data(), mapped, static_cast<std::size_t>(output_bytes));
    D3D12_RANGE no_write{0,0}; readback->Unmap(0, &no_write); require(written == output_bytes, "Stream output did not write every expected vertex");
    return values;
  }
  void validate() {
    for (UINT64 i = 0; i < messages->GetNumStoredMessages(); ++i) {
      SIZE_T bytes{}; hr(messages->GetMessage(i, nullptr, &bytes), "Message size"); std::vector<char> storage(bytes);
      auto* m = reinterpret_cast<D3D12_MESSAGE*>(storage.data()); hr(messages->GetMessage(i, m, &bytes), "Message");
      if (m->Severity <= D3D12_MESSAGE_SEVERITY_ERROR) { std::cerr << m->pDescription << '\n'; throw std::runtime_error("GPU validation error"); }
    }
  }
};

int wmain(int argc, wchar_t** argv) {
  try {
    require(argc >= 4 && argc <= 6,
            "Expected original VS, candidate VS, dxcompiler.dll, optionally --hardware and --cylindrical-invariance");
    bool hardware{}, cylindrical{};
    for (int i = 4; i < argc; ++i) {
      if (std::wstring(argv[i]) == L"--hardware") hardware = true;
      else if (std::wstring(argv[i]) == L"--cylindrical-invariance") cylindrical = true;
      else throw std::runtime_error("Unknown fixture mode");
    }
    const auto library = LoadLibraryW(argv[3]); require(library != nullptr, "Cannot load reflection runtime");
    const auto create = reinterpret_cast<DxcCreateInstanceProc>(GetProcAddress(library, "DxcCreateInstance")); require(create != nullptr, "No DXC factory");
    Shader original(argv[1], create), candidate(argv[2], create);
    for (const auto pair : {std::pair{&original.inputs, &candidate.inputs}, std::pair{&original.outputs, &candidate.outputs}}) {
      require(!pair.first->empty() && pair.first->size() == pair.second->size(), "Interface size mismatch");
      // Stream output and input assembly bind semantic names/indices, not the
      // reflection enumeration order. Packed scalar outputs may enumerate in
      // another order while retaining the same exact register components.
      for (const auto& a : *pair.first) {
        const auto b = std::find_if(pair.second->begin(), pair.second->end(), [&](const Parameter& value) {
          return !_stricmp(a.name.c_str(), value.name.c_str()) && a.index == value.index;
        });
        require(b != pair.second->end() && a.mask == b->mask && a.system == b->system, "Interface semantic mismatch");
      }
    }
    Fixture f(original, hardware); auto stock = f.pipeline(original), rebuilt = f.pipeline(candidate);
    double maximum{}; std::uint64_t compared{}; unsigned cases{};
    for (unsigned fog = 0; fog < 4; ++fog) for (float yaw : {-1.1f,0.f,.8f})
      for (float pitch : {-1.f,0.f,.65f}) for (float roll : {-.8f,0.f,1.2f}) {
        const UINT first = cases % 2 ? 3 : 0;
        f.inputs(yaw, cylindrical ? 0.f : pitch, cylindrical ? 0.f : roll, fog);
        const auto a = f.run(cylindrical ? rebuilt.Get() : stock.Get(),first);
        f.inputs(yaw,pitch,roll,fog);
        const auto b = f.run(rebuilt.Get(),first);
        for (std::size_t i = 0; i < a.size(); ++i) {
          if (!std::isfinite(a[i]) || !std::isfinite(b[i])) throw std::runtime_error("Nonfinite output in controlled shader fixture");
          const double delta = std::abs(static_cast<double>(a[i])-b[i]); maximum = std::max(maximum,delta);
          if (delta > 1e-5 + 2e-5*std::abs(a[i])) { std::ostringstream error;
            error << "Output mismatch case=" << cases << " scalar=" << i << " original=" << a[i] << " reconstructed=" << b[i]; throw std::runtime_error(error.str()); }
          ++compared;
        }
        ++cases;
      }
    f.validate(); hr(f.commands->Close(), "Final close");
    std::cout << "PASS: " << (cylindrical ? "cylindrical pitch/roll invariance" : "stock shader GPU equivalence")
              << " cases=" << cases << " vertices_per_case=32 compared_scalars="
              << compared << " maximum_absolute_delta=" << maximum << " debug_errors=0\n";
    std::cout << "LIMIT: controlled constants/textures/vertices; not all game materials, raster pixels or worn acceptance\n";
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
