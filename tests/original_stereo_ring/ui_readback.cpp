#include "producer/stereo_ui_readback.h"
#include <Windows.h>
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <array>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <thread>

using Microsoft::WRL::ComPtr;
namespace fs=std::filesystem;
bool match_armed{};
namespace darktidevr::producer {
void arm_ngx_copy_ui_match(ID3D12Resource* left, ID3D12Resource* right, std::uint64_t pose) {
  match_armed=left && right && pose==42;
}
}
void check(HRESULT result) { if(FAILED(result)) throw std::runtime_error("D3D12 readback fixture failed"); }
void expect(bool result) { if(!result) throw std::runtime_error("UI readback invariant failed"); }
std::string read(const fs::path& path) {
  const auto file=CreateFileW(path.c_str(),GENERIC_READ,
      FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(file==INVALID_HANDLE_VALUE) return {};
  LARGE_INTEGER size{};
  if(!GetFileSizeEx(file,&size) || size.QuadPart<0 || size.QuadPart>1024*1024) {
    CloseHandle(file); throw std::runtime_error("Invalid fixture file size");
  }
  std::string data(static_cast<std::size_t>(size.QuadPart),'\0');
  DWORD count{};
  const bool ok=ReadFile(file,data.data(),static_cast<DWORD>(data.size()),&count,nullptr)!=0;
  CloseHandle(file);
  if(!ok) return {};
  data.resize(count);
  return data;
}
int main(int argc,char** argv) {
  try {
    const std::string mode=argc>1 ? argv[1] : "";
    const bool failure=mode=="failure";
    const bool observed=mode=="overlay-wait";
    const bool source_failure=mode=="source-failure";
    const auto directory=fs::absolute("ui-readback-test-"+std::to_string(GetCurrentProcessId())+"-"+std::to_string(GetTickCount64()));
    fs::create_directories(directory);
    // Process-local TMP prevents this test request from reaching a running game.
    expect(SetEnvironmentVariableW(L"TMP",directory.c_str())!=0);
    std::array<wchar_t,MAX_PATH> selected{};
    expect(GetTempPathW(static_cast<DWORD>(selected.size()),selected.data())>0);
    expect(fs::equivalent(directory,fs::path(selected.data())));
    expect(SetEnvironmentVariableW(L"DARKTIDEVR_CAPTURE_UI_ALPHA",observed || failure || source_failure ? L"1" : nullptr)!=0);
    expect(darktidevr::producer::stereo_ui_overlay_capture_requested()==(observed || failure || source_failure));
    const auto stem=directory/("darktidevr-ui-readback-"+std::to_string(GetCurrentProcessId()));
    if(failure) fs::create_directory(stem.wstring()+L"-left-ui.bmp");
    { std::ofstream request(directory/"darktidevr-ui-readback.request"); request<<"test\n"; expect(request.good()); }
    ComPtr<IDXGIFactory4> factory; check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter> warp; check(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
    ComPtr<ID3D12Device> device; check(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)));
    D3D12_COMMAND_QUEUE_DESC queue_desc{};
    ComPtr<ID3D12CommandQueue> queue; check(device->CreateCommandQueue(&queue_desc,IID_PPV_ARGS(&queue)));
    ComPtr<ID3D12CommandAllocator> allocator;
    check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,IID_PPV_ARGS(&allocator)));
    ComPtr<ID3D12GraphicsCommandList> commands;
    check(device->CreateCommandList(0,D3D12_COMMAND_LIST_TYPE_DIRECT,allocator.Get(),nullptr,IID_PPV_ARGS(&commands)));
    D3D12_RESOURCE_DESC desc{}; desc.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    desc.Width=desc.Height=2; desc.DepthOrArraySize=desc.MipLevels=1;
    desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM; desc.SampleDesc.Count=1;
    D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
    ComPtr<ID3D12Resource> source;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&source)));
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{}; UINT64 bytes{};
    device->GetCopyableFootprints(&desc,0,1,0,&footprint,nullptr,nullptr,&bytes);
    D3D12_RESOURCE_DESC buffer{}; buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
    buffer.Width=bytes; buffer.Height=buffer.DepthOrArraySize=buffer.MipLevels=1;
    buffer.SampleDesc.Count=1; buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    heap.Type=D3D12_HEAP_TYPE_UPLOAD;
    ComPtr<ID3D12Resource> upload;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&buffer,D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&upload)));
    void* mapped{}; const D3D12_RANGE no_read{0,0}; check(upload->Map(0,&no_read,&mapped));
    std::memset(mapped,0xaa,static_cast<std::size_t>(bytes));
    auto* pixels=static_cast<unsigned char*>(mapped)+footprint.Offset;
    for(unsigned y=0;y<2;++y) for(unsigned x=0;x<8;++x)
      pixels[y*footprint.Footprint.RowPitch+x]=static_cast<unsigned char>(y*8+x);
    upload->Unmap(0,nullptr);
    D3D12_TEXTURE_COPY_LOCATION from{},to{};
    from.pResource=upload.Get(); from.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT; from.PlacedFootprint=footprint;
    to.pResource=source.Get(); to.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands->CopyTextureRegion(&to,0,0,0,&from,nullptr);
    ComPtr<ID3D12Resource> overlay;
    if(observed) {
      darktidevr::producer::stage_stereo_ui_readback(commands.Get(),source.Get(),source.Get(),source.Get(),source.Get(),42);
      expect(fs::exists(directory/"darktidevr-ui-readback.request"));
      expect(darktidevr::producer::stereo_ui_overlay_capture_requested());
      expect(!match_armed && !darktidevr::producer::stereo_ui_overlay_readback_staged());
      auto overlay_desc=desc;overlay_desc.Flags=D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET;
      D3D12_HEAP_PROPERTIES overlay_heap{};overlay_heap.Type=D3D12_HEAP_TYPE_DEFAULT;
      check(device->CreateCommittedResource(&overlay_heap,D3D12_HEAP_FLAG_NONE,&overlay_desc,
          D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&overlay)));
      to.pResource=overlay.Get();commands->CopyTextureRegion(&to,0,0,0,&from,nullptr);
      D3D12_RESOURCE_BARRIER barrier{};barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      barrier.Transition={overlay.Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
          D3D12_RESOURCE_STATE_COPY_DEST,D3D12_RESOURCE_STATE_RENDER_TARGET};
      commands->ResourceBarrier(1,&barrier);
      darktidevr::producer::observe_stereo_ui_readback_overlay(0,42,overlay.Get());
      darktidevr::producer::observe_stereo_ui_readback_overlay(1,41,overlay.Get());
      std::this_thread::sleep_for(std::chrono::milliseconds(1050));
      darktidevr::producer::stage_stereo_ui_readback(commands.Get(),source.Get(),source.Get(),source.Get(),source.Get(),42);
      expect(fs::exists(directory/"darktidevr-ui-readback.request"));
      darktidevr::producer::observe_stereo_ui_readback_overlay(1,42,overlay.Get());
      std::this_thread::sleep_for(std::chrono::milliseconds(1050));
    }
    darktidevr::producer::stage_stereo_ui_readback(commands.Get(),source_failure ? nullptr : source.Get(),source.Get(),source.Get(),source.Get(),42,
        observed ? nullptr : source.Get(),observed ? nullptr : source.Get());
    if(source_failure) {
      expect(!darktidevr::producer::stereo_ui_overlay_capture_requested());
      expect(!darktidevr::producer::stereo_ui_overlay_readback_staged() && !match_armed);
      expect(!fs::exists(directory/"darktidevr-ui-readback.request"));
      expect(read(stem.wstring()+L".log").find("phase=source_missing")!=std::string::npos);
      std::cout<<"ui_readback=pass source_failure stops_diagnostic_replay_without_claiming_staging\n";
      return 0;
    }
    expect(match_armed!=observed && darktidevr::producer::stereo_ui_overlay_readback_staged());
    expect(!darktidevr::producer::stereo_ui_overlay_capture_requested());
    // Keep a legitimate monitoring reader open throughout export. The secure
    // CRT's default exclusive write sharing previously lost completion logs.
    const auto observer=CreateFileW((stem.wstring()+L".log").c_str(),GENERIC_READ,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    expect(observer!=INVALID_HANDLE_VALUE);
    check(commands->Close()); ID3D12CommandList* lists[]{commands.Get()}; queue->ExecuteCommandLists(1,lists);
    darktidevr::producer::finish_stereo_ui_readback(queue.Get());
    std::string log;
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    do {
      log=read(stem.wstring()+L".log");
      if(log.find("UI_READBACK phase=exported ")!=std::string::npos ||
          log.find("UI_READBACK phase=export_failed ")!=std::string::npos) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    } while(std::chrono::steady_clock::now()<deadline);
    CloseHandle(observer);
    expect(log.find(failure ? "UI_READBACK phase=export_failed " : "UI_READBACK phase=exported result=0x00000000")!=std::string::npos);
    expect(log.find(observed ? "owned_ui=0" : "owned_ui=1")!=std::string::npos);
    for(const auto* role : {"left-scene","left-final","right-scene","right-final","left-ui","right-ui"}) {
      const auto record=std::string("UI_READBACK_IMAGE phase=exported role=")+role+" width=2 height=2 rgba_hash=8972538887847352181";
      if(failure && std::strcmp(role,"left-ui")==0) { expect(log.find(record)==std::string::npos); continue; }
      expect(log.find(record)!=std::string::npos);
      const auto bitmap=read(stem.string()+"-"+role+".bmp"); expect(bitmap.size()==70);
      for(unsigned pixel=0;pixel<4;++pixel) {
        const auto at=54+pixel*4;
        expect(static_cast<unsigned char>(bitmap[at])==pixel*4+2);
        expect(static_cast<unsigned char>(bitmap[at+1])==pixel*4+1);
        expect(static_cast<unsigned char>(bitmap[at+2])==pixel*4);
        expect(static_cast<unsigned char>(bitmap[at+3])==pixel*4+3);
      }
    }
    std::cout<<"ui_readback=pass rgba_hash row_padding bmp_channels "<<(failure ? "failed_export" : "complete_export")<<'\n';
  } catch(const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}
