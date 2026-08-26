#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>

#include <array>
#include <cstring>
#include <string>

namespace {

using Microsoft::WRL::ComPtr;
using SetDiagnosticHooksFn = int (*)(int);
using SetBillboardShaderSubstitutionFn = int (*)(int);
using SetVertexShaderDumpFn = int (*)(int);
using SetBillboardBasisFn = int (*)(float, float, float, float, float, float,
                                    int);
using InstallForDeviceFn = int (*)(ID3D12Device*);

INIT_ONCE real_d3d12_once = INIT_ONCE_STATIC_INIT;
INIT_ONCE native_capture_once = INIT_ONCE_STATIC_INIT;
HMODULE proxy_module{};
HMODULE real_d3d12{};
ID3D12Device* first_device{};

void write_bootstrap_log(const char* message) {
  std::array<wchar_t, 32768> module_path{};
  const auto length = GetModuleFileNameW(
      proxy_module, module_path.data(), static_cast<DWORD>(module_path.size()));
  if (length == 0 || length >= module_path.size()) {
    return;
  }
  std::wstring path(module_path.data(), length);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return;
  }
  path.resize(separator + 1);
  path += L"darktidevr-d3d12-bootstrap.log";
  const auto file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                                FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  DWORD written{};
  WriteFile(file, message, static_cast<DWORD>(strlen(message)), &written,
            nullptr);
  WriteFile(file, "\r\n", 2, &written, nullptr);
  CloseHandle(file);
}

BOOL CALLBACK initialize_real_d3d12(PINIT_ONCE, PVOID, PVOID*) {
  std::array<wchar_t, MAX_PATH> system_directory{};
  const auto length = GetSystemDirectoryW(
      system_directory.data(), static_cast<UINT>(system_directory.size()));
  if (length == 0 || length >= system_directory.size()) {
    return FALSE;
  }
  std::wstring path(system_directory.data(), length);
  path += L"\\d3d12.dll";
  real_d3d12 = LoadLibraryW(path.c_str());
  return real_d3d12 ? TRUE : FALSE;
}

template <typename Function>
Function resolve_real(const char* name) {
  if (!InitOnceExecuteOnce(&real_d3d12_once, initialize_real_d3d12, nullptr,
                           nullptr)) {
    return nullptr;
  }
  return reinterpret_cast<Function>(GetProcAddress(real_d3d12, name));
}

