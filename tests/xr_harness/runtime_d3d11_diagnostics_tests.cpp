#include "runtime_d3d11_diagnostics.h"
#include <Windows.h>
#include <d3d11.h>
#include <d3d11sdklayers.h>
#include <wrl/client.h>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
using Microsoft::WRL::ComPtr;
using namespace darktidevr::xr;
void expect(bool value) { if (!value) throw std::runtime_error("D3D11 diagnostic invariant failed"); }
ComPtr<ID3D11Device> create() {
  ComPtr<ID3D11Device> device;
  expect(SUCCEEDED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,
      nullptr,0,D3D11_SDK_VERSION,&device,nullptr,nullptr)));
  return device;
}
int main() {
  try {
    std::ostringstream before;
    report_runtime_d3d11_diagnostics(before); expect(before.str().empty());
    { RuntimeD3D11Diagnostics disabled(false); expect(!(create()->GetCreationFlags()&D3D11_CREATE_DEVICE_DEBUG)); }
    {
      RuntimeD3D11Diagnostics enabled(true);
      bool nested_rejected=false;
      try { RuntimeD3D11Diagnostics nested(true); } catch (...) { nested_rejected=true; }
      expect(nested_rejected);
      auto device=create();
      D3D11_TEXTURE2D_DESC description{};
      description.Width=description.Height=64; description.MipLevels=description.ArraySize=1;
      description.Format=DXGI_FORMAT_R8G8B8A8_UNORM; description.SampleDesc.Count=1;
      description.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
      description.MiscFlags=D3D11_RESOURCE_MISC_SHARED;
      ComPtr<ID3D11Texture2D> texture;
      expect(SUCCEEDED(device->CreateTexture2D(&description,nullptr,&texture)));
      ComPtr<IDXGIResource> resource; expect(SUCCEEDED(texture.As(&resource)));
      HANDLE shared{}; expect(SUCCEEDED(resource->GetSharedHandle(&shared)));
      ComPtr<ID3D11Texture2D> opened;
      expect(SUCCEEDED(device->OpenSharedResource(shared,IID_PPV_ARGS(&opened))));
      const bool debug=(device->GetCreationFlags()&D3D11_CREATE_DEVICE_DEBUG)!=0;
      if (debug) {
        ComPtr<ID3D11InfoQueue> queue; expect(SUCCEEDED(device.As(&queue)));
        expect(SUCCEEDED(queue->AddApplicationMessage(D3D11_MESSAGE_SEVERITY_WARNING,
            "diagnostic fixture\ncontinued")));
      }
      // Invalid SDK input remains an error; diagnostics cannot manufacture success.
      ComPtr<ID3D11Device> invalid;
      expect(FAILED(D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,0,
          nullptr,0,0,&invalid,nullptr,nullptr)));
      std::ostringstream result; report_runtime_d3d11_diagnostics(result);
      const auto text=result.str();
      expect(text.find("calls=2")!=std::string::npos);
      expect(text.find("original_flags=0 requested_flags=2")!=std::string::npos);
      expect(text.find("removed_reason=0")!=std::string::npos);
      expect(text.find("runtime_d3d11.import=0 device=0 handle=")!=std::string::npos);
      expect(text.find("iid=6F15AAF2-D208-4E89-9AB4-489535D34F9C")!=std::string::npos);
      expect(text.find("caller=darktidevr-runtime-d3d11-diagnostics-tests.exe")!=std::string::npos);
      for (unsigned i=0;i<10;++i)
        expect(SUCCEEDED(device->OpenSharedResource(shared,IID_PPV_ARGS(&opened))));
      std::ostringstream import_bound; report_runtime_d3d11_diagnostics(import_bound);
      expect(import_bound.str().find("runtime_d3d11.import_hook=enabled calls=11")!=std::string::npos);
      expect(import_bound.str().find("runtime_d3d11.import=7 ")!=std::string::npos);
      expect(import_bound.str().find("runtime_d3d11.import=8 ")==std::string::npos);
      expect(text.find("device=unavailable")!=std::string::npos);
      expect(text.find(debug ? "diagnostic fixture continued" : "fallback=1")!=std::string::npos);
      device.Reset(); // The bounded diagnostic record keeps it valid until scope exit.
      std::ostringstream retained; report_runtime_d3d11_diagnostics(retained);
      expect(retained.str().find("removed_reason=0")!=std::string::npos);
      for (unsigned i=0;i<10;++i) create();
      std::ostringstream bounded; report_runtime_d3d11_diagnostics(bounded);
      expect(bounded.str().find("calls=12")!=std::string::npos);
      expect(bounded.str().find("runtime_d3d11.device=7 ")!=std::string::npos);
      expect(bounded.str().find("runtime_d3d11.device=8 ")==std::string::npos);
      auto other=create();
      const auto probe=probe_shared_texture(other.Get(),reinterpret_cast<std::uintptr_t>(shared));
      expect(probe.result==S_OK && probe.width==64 && probe.height==64 &&
          probe.format==DXGI_FORMAT_R8G8B8A8_UNORM && (probe.misc_flags&D3D11_RESOURCE_MISC_SHARED));
      expect(probe_shared_texture(other.Get(),0).result==E_INVALIDARG);
      expect(probe_shared_texture(nullptr,reinterpret_cast<std::uintptr_t>(shared)).result==E_INVALIDARG);
      std::ostringstream off; probe_runtime_d3d11_import_adapters(off);
      expect(off.str().empty());
    }
    expect(!(create()->GetCreationFlags()&D3D11_CREATE_DEVICE_DEBUG));
    std::ostringstream after; report_runtime_d3d11_diagnostics(after); expect(after.str().empty());
    // A fresh scope must not inherit old devices or counts.
    { RuntimeD3D11Diagnostics again(true,true); std::ostringstream clean;
      report_runtime_d3d11_diagnostics(clean); expect(clean.str().find("calls=0")!=std::string::npos);
      std::ostringstream empty; probe_runtime_d3d11_import_adapters(empty);
      expect(empty.str()=="runtime_d3d11.adapter_probe_handles=0\n"); }
    std::cout<<"runtime_d3d11_diagnostics=pass WARP flags errors bounded_records cleanup\n";
  } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
