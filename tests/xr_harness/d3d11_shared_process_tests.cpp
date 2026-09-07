#include <Windows.h>
#include <d3d11.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
using Microsoft::WRL::ComPtr;
void check(HRESULT result,const char* operation) {
  if (FAILED(result)) throw std::runtime_error(std::string(operation)+" result="+
      std::to_string(static_cast<std::uint32_t>(result)));
}
void expect(bool value,const char* message) { if (!value) throw std::runtime_error(message); }
struct Graphics {
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  LUID luid{};
};
Graphics create(bool warp,unsigned index,std::optional<LUID> expected={}) {
  ComPtr<IDXGIFactory4> factory; check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)),"factory");
  ComPtr<IDXGIAdapter1> adapter;
  if (warp) check(factory->EnumWarpAdapter(IID_PPV_ARGS(&adapter)),"warp adapter");
  else if (!expected) check(factory->EnumAdapters1(index,&adapter),"selected adapter");
  else {
    for (unsigned candidate=0;candidate<8;++candidate) {
      ComPtr<IDXGIAdapter1> next;
      const auto enumerated=factory->EnumAdapters1(candidate,&next);
      if (enumerated==DXGI_ERROR_NOT_FOUND) break;
      check(enumerated,"child adapter enumeration");
      DXGI_ADAPTER_DESC1 desc{}; check(next->GetDesc1(&desc),"adapter description");
      if (desc.AdapterLuid.LowPart==expected->LowPart && desc.AdapterLuid.HighPart==expected->HighPart) {
        adapter=next; break;
      }
    }
    expect(adapter!=nullptr,"Child did not find parent's adapter");
  }
  DXGI_ADAPTER_DESC1 desc{}; check(adapter->GetDesc1(&desc),"adapter description");
  if (!warp) expect(!(desc.Flags&DXGI_ADAPTER_FLAG_SOFTWARE),"Hardware request selected software adapter");
  Graphics result; result.luid=desc.AdapterLuid;
  if (expected) expect(result.luid.LowPart==expected->LowPart && result.luid.HighPart==expected->HighPart,
      "Parent/child adapter identities differ");
  check(D3D11CreateDevice(adapter.Get(),D3D_DRIVER_TYPE_UNKNOWN,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      nullptr,0,D3D11_SDK_VERSION,&result.device,nullptr,&result.context),"device");
  return result;
}
int child(int argc,wchar_t** argv) {
  expect(argc==7,"Invalid child arguments");
  std::ofstream output{std::filesystem::path(argv[6])};
  try {
    const auto handle=static_cast<std::uintptr_t>(std::stoull(argv[2]));
    const LUID luid{static_cast<DWORD>(std::stoul(argv[3])),static_cast<LONG>(std::stol(argv[4]))};
    auto graphics=create(std::stoi(argv[5])!=0,0,luid);
    ComPtr<ID3D11Texture2D> texture;
    check(graphics.device->OpenSharedResource(reinterpret_cast<HANDLE>(handle),IID_PPV_ARGS(&texture)),"shared import");
    D3D11_TEXTURE2D_DESC desc{}; texture->GetDesc(&desc);
    expect(desc.Width==64 && desc.Height==64 && desc.Format==DXGI_FORMAT_R8G8B8A8_UNORM,
        "Shared description differs");
    desc.Usage=D3D11_USAGE_STAGING; desc.BindFlags=0;
    desc.CPUAccessFlags=D3D11_CPU_ACCESS_READ; desc.MiscFlags=0;
    ComPtr<ID3D11Texture2D> staging;
    check(graphics.device->CreateTexture2D(&desc,nullptr,&staging),"readback texture");
    graphics.context->CopyResource(staging.Get(),texture.Get());
    D3D11_MAPPED_SUBRESOURCE mapped{};
    check(graphics.context->Map(staging.Get(),0,D3D11_MAP_READ,0,&mapped),"readback map");
    const auto* pixel=static_cast<const unsigned char*>(mapped.pData);
    const bool red=pixel && pixel[0]==255 && pixel[1]==0 && pixel[2]==0 && pixel[3]==255;
    graphics.context->Unmap(staging.Get(),0);
    expect(red,"Shared pixel differs from producer's completed red clear");
    output<<"d3d11_shared_child=pass dimensions=64x64 pixel=255,0,0,255\n";
    return 0;
  } catch (const std::exception& error) { output<<error.what()<<'\n'; return 1; }
}
struct ChildProcess {
  PROCESS_INFORMATION info{};
  ~ChildProcess() {
    if (info.hProcess) {
      if (WaitForSingleObject(info.hProcess,0)==WAIT_TIMEOUT) {
        TerminateProcess(info.hProcess,2); WaitForSingleObject(info.hProcess,5000);
      }
      CloseHandle(info.hProcess);
    }
    if (info.hThread) CloseHandle(info.hThread);
  }
};
struct TempResult {
  wchar_t path[MAX_PATH]{};
  TempResult() {
    wchar_t directory[MAX_PATH]{};
    const auto length=GetTempPathW(MAX_PATH,directory);
    expect(length && length<MAX_PATH && GetTempFileNameW(directory,L"dvr",0,path),"Temporary result creation failed");
  }
  ~TempResult() { if (path[0]) DeleteFileW(path); }
};
int wmain(int argc,wchar_t** argv) {
  if (argc>1 && std::wstring(argv[1])==L"--child") return child(argc,argv);
  try {
    const bool warp=argc==1;
    expect(warp || (argc==3 && std::wstring(argv[1])==L"--hardware"),"Use no arguments for WARP or --hardware <adapter index>");
    auto graphics=create(warp,warp ? 0 : static_cast<unsigned>(std::stoul(argv[2])));
    D3D11_TEXTURE2D_DESC desc{}; desc.Width=desc.Height=64; desc.MipLevels=desc.ArraySize=1;
    desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM; desc.SampleDesc.Count=1;
    desc.BindFlags=D3D11_BIND_RENDER_TARGET|D3D11_BIND_SHADER_RESOURCE;
    desc.MiscFlags=D3D11_RESOURCE_MISC_SHARED;
    ComPtr<ID3D11Texture2D> texture;
    check(graphics.device->CreateTexture2D(&desc,nullptr,&texture),"producer texture");
    ComPtr<ID3D11RenderTargetView> view;
    check(graphics.device->CreateRenderTargetView(texture.Get(),nullptr,&view),"producer target");
    const float red[]{1,0,0,1}; graphics.context->ClearRenderTargetView(view.Get(),red);
    D3D11_QUERY_DESC query_desc{D3D11_QUERY_EVENT,0}; ComPtr<ID3D11Query> query;
    check(graphics.device->CreateQuery(&query_desc,&query),"completion query");
    graphics.context->End(query.Get()); graphics.context->Flush();
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    for (;;) {
      const auto result=graphics.context->GetData(query.Get(),nullptr,0,0);
      check(result,"producer completion"); if (result==S_OK) break;
      expect(std::chrono::steady_clock::now()<deadline,"Producer completion timed out"); Sleep(1);
    }
    ComPtr<IDXGIResource> resource; check(texture.As(&resource),"shared interface");
    HANDLE shared{}; check(resource->GetSharedHandle(&shared),"shared handle");
    // KMT handles are not NT handles: retain the texture and never CloseHandle(shared).
    TempResult result;
    wchar_t executable[32768]{};
    const auto length=GetModuleFileNameW(nullptr,executable,32768);
    expect(length && length<32768,"Executable path unavailable");
    auto command=L"\""+std::wstring(executable)+L"\" --child "+
        std::to_wstring(reinterpret_cast<std::uintptr_t>(shared))+L" "+
        std::to_wstring(graphics.luid.LowPart)+L" "+std::to_wstring(graphics.luid.HighPart)+
        L" "+std::to_wstring(warp ? 1 : 0)+L" \""+result.path+L"\"";
    STARTUPINFOW startup{}; startup.cb=sizeof(startup); ChildProcess process;
    expect(CreateProcessW(executable,command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,
        nullptr,nullptr,&startup,&process.info)!=FALSE,"Child creation failed");
    expect(WaitForSingleObject(process.info.hProcess,15000)==WAIT_OBJECT_0,"Child sharing test timed out");
    DWORD code{}; expect(GetExitCodeProcess(process.info.hProcess,&code)!=FALSE,"Child status unavailable");
    std::ifstream input{std::filesystem::path(result.path)}; std::ostringstream text; text<<input.rdbuf();
    std::cout<<text.str();
    expect(code==0,"Child sharing test failed");
    expect(text.str().find("d3d11_shared_child=pass")!=std::string::npos,"Child success evidence missing");
    std::cout<<"d3d11_shared_process=pass adapter="<<(warp ? "WARP" : "hardware")<<'\n';
    return 0;
  } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
