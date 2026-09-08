#include "../isolated_transports.h"
#include <d3d12.h>
#include <d3dcompiler.h>
#include <wrl/client.h>

#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <vector>

using Microsoft::WRL::ComPtr;

template <D3D12_PIPELINE_STATE_SUBOBJECT_TYPE Kind, typename T>
struct alignas(void*) Subobject {
  D3D12_PIPELINE_STATE_SUBOBJECT_TYPE kind = Kind;
  T value{};
};

struct Stream {
  Subobject<D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_ROOT_SIGNATURE, ID3D12RootSignature*> root;
  Subobject<D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_VS, D3D12_SHADER_BYTECODE> vertex;
  Subobject<D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PS, D3D12_SHADER_BYTECODE> pixel;
  Subobject<D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_RENDER_TARGET_FORMATS, D3D12_RT_FORMAT_ARRAY> formats;
  Subobject<D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_PRIMITIVE_TOPOLOGY, D3D12_PRIMITIVE_TOPOLOGY_TYPE> topology;
  Subobject<D3D12_PIPELINE_STATE_SUBOBJECT_TYPE_DEPTH_STENCIL, D3D12_DEPTH_STENCIL_DESC> depth;
};

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    std::ostringstream error;
    error << operation << " failed: 0x" << std::hex << result;
    throw std::runtime_error(error.str());
  }
}

std::vector<char> read(const std::filesystem::path& path) {
  std::ifstream stream(path, std::ios::binary);
  std::vector<char> bytes((std::istreambuf_iterator<char>(stream)), {});
  if (bytes.empty()) throw std::runtime_error("Empty shader fixture");
  return bytes;
}

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc != 3) throw std::runtime_error("Expected isolated directory and mode");
    darktidevr::tests::isolate_transports();
    const auto directory = std::filesystem::path(argv[1]);
    const bool reject_creation = std::wstring_view(argv[2]) == L"fallback";
    const auto vs = read(directory / L"vs_main.dxil");
    const auto ps = read(directory / L"ps_stock.dxil");
    std::uint64_t hash = 1469598103934665603ULL;
    for (const auto byte : ps) {
      hash ^= static_cast<unsigned char>(byte);
      hash *= 1099511628211ULL;
    }
    std::wostringstream name;
    name << L"ps-" << std::hex << std::setfill(L'0') << std::setw(16) << hash << L".dxil";
    std::filesystem::create_directory(directory / L"billboard_shaders");
    std::filesystem::copy_file(directory /
        (reject_creation ? L"ps_invalid.dxil" : L"ps_probe.dxil"),
        directory / L"billboard_shaders" / name.str());

    // Seed a real pipeline-library entry before installing the native hooks.
    ComPtr<ID3D12Device2> device;
    check(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_12_0,
        IID_PPV_ARGS(&device)), "CreateDevice");
    D3D12_ROOT_SIGNATURE_DESC root_desc{};
    root_desc.Flags = D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;
    ComPtr<ID3DBlob> root_blob;
    ComPtr<ID3DBlob> errors;
    check(D3D12SerializeRootSignature(&root_desc, D3D_ROOT_SIGNATURE_VERSION_1,
        &root_blob, &errors), "SerializeRootSignature");
    ComPtr<ID3D12RootSignature> root;
    check(device->CreateRootSignature(0, root_blob->GetBufferPointer(),
        root_blob->GetBufferSize(), IID_PPV_ARGS(&root)), "CreateRootSignature");
    Stream stream;
    stream.root.value = root.Get();
    stream.vertex.value = {vs.data(), vs.size()};
    stream.pixel.value = {ps.data(), ps.size()};
    stream.formats.value.NumRenderTargets = 1;
    stream.formats.value.RTFormats[0] = DXGI_FORMAT_R8G8B8A8_UNORM;
    stream.topology.value = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    const D3D12_PIPELINE_STATE_STREAM_DESC description{sizeof(stream), &stream};
    ComPtr<ID3D12PipelineState> stock;
    check(device->CreatePipelineState(&description, IID_PPV_ARGS(&stock)), "CreateStockPipeline");
    ComPtr<ID3D12PipelineLibrary1> library;
    check(device->CreatePipelineLibrary(nullptr, 0, IID_PPV_ARGS(&library)), "CreatePipelineLibrary");
    check(library->StorePipeline(L"stock", stock.Get()), "StorePipeline");

    const auto module = LoadLibraryW((directory / L"darktidevr_native_capture.dll").c_str());
    if (!module) throw std::runtime_error("Load native fixture failed");
    const auto probe = reinterpret_cast<int (*)(int)>(GetProcAddress(module, "dtvr_set_billboard_pixel_shader_probe"));
    const auto install = reinterpret_cast<int (*)()>(GetProcAddress(module, "dtvr_install"));
    const auto counts = reinterpret_cast<unsigned long long (*)(unsigned int)>(
        GetProcAddress(module, "dtvr_billboard_pixel_shader_probe_result_count"));
    if (!probe || !install || !counts || probe(1) != 0 || install() != 0) {
      throw std::runtime_error("Probe initialization failed");
    }
    ComPtr<ID3D12PipelineState> loaded;
    check(library->LoadPipeline(L"stock", &description, IID_PPV_ARGS(&loaded)), "LoadCachedPipeline");
    const auto attempts = counts(0), applied = counts(1), validation = counts(2), rejected = counts(3);
    if (attempts != 1 || validation != 0 ||
        applied != (reject_creation ? 0ULL : 1ULL) ||
        rejected != (reject_creation ? 1ULL : 0ULL)) {
      std::ostringstream error;
      error << "Cached probe outcome mismatch: attempts=" << attempts
            << " applied=" << applied << " validation=" << validation << " creation_rejected=" << rejected;
      throw std::runtime_error(error.str());
    }
    if (!reject_creation) {
      // A selected replacement is created directly, even with no cached name.
      ComPtr<ID3D12PipelineState> uncached;
      check(library->LoadPipeline(L"never-stored", &description,
          IID_PPV_ARGS(&uncached)), "LoadUncachedProbe");
      if (counts(1) != 2) throw std::runtime_error("Uncached probe was not applied");
    }
    std::cout << "Cached pixel probe " << (reject_creation ? "fallback" : "application") << " passed\n";
    // Hook code stays loaded through process teardown, as in native_capture_hooks.
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
