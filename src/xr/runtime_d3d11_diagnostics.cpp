#include "runtime_d3d11_diagnostics.h"
#include <Windows.h>
#include <d3d11.h>
#include <d3d11sdklayers.h>
#include <wrl/client.h>
#include <MinHook.h>
#include <array>
#include <cstdint>
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
decltype(&D3D11CreateDevice) original_create{};

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
    records={}; calls=0; capturing=true;
  }
  ~Impl() {
    if (enabled) MH_DisableHook(target);
    if (created) MH_RemoveHook(target);
    if (owns_minhook) MH_Uninitialize();
    if (enabled) {
      std::scoped_lock lock(capture_mutex);
      capturing=false; records={}; calls=0;
    }
    if (module) FreeLibrary(module);
  }
};

RuntimeD3D11Diagnostics::RuntimeD3D11Diagnostics(bool enabled) {
  if (enabled) {
    impl_=std::make_unique<Impl>();
    impl_->start();
  }
}
RuntimeD3D11Diagnostics::~RuntimeD3D11Diagnostics()=default;

void report_runtime_d3d11_diagnostics(std::ostream& output) {
  std::scoped_lock lock(capture_mutex);
  if (!capturing) return;
  output<<"runtime_d3d11.diagnostic=debug_layer_requested process_local=1 calls="<<calls<<'\n';
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
