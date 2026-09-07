#include "runtime_d3d11_diagnostics.h"
#include <Windows.h>
#include <d3d11.h>
#include <d3d11sdklayers.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include <MinHook.h>
#include <intrin.h>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <ostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace darktidevr::xr {
namespace {
using Microsoft::WRL::ComPtr;
struct Record {
  ComPtr<ID3D11Device> device;
  UINT original_flags{}, requested_flags{};
  HRESULT debug_result{}, result{};
  bool fallback{};
};
std::mutex capture_mutex;
std::array<Record,8> records;
unsigned calls{};
bool capturing{};
bool probe_adapters_requested{};
decltype(&D3D11CreateDevice) original_create{};
using OpenShared=HRESULT(STDMETHODCALLTYPE*)(ID3D11Device*,HANDLE,REFIID,void**);
OpenShared original_open{};
void* open_target{};
bool open_attempted{};
struct Import {
  unsigned device{};
  std::uintptr_t handle{}, caller_offset{};
  GUID interface_id{};
  HRESULT result{};
  std::array<char,MAX_PATH> caller{};
};
std::array<Import,8> imports;
unsigned import_calls{};

HRESULT STDMETHODCALLTYPE capture_open(ID3D11Device* device, HANDLE shared,
    REFIID interface_id, void** resource) {
  const auto caller=_ReturnAddress();
  const auto result=original_open(device,shared,interface_id,resource);
  std::scoped_lock lock(capture_mutex);
  for (unsigned i=0;i<records.size();++i) {
    if (records[i].device.Get()!=device) continue;
    if (import_calls<imports.size()) {
      auto& entry=imports[import_calls];
      entry.device=i; entry.handle=reinterpret_cast<std::uintptr_t>(shared);
      entry.interface_id=interface_id; entry.result=result;
      HMODULE module{};
      if (GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
              reinterpret_cast<LPCWSTR>(caller),&module)) {
        std::array<char,MAX_PATH> path{};
        if (GetModuleFileNameA(module,path.data(),static_cast<DWORD>(path.size()))) {
          const auto leaf=std::strrchr(path.data(),'\\');
          strcpy_s(entry.caller.data(),entry.caller.size(),leaf ? leaf+1 : path.data());
        }
        entry.caller_offset=reinterpret_cast<std::uintptr_t>(caller)-
            reinterpret_cast<std::uintptr_t>(module);
      }
    }
    ++import_calls;
    break;
  }
  return result;
}

HRESULT WINAPI capture_create(IDXGIAdapter* adapter, D3D_DRIVER_TYPE type,
    HMODULE software, UINT flags, const D3D_FEATURE_LEVEL* levels, UINT level_count,
    UINT version, ID3D11Device** device, D3D_FEATURE_LEVEL* selected,
    ID3D11DeviceContext** context) {
  Record record;
  record.original_flags=flags;
  record.requested_flags=flags|D3D11_CREATE_DEVICE_DEBUG;
  record.result=original_create(adapter,type,software,record.requested_flags,
      levels,level_count,version,device,selected,context);
  record.debug_result=record.result;
  if (record.result==DXGI_ERROR_SDK_COMPONENT_MISSING && !(flags&D3D11_CREATE_DEVICE_DEBUG)) {
    // A missing optional debug layer must not make a previously valid device
    // request fail. Do not retry unrelated errors or caller-requested debug.
    record.fallback=true;
    record.result=original_create(adapter,type,software,flags,
        levels,level_count,version,device,selected,context);
  }
  if (SUCCEEDED(record.result) && device && *device) record.device=*device;
  const auto result=record.result;
  std::scoped_lock lock(capture_mutex);
  if (record.device && !open_attempted) {
    open_attempted=true;
    // Windows SDK ID3D11DeviceVtbl: OpenSharedResource is slot 28. Only the
    // first implementation is instrumented, and only captured devices log.
    const auto target=(*reinterpret_cast<void***>(record.device.Get()))[28];
    if (MH_CreateHook(target,reinterpret_cast<void*>(&capture_open),
          reinterpret_cast<void**>(&original_open))==MH_OK) {
      if (MH_EnableHook(target)==MH_OK) open_target=target;
      else MH_RemoveHook(target);
    }
  }
  if (calls<records.size()) records[calls]=std::move(record);
  ++calls;
  return result;
}
}