BOOL CALLBACK initialize_native_capture(PINIT_ONCE, PVOID, PVOID*) {
  std::array<wchar_t, 32768> module_path{};
  const auto length = GetModuleFileNameW(
      proxy_module, module_path.data(), static_cast<DWORD>(module_path.size()));
  if (length == 0 || length >= module_path.size()) {
    return FALSE;
  }
  std::wstring path(module_path.data(), length);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return FALSE;
  }
  path.resize(separator + 1);
  const auto mod_bin_path =
      path + L"..\\mods\\darktidevr_stereo_probe\\bin\\";
  const auto diagnostic_flag_path =
      mod_bin_path + L"darktidevr_diagnostic_render_hooks.flag";
  const auto diagnostic_flag_attributes =
      GetFileAttributesW(diagnostic_flag_path.c_str());
  const auto diagnostic_hooks_requested =
      diagnostic_flag_attributes != INVALID_FILE_ATTRIBUTES &&
      (diagnostic_flag_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
  const auto substitution_flag_path =
      mod_bin_path + L"darktidevr_billboard_shader_substitution.flag";
  const auto substitution_flag_attributes =
      GetFileAttributesW(substitution_flag_path.c_str());
  const auto billboard_shader_substitution_requested =
      substitution_flag_attributes != INVALID_FILE_ATTRIBUTES &&
      (substitution_flag_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
  const auto shader_dump_flag_path =
      mod_bin_path + L"darktidevr_vertex_shader_dump.flag";
  const auto shader_dump_flag_attributes =
      GetFileAttributesW(shader_dump_flag_path.c_str());
  const auto vertex_shader_dump_requested =
      shader_dump_flag_attributes != INVALID_FILE_ATTRIBUTES &&
      (shader_dump_flag_attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
  path = mod_bin_path + L"darktidevr_native_capture.dll";
  const auto native = LoadLibraryW(path.c_str());
  if (!native) {
    char message[96]{};
    wsprintfA(message, "native_load_failed error=%lu", GetLastError());
    write_bootstrap_log(message);
    return FALSE;
  }
  const auto select_diagnostics = reinterpret_cast<SetDiagnosticHooksFn>(
      GetProcAddress(native, "dtvr_set_diagnostic_render_hooks"));
  const auto set_billboard_basis = reinterpret_cast<SetBillboardBasisFn>(
      GetProcAddress(native, "dtvr_set_billboard_view_basis"));
  const auto set_billboard_shader_substitution =
      reinterpret_cast<SetBillboardShaderSubstitutionFn>(GetProcAddress(
          native, "dtvr_set_billboard_shader_substitution"));
  const auto set_vertex_shader_dump = reinterpret_cast<SetVertexShaderDumpFn>(
      GetProcAddress(native, "dtvr_set_vertex_shader_dump"));
  const auto install = reinterpret_cast<InstallForDeviceFn>(
      GetProcAddress(native, "dtvr_install_for_device"));
  const auto diagnostics_result =
      select_diagnostics
          ? select_diagnostics(diagnostic_hooks_requested ? 1 : 0)
          : -1;
  const auto substitution_result = set_billboard_shader_substitution
                                       ? set_billboard_shader_substitution(
                                             billboard_shader_substitution_requested
                                                 ? 1
                                                 : 0)
                                       : -1;
  const auto shader_dump_result =
      set_vertex_shader_dump
          ? set_vertex_shader_dump(vertex_shader_dump_requested ? 1 : 0)
          : -1;
  const auto basis_result =
      set_billboard_basis
          ? set_billboard_basis(1.0F, 0.0F, 0.0F, 0.0F, 0.0F, 1.0F, 0)
          : -1;
  const auto install_result = install ? install(first_device) : -1;
  char message[224]{};
  wsprintfA(message,
            "native_results diagnostic_requested=%d diagnostics=%d "
            "substitution_requested=%d substitution=%d "
            "shader_dump_requested=%d shader_dump=%d "
            "basis=%d install=%d",
            diagnostic_hooks_requested ? 1 : 0, diagnostics_result,
            billboard_shader_substitution_requested ? 1 : 0,
            substitution_result, vertex_shader_dump_requested ? 1 : 0,
            shader_dump_result, basis_result, install_result);
  write_bootstrap_log(message);
  return diagnostics_result == 0 && substitution_result == 0 &&
                 shader_dump_result == 0 && basis_result == 0 &&
                 install_result == 0
             ? TRUE
             : FALSE;
}

void install_native_capture(IUnknown* returned_device) {
  if (!returned_device || first_device) {
    return;
  }
  ComPtr<ID3D12Device> device;
  if (FAILED(returned_device->QueryInterface(IID_PPV_ARGS(&device)))) {
    return;
  }
  first_device = device.Get();
  InitOnceExecuteOnce(&native_capture_once, initialize_native_capture, nullptr,
                      nullptr);
  first_device = nullptr;
}

}  // namespace

extern "C" HRESULT WINAPI D3D12CreateDevice(IUnknown* adapter,
                                              D3D_FEATURE_LEVEL minimum_level,
                                              REFIID iid, void** output) {
  const auto function =
      resolve_real<PFN_D3D12_CREATE_DEVICE>("D3D12CreateDevice");
  if (!function) {
    return E_NOINTERFACE;
  }
  const auto result = function(adapter, minimum_level, iid, output);
  char message[128]{};
  wsprintfA(message, "create_device result=0x%08lX output=%p",
            static_cast<unsigned long>(result), output ? *output : nullptr);
  write_bootstrap_log(message);
  if (SUCCEEDED(result) && output && *output) {
    install_native_capture(static_cast<IUnknown*>(*output));
  }
  return result;
}

#define DTVR_FORWARD_HRESULT(name, signature, arguments)                       \
  extern "C" HRESULT WINAPI name signature {                                  \
    const auto function = resolve_real<decltype(&::name)>(#name);              \
    return function ? function arguments : E_NOINTERFACE;                     \
  }

DTVR_FORWARD_HRESULT(D3D12GetDebugInterface, (REFIID iid, void** output),
                     (iid, output))
DTVR_FORWARD_HRESULT(
    D3D12SerializeRootSignature,
    (const D3D12_ROOT_SIGNATURE_DESC* description,
     D3D_ROOT_SIGNATURE_VERSION version, ID3DBlob** blob, ID3DBlob** error),
    (description, version, blob, error))
DTVR_FORWARD_HRESULT(D3D12CreateRootSignatureDeserializer,
                     (LPCVOID data, SIZE_T size, REFIID iid, void** output),
                     (data, size, iid, output))
DTVR_FORWARD_HRESULT(
    D3D12SerializeVersionedRootSignature,
    (const D3D12_VERSIONED_ROOT_SIGNATURE_DESC* description, ID3DBlob** blob,
     ID3DBlob** error),
    (description, blob, error))
DTVR_FORWARD_HRESULT(D3D12CreateVersionedRootSignatureDeserializer,
                     (LPCVOID data, SIZE_T size, REFIID iid, void** output),
                     (data, size, iid, output))
DTVR_FORWARD_HRESULT(
    D3D12EnableExperimentalFeatures,
    (UINT feature_count, const IID* feature_ids, void* configurations,
     UINT* configuration_sizes),
    (feature_count, feature_ids, configurations, configuration_sizes))
DTVR_FORWARD_HRESULT(D3D12GetInterface,
                     (REFCLSID class_id, REFIID iid, void** output),
                     (class_id, iid, output))

#undef DTVR_FORWARD_HRESULT

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    proxy_module = instance;
    DisableThreadLibraryCalls(instance);
  }
  return TRUE;
}
