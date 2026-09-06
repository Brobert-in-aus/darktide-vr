#include "producer/stereo_ui_readback.h"
#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>
#include <array>
#include <string>
#include <thread>
#include <vector>
#include <cstdio>
#include <mutex>
#include <atomic>

namespace darktidevr::producer {
namespace {
using Microsoft::WRL::ComPtr;
struct Image {
  ComPtr<ID3D12Resource> readback;
  D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
  UINT64 bytes{};
};
struct Probe {
  std::array<Image,6> images;
  unsigned image_count{4};
  ComPtr<ID3D12Fence> done;
  std::wstring stem;
  ULONGLONG poll_after{};
  bool attempted{}, staged{}, submitted{};
  std::jthread worker;
};
Probe probe;
std::mutex overlays_mutex;
std::array<ComPtr<ID3D12Resource>,2> overlays;
std::array<std::uint64_t,2> overlay_poses{};
std::atomic<bool> overlay_staged{};
void log(const char* phase, HRESULT result) {
  FILE* file{};
  if(_wfopen_s(&file,(probe.stem+L".log").c_str(),L"a")!=0) return;
  std::fprintf(file,"UI_READBACK phase=%s result=0x%08x\n",phase,static_cast<unsigned>(result));
  std::fclose(file);
}
bool export_image(const Image& image, const wchar_t* suffix) {
  void* mapped{}; D3D12_RANGE range{0,static_cast<SIZE_T>(image.bytes)};
  if(FAILED(image.readback->Map(0,&range,&mapped))) return false;
  FILE* file{};
  bool ok=_wfopen_s(&file,(probe.stem+suffix+L".bmp").c_str(),L"wb")==0;
  const auto& footprint=image.footprint.Footprint;
  const auto write=[&](const void* value,std::size_t bytes) {
    if(ok && std::fwrite(value,1,bytes,file)!=bytes) ok=false;
  };
  BITMAPFILEHEADER header{};
  header.bfType=0x4d42; header.bfOffBits=sizeof(header)+sizeof(BITMAPINFOHEADER);
  header.bfSize=header.bfOffBits+footprint.Width*footprint.Height*4;
  BITMAPINFOHEADER info{};
  info.biSize=sizeof(info); info.biWidth=footprint.Width; info.biHeight=-static_cast<LONG>(footprint.Height);
  info.biPlanes=1; info.biBitCount=32;
  write(&header,sizeof(header)); write(&info,sizeof(info));
  std::vector<unsigned char> row(footprint.Width*4ULL);
  const auto* base=static_cast<const unsigned char*>(mapped)+image.footprint.Offset;
  for(UINT y=0;y<footprint.Height && ok;++y) {
    const auto* source=base+static_cast<std::size_t>(y)*footprint.RowPitch;
    for(UINT x=0;x<footprint.Width;++x) {
      row[x*4ULL]=source[x*4ULL+2]; row[x*4ULL+1]=source[x*4ULL+1];
      row[x*4ULL+2]=source[x*4ULL]; row[x*4ULL+3]=source[x*4ULL+3];
    }
    write(row.data(),row.size());
  }
  if(file) std::fclose(file);
  D3D12_RANGE written{0,0}; image.readback->Unmap(0,&written);
  return ok;
}
}
void observe_stereo_ui_readback_overlay(unsigned eye, std::uint64_t pose,
    ID3D12Resource* resource) {
  if (eye > 1) return;
  std::scoped_lock lock(overlays_mutex);
  overlays[eye] = resource;
  overlay_poses[eye] = resource ? pose : 0;
}
bool stereo_ui_overlay_readback_staged() noexcept { return overlay_staged.load(); }
void stage_stereo_ui_readback(ID3D12GraphicsCommandList* commands,
    ID3D12Resource* left_scene, ID3D12Resource* left_final,
    ID3D12Resource* right_scene, ID3D12Resource* right_final, std::uint64_t pose) {
  if(probe.attempted || !commands || GetTickCount64()<probe.poll_after) return;
  probe.poll_after=GetTickCount64()+1000;
  wchar_t directory[MAX_PATH]{};
  const auto length=GetTempPathW(MAX_PATH,directory);
  if(!length || length>=MAX_PATH) return;
  const auto request=std::wstring(directory)+L"darktidevr-ui-readback.request";
  if(GetFileAttributesW(request.c_str())==INVALID_FILE_ATTRIBUTES) return;
  probe.attempted=true;
  DeleteFileW(request.c_str());
  probe.stem=std::wstring(directory)+L"darktidevr-ui-readback-"+std::to_wstring(GetCurrentProcessId());
  ComPtr<ID3D12Device> device;
  if(FAILED(commands->GetDevice(IID_PPV_ARGS(&device)))) {log("device_failed",E_FAIL);return;}
  std::array<ComPtr<ID3D12Resource>,2> overlay_sources;
  {
    std::scoped_lock lock(overlays_mutex);
    if (pose && overlay_poses[0] == pose && overlay_poses[1] == pose && overlays[0] && overlays[1]) {
      overlay_sources = overlays;
      probe.image_count = 6;
    }
  }
  const std::array<ID3D12Resource*,6> sources{left_scene,left_final,right_scene,right_final,
      overlay_sources[0].Get(),overlay_sources[1].Get()};
  for(unsigned i=0;i<probe.image_count;++i) {
    if(!sources[i]) {log("source_missing",E_INVALIDARG);return;}
    const auto desc=sources[i]->GetDesc();
    if(desc.Dimension!=D3D12_RESOURCE_DIMENSION_TEXTURE2D || desc.MipLevels!=1 ||
        desc.DepthOrArraySize!=1 || desc.SampleDesc.Count!=1 ||
        (desc.Format!=DXGI_FORMAT_R8G8B8A8_TYPELESS && desc.Format!=DXGI_FORMAT_R8G8B8A8_UNORM)) {
      log("format_failed",E_INVALIDARG);return;
    }
    auto& image=probe.images[i];
    device->GetCopyableFootprints(&desc,0,1,0,&image.footprint,nullptr,nullptr,&image.bytes);
    if(!image.bytes || image.bytes>128ULL*1024*1024) {log("size_bound",E_OUTOFMEMORY);return;}
    D3D12_RESOURCE_DESC buffer{}; buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
    buffer.Width=image.bytes; buffer.Height=1; buffer.DepthOrArraySize=buffer.MipLevels=1;
    buffer.SampleDesc.Count=1; buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_READBACK;
    const auto hr=device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&buffer,
        D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&image.readback));
    if(FAILED(hr)) {log("allocation_failed",hr);return;}
  }
  auto hr=device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&probe.done));
  if(FAILED(hr)) {log("fence_failed",hr);return;}
  for(unsigned i=0;i<probe.image_count;++i) {
    D3D12_RESOURCE_BARRIER barrier{}; barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition={sources[i],D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        i < 4 ? D3D12_RESOURCE_STATE_COPY_DEST : D3D12_RESOURCE_STATE_RENDER_TARGET,
        D3D12_RESOURCE_STATE_COPY_SOURCE};
    commands->ResourceBarrier(1,&barrier);
    D3D12_TEXTURE_COPY_LOCATION from{},to{};
    from.pResource=sources[i]; from.Type=D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    to.pResource=probe.images[i].readback.Get(); to.Type=D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    to.PlacedFootprint=probe.images[i].footprint;
    commands->CopyTextureRegion(&to,0,0,0,&from,nullptr);
    std::swap(barrier.Transition.StateBefore,barrier.Transition.StateAfter);
    commands->ResourceBarrier(1,&barrier);
  }
  probe.staged=true;
  overlay_staged.store(probe.image_count == 6);
  log("staged",S_OK);
}
void finish_stereo_ui_readback(ID3D12CommandQueue* queue) {
  if(!probe.staged || probe.submitted || !queue) return;
  probe.submitted=true;
  const auto hr=queue->Signal(probe.done.Get(),1);
  if(FAILED(hr)) {log("signal_failed",hr);return;}
  probe.worker=std::jthread([](std::stop_token stop) {
    while(!stop.stop_requested()) {
      const auto value=probe.done->GetCompletedValue();
      if(value==UINT64_MAX) {log("device_removed",E_FAIL);return;}
      if(value>=1) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    if(stop.stop_requested()) return;
    const wchar_t* names[]{L"-left-scene",L"-left-final",L"-right-scene",L"-right-final",
                           L"-left-ui",L"-right-ui"};
    bool ok=true;
    for(unsigned i=0;i<probe.image_count;++i) ok=export_image(probe.images[i],names[i]) && ok;
    log(ok ? "exported" : "export_failed",ok ? S_OK : E_FAIL);
  });
}
}