struct RuntimeD3D11Diagnostics::Impl {
  HMODULE module{};
  void* target{};
  bool owns_minhook{}, created{}, enabled{};
  void start() {
    {
      std::scoped_lock lock(capture_mutex);
      if (capturing) throw std::runtime_error("D3D11 diagnostic scope already active");
    }
    module=LoadLibraryExW(L"d3d11.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) throw std::runtime_error("D3D11 diagnostic library unavailable");
    target=reinterpret_cast<void*>(GetProcAddress(module,"D3D11CreateDevice"));
    if (!target) throw std::runtime_error("D3D11 diagnostic export unavailable");
    const auto initialized=MH_Initialize();
    owns_minhook=initialized==MH_OK;
    if (!owns_minhook && initialized!=MH_ERROR_ALREADY_INITIALIZED)
      throw std::runtime_error("D3D11 diagnostic hook initialization failed");
    if (MH_CreateHook(target,reinterpret_cast<void*>(&capture_create),
          reinterpret_cast<void**>(&original_create))!=MH_OK)
      throw std::runtime_error("D3D11 diagnostic hook creation failed");
    created=true;
    if (MH_EnableHook(target)!=MH_OK)
      throw std::runtime_error("D3D11 diagnostic hook enable failed");
    enabled=true;
    std::scoped_lock lock(capture_mutex);
    records={}; calls=0; imports={}; import_calls=0;
    open_attempted=false; open_target=nullptr; capturing=true;
  }
  ~Impl() {
    if (enabled && open_target) MH_DisableHook(open_target);
    if (enabled) MH_DisableHook(target);
    if (enabled && open_target) MH_RemoveHook(open_target);
    if (created) MH_RemoveHook(target);
    if (owns_minhook) MH_Uninitialize();
    if (enabled) {
      std::scoped_lock lock(capture_mutex);
      capturing=false; records={}; calls=0; imports={}; import_calls=0;
      open_target=nullptr; open_attempted=false; probe_adapters_requested=false;
    }
    if (module) FreeLibrary(module);
  }
};

RuntimeD3D11Diagnostics::RuntimeD3D11Diagnostics(bool enabled, bool probe_adapters) {
  if (enabled) {
    impl_=std::make_unique<Impl>();
    impl_->start();
    std::scoped_lock lock(capture_mutex);
    probe_adapters_requested=probe_adapters;
  }
}
RuntimeD3D11Diagnostics::~RuntimeD3D11Diagnostics()=default;

SharedTextureProbe probe_shared_texture(ID3D11Device* device,std::uintptr_t handle) {
  SharedTextureProbe result;
  if (!device || !handle) { result.result=E_INVALIDARG; return result; }
  ComPtr<ID3D11Texture2D> texture;
  result.result=device->OpenSharedResource(reinterpret_cast<HANDLE>(handle),IID_PPV_ARGS(&texture));
  if (SUCCEEDED(result.result) && texture) {
    D3D11_TEXTURE2D_DESC desc{}; texture->GetDesc(&desc);
    result.width=desc.Width; result.height=desc.Height;
    result.format=desc.Format; result.misc_flags=desc.MiscFlags;
  }
  return result;
}

void probe_runtime_d3d11_import_adapters(std::ostream& output) {
  std::array<std::uintptr_t,8> handles{};
  unsigned count{};
  {
    std::scoped_lock lock(capture_mutex);
    if (!capturing || !probe_adapters_requested) return;
    for (unsigned i=0;i<import_calls && i<imports.size();++i) {
      const auto& entry=imports[i];
      if (SUCCEEDED(entry.result) || !entry.handle || entry.interface_id!=__uuidof(ID3D11Texture2D)) continue;
      bool duplicate=false;
      for (unsigned h=0;h<count;++h) duplicate=duplicate || handles[h]==entry.handle;
      if (!duplicate) handles[count++]=entry.handle;
    }
  }
  output<<"runtime_d3d11.adapter_probe_handles="<<count<<'\n';
  if (!count) return;
  ComPtr<IDXGIFactory1> factory;
  const auto factory_result=CreateDXGIFactory1(IID_PPV_ARGS(&factory));
  if (FAILED(factory_result)) {
    output<<"runtime_d3d11.adapter_probe_factory="<<static_cast<std::uint32_t>(factory_result)<<'\n';
    return;
  }
  for (unsigned i=0;i<8;++i) {
    ComPtr<IDXGIAdapter1> adapter;
    const auto enumerated=factory->EnumAdapters1(i,&adapter);
    if (enumerated==DXGI_ERROR_NOT_FOUND) break;
    if (FAILED(enumerated)) {
      output<<"runtime_d3d11.adapter_probe_enumeration="<<static_cast<std::uint32_t>(enumerated)<<'\n'; break;
    }
    DXGI_ADAPTER_DESC1 desc{};
    if (FAILED(adapter->GetDesc1(&desc)) || (desc.Flags&DXGI_ADAPTER_FLAG_SOFTWARE)) continue;
    ComPtr<ID3D11Device> device;
    // Bypass our creation hook: these are diagnostic devices, never backend
    // observations. No context, rendering, writes or debug flag override.
    const auto created=original_create(adapter.Get(),D3D_DRIVER_TYPE_UNKNOWN,nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,&device,nullptr,nullptr);
    char name[512]{};
    WideCharToMultiByte(CP_UTF8,0,desc.Description,-1,name,sizeof(name),nullptr,nullptr);
    output<<"runtime_d3d11.adapter_probe="<<i<<" name="<<name
        <<" create_result="<<static_cast<std::uint32_t>(created)<<'\n';
    if (FAILED(created)) continue;
    for (unsigned h=0;h<count;++h) {
      const auto result=probe_shared_texture(device.Get(),handles[h]);
      output<<"runtime_d3d11.adapter_import="<<i<<" handle="<<handles[h]
          <<" result="<<static_cast<std::uint32_t>(result.result)
          <<" width="<<result.width<<" height="<<result.height
          <<" format="<<result.format<<" misc_flags="<<result.misc_flags<<'\n';
    }
  }
}

void report_runtime_d3d11_diagnostics(std::ostream& output) {
  std::scoped_lock lock(capture_mutex);
  if (!capturing) return;
  output<<"runtime_d3d11.diagnostic=debug_layer_requested process_local=1 calls="<<calls<<'\n';
  output<<"runtime_d3d11.import_hook="<<(open_target ? "enabled" : "unavailable")
      <<" calls="<<import_calls<<'\n';
  for (unsigned i=0;i<import_calls && i<imports.size();++i) {
    const auto& entry=imports[i];
    const auto& id=entry.interface_id;
    char guid[40]{};
    std::snprintf(guid,sizeof(guid),"%08lX-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X",
        id.Data1,id.Data2,id.Data3,id.Data4[0],id.Data4[1],id.Data4[2],id.Data4[3],
        id.Data4[4],id.Data4[5],id.Data4[6],id.Data4[7]);
    output<<"runtime_d3d11.import="<<i<<" device="<<entry.device
        <<" handle="<<entry.handle<<" iid="<<guid
        <<" result="<<static_cast<std::uint32_t>(entry.result)
        <<" caller="<<entry.caller.data()<<" caller_offset="<<entry.caller_offset<<'\n';
  }
  for (unsigned i=0;i<calls && i<records.size();++i) {
    const auto& record=records[i];
    output<<"runtime_d3d11.device="<<i<<" original_flags="<<record.original_flags
        <<" requested_flags="<<record.requested_flags<<" debug_result="
        <<static_cast<std::uint32_t>(record.debug_result)<<" fallback="<<record.fallback
        <<" result="<<static_cast<std::uint32_t>(record.result);
    if (!record.device) { output<<" device=unavailable\n"; continue; }
    output<<" actual_flags="<<record.device->GetCreationFlags()<<" removed_reason="
        <<static_cast<std::uint32_t>(record.device->GetDeviceRemovedReason())<<'\n';
    ComPtr<ID3D11InfoQueue> queue;
    if (FAILED(record.device.As(&queue))) {
      output<<"runtime_d3d11.messages="<<i<<" unavailable\n"; continue;
    }
    const auto count=queue->GetNumStoredMessagesAllowedByRetrievalFilter();
    output<<"runtime_d3d11.messages="<<i<<" count="<<count<<'\n';
    for (auto index=count>8 ? count-8 : 0;index<count;++index) {
      SIZE_T bytes{};
      if (FAILED(queue->GetMessage(index,nullptr,&bytes)) ||
          bytes<sizeof(D3D11_MESSAGE) || bytes>1024*1024) continue;
      std::vector<std::byte> storage(bytes);
      auto* message=reinterpret_cast<D3D11_MESSAGE*>(storage.data());
      if (FAILED(queue->GetMessage(index,message,&bytes))) continue;
      std::string text;
      if (message->pDescription) {
        for (SIZE_T c=0;c<message->DescriptionByteLength && c<2048 && message->pDescription[c];++c) {
          const auto ch=message->pDescription[c];
          text+=ch=='\r' || ch=='\n' ? ' ' : ch;
        }
      }
      output<<"runtime_d3d11.message="<<i<<" id="<<message->ID
          <<" severity="<<message->Severity<<" text="<<text<<'\n';
    }
  }
}
}
