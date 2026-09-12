#include "../isolated_transports.h"
#include <d3d12.h>
#include <wrl/client.h>

#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc != 6) throw std::runtime_error("Expected fixture root and four selections");
    darktidevr::tests::isolate_transports();
    const auto root = std::filesystem::path(argv[1]);
    if (!GetModuleHandleW((root / L"binaries/d3d12.dll").c_str())) {
      throw std::runtime_error("Test executable did not import the fixture bootstrap");
    }
    Microsoft::WRL::ComPtr<ID3D12Device> device;
    if (FAILED(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device)))) {
      throw std::runtime_error("Bootstrap device creation failed");
    }
    const auto native = GetModuleHandleW(
        (root / L"mods/darktidevr/bin/darktidevr_native_capture.dll").c_str());
    if (!native) throw std::runtime_error("Bootstrap did not load the fixture native module");
    const char* exports[] = {"dtvr_set_diagnostic_render_hooks", "dtvr_set_vertex_shader_dump",
        "dtvr_set_billboard_shader_substitution", "dtvr_set_billboard_pixel_shader_probe"};
    for (int i = 0; i < 4; ++i) {
      const int selected = std::stoi(argv[i + 2]);
      const auto select = reinterpret_cast<int (*)(int)>(GetProcAddress(native, exports[i]));
      if (!select || select(selected) != 0 || select(1 - selected) != 1) {
        throw std::runtime_error(std::string("Immutable startup selection disagrees: ") + exports[i]);
      }
    }
    std::cout << "bootstrap_selection=pass\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
