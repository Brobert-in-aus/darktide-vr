#include "producer/resource_name_match.h"
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <string>
#include <vector>
#include <chrono>
#include <iostream>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
void check(bool value) { if (!value) throw std::runtime_error("name mismatch"); }
void ok(HRESULT result) { check(SUCCEEDED(result)); }
std::string resource_debug_name(ID3D12Resource* resource) {
  if (!resource) {
    return {};
  }

  UINT wide_size = 0;
  if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectNameW,
                                         &wide_size, nullptr)) &&
      wide_size >= sizeof(wchar_t)) {
    std::vector<wchar_t> wide_name(
        (wide_size + sizeof(wchar_t) - 1) / sizeof(wchar_t) + 1, L'\0');
    if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectNameW,
                                           &wide_size, wide_name.data()))) {
      const auto required = WideCharToMultiByte(
          CP_UTF8, 0, wide_name.data(), -1, nullptr, 0, nullptr, nullptr);
      if (required > 1) {
        std::string name(static_cast<std::size_t>(required), '\0');
        WideCharToMultiByte(CP_UTF8, 0, wide_name.data(), -1, name.data(),
                            required, nullptr, nullptr);
        name.pop_back();
        return name;
      }
    }
  }

  UINT narrow_size = 0;
  if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectName,
                                         &narrow_size, nullptr)) &&
      narrow_size > 0) {
    std::string name(static_cast<std::size_t>(narrow_size), '\0');
    if (SUCCEEDED(resource->GetPrivateData(WKPDID_D3DDebugObjectName,
                                           &narrow_size, name.data()))) {
      while (!name.empty() && name.back() == '\0') {
        name.pop_back();
      }
      return name;
    }
  }
  return {};
}

int main() {
  ComPtr<IDXGIFactory4> factory; ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
  ComPtr<IDXGIAdapter> warp; ok(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
  ComPtr<ID3D12Device> device; ok(D3D12CreateDevice(warp.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device)));
  D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
  D3D12_RESOURCE_DESC desc{}; desc.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
  desc.Width=256; desc.Height=1; desc.DepthOrArraySize=1; desc.MipLevels=1;
  desc.SampleDesc.Count=1; desc.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  ComPtr<ID3D12Resource> resource;
  ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,
      D3D12_RESOURCE_STATE_COMMON,nullptr,IID_PPV_ARGS(&resource)));
  unsigned fallbacks=0;
  const auto fresh=[&] {
    return darktidevr::producer::match_resource_name(resource.Get(),
      {"0xaf0f1409769cf92b","0xf91259166b1933b1"},
      [&] { ++fallbacks; return resource_debug_name(resource.Get()); });
  };
  const auto old=[&] {
    auto name=resource_debug_name(resource.Get());
    return name=="0xaf0f1409769cf92b" ? 0 : name=="0xf91259166b1933b1" ? 1 : -1;
  };
  check(fresh()==old());
  check(darktidevr::producer::match_resource_name(nullptr,{"name"},
      []() -> std::string { throw std::runtime_error("null fallback"); })==-1);
  const auto wide=[&](const std::wstring& name) {
    ok(resource->SetPrivateData(WKPDID_D3DDebugObjectNameW,
      static_cast<UINT>(name.size()*sizeof(wchar_t)),name.data()));
    check(fresh()==old());
  };
  const auto narrow=[&](const std::string& name) {
    ok(resource->SetPrivateData(WKPDID_D3DDebugObjectName,
      static_cast<UINT>(name.size()),name.data()));
    check(fresh()==old());
  };
  narrow("0xaf0f1409769cf92b"); check(fresh()==0);
  wide(L"0xf91259166b1933b1"); check(fresh()==1);
  wide(std::wstring(L"0xaf0f1409769cf92b")+L'\0'+L"tail"); check(fresh()==0);
  wide(std::wstring(1,L'\0')); check(fresh()==0); // Empty wide falls back to ANSI.
  narrow(std::string("0xaf0f1409769cf92b")+std::string(3,'\0')); check(fresh()==0);
  narrow(std::string("0xaf0f1409769cf92b")+'\0'+"tail"); check(fresh()==-1);
  wide(std::wstring(64,L'x')); wide(std::wstring(65,L'x'));
  wide(std::wstring(1,static_cast<wchar_t>(0x20ac)));
  wide(L""); narrow(std::string(129,'x'));
  wide(L"0xaf0f1409769cf92b");
  check(fresh()==0);
  wide(L"renamed"); check(fresh()==-1);
  wide(L"0xaf0f1409769cf92b");
  const auto fallback_before=fallbacks;
  for (unsigned trial=0;trial<5;++trial) {
    const auto measure=[&](bool baseline) {
      const auto start=std::chrono::steady_clock::now();
      for (unsigned i=0;i<200000;++i) check((baseline?old():fresh())==0);
      return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    };
    double before{},after{};
    if (trial%2) {after=measure(false);before=measure(true);}
    else {before=measure(true);after=measure(false);}
    std::cout << "trial=" << trial << " queries=200000 old_ms=" << before << " new_ms=" << after << '\n';
  }
  check(fallbacks==fallback_before);
  std::cout << "PASS real WARP resource names, changes, precedence, long-name fallback; short-name benchmark fallback calls=0\n";
}
