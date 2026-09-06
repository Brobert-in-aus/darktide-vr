#include "producer/ngx_output_copy_probe.h"
#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>
#include <mutex>

namespace darktidevr::producer {
namespace {
using Microsoft::WRL::ComPtr;
struct CopyProbe {
  bool enabled{};
  std::atomic<bool> attempted{}, exported{};
  std::atomic<std::uint64_t> call{};
  std::uint64_t left_call{};
  std::uint64_t pose{};
  std::array<void*,2> scenes{};
  bool matched_request{};
  ComPtr<ID3D12Resource> source, owned, readback;
  D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
  std::uint64_t bytes{};
  unsigned width{}, height{};
  std::wstring stem;
  // Last member: join export before releasing its resources on destruction.
  std::jthread worker;
};
CopyProbe probe;
std::mutex match_mutex;

void log(const char* phase, HRESULT result, std::uint64_t right_call,
         std::uint64_t left_pixels = 0, std::uint64_t right_pixels = 0,
         std::uint64_t left_hash = 0, std::uint64_t right_hash = 0) {
  const auto path = probe.stem + L".log";
  HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return;
  char line[640]{};
  const auto length = std::snprintf(line, sizeof(line),
      "NGX_COPY phase=%s left_call=%llu right_call=%llu result=0x%08x source=%p owned=%p readback=%p width=%u height=%u row_pitch=%u bytes=%llu left_nonblack=%llu right_nonblack=%llu left_hash=%llu right_hash=%llu publication=0 pose=%llu left_scene=%p right_scene=%p\n",
      phase, probe.left_call, right_call, static_cast<unsigned>(result), probe.source.Get(),
      probe.owned.Get(), probe.readback.Get(), probe.width, probe.height,
      probe.footprint.Footprint.RowPitch, probe.bytes, left_pixels, right_pixels, left_hash, right_hash,
      probe.pose, probe.scenes[0], probe.scenes[1]);
  DWORD written{};
  if (length > 0 && length < sizeof(line)) WriteFile(file, line, length, &written, nullptr);
  CloseHandle(file);
}

void export_pixels(std::uint64_t call) {
  void* mapped{};
  const D3D12_RANGE range{0, static_cast<SIZE_T>(probe.bytes)};
  const auto mapped_result = probe.readback->Map(0, &range, &mapped);
  if (FAILED(mapped_result)) { log("map_failed", mapped_result, call); return; }
  HANDLE file = CreateFileW((probe.stem + L".bmp").c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                            nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  bool success = file != INVALID_HANDLE_VALUE;
  const auto write = [&](const void* data, DWORD bytes) {
    DWORD written{};
    if (!success || !WriteFile(file, data, bytes, &written, nullptr) || written != bytes) success = false;
  };
  BITMAPFILEHEADER header{};
  header.bfType = 0x4d42;
  header.bfOffBits = sizeof(header) + sizeof(BITMAPINFOHEADER);
  header.bfSize = header.bfOffBits + probe.width * probe.height * 4;
  BITMAPINFOHEADER info{};
  info.biSize = sizeof(info); info.biWidth = probe.width; info.biHeight = -static_cast<LONG>(probe.height);
  info.biPlanes = 1; info.biBitCount = 32; info.biCompression = BI_RGB;
  write(&header, sizeof(header)); write(&info, sizeof(info));
  std::vector<unsigned char> row(probe.width * 4ULL);
  std::array<std::uint64_t, 2> nonblack{}, hashes{14695981039346656037ULL,14695981039346656037ULL};
  const auto* bytes = static_cast<const unsigned char*>(mapped) + probe.footprint.Offset;
  for (unsigned y = 0; y < probe.height; ++y) {
    const auto* source = bytes + y * static_cast<std::size_t>(probe.footprint.Footprint.RowPitch);
    for (unsigned x = 0; x < probe.width; ++x) {
      const auto eye = x < probe.width / 2 ? 0U : 1U;
      const auto* pixel = source + x * 4ULL;
      if (pixel[0] || pixel[1] || pixel[2]) ++nonblack[eye];
      for (unsigned channel = 0; channel < 3; ++channel) {
        hashes[eye] ^= pixel[channel]; hashes[eye] *= 1099511628211ULL;
      }
      row[x*4ULL] = pixel[2]; row[x*4ULL+1] = pixel[1];
      row[x*4ULL+2] = pixel[0]; row[x*4ULL+3] = pixel[3];
    }
    write(row.data(), static_cast<DWORD>(row.size()));
  }
  if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
  const D3D12_RANGE written{0,0}; probe.readback->Unmap(0, &written);
  log(success ? "exported" : "export_failed", success ? S_OK : E_FAIL, call,
      nonblack[0], nonblack[1], hashes[0], hashes[1]);
}
}

void configure_ngx_output_copy(bool enabled) { probe.enabled = enabled; }

void observe_ngx_copy_frame(ID3D12Resource* left_scene, ID3D12Resource* right_scene) {
  std::scoped_lock lock(match_mutex);
  if (!probe.attempted.load() && probe.matched_request &&
      (probe.scenes[0] == left_scene || probe.scenes[1] == right_scene)) {
    probe.matched_request = false;
    // Disable fallback too: this requested comparison must never capture an
    // unrelated frame if FG was suspended while its owners were recycled.
    probe.enabled = false;
  }
}

void arm_ngx_copy_ui_match(ID3D12Resource* left_scene, ID3D12Resource* right_scene,
    std::uint64_t pose) {
  std::scoped_lock lock(match_mutex);
  if (probe.attempted.load() || !left_scene || !right_scene || !pose) return;
  probe.scenes = {left_scene, right_scene};
  probe.pose = pose;
  probe.matched_request = true;
}

bool stage_ngx_output_copy(ID3D12GraphicsCommandList* commands, ID3D12Resource* output,
    std::uint64_t left_call, std::uint64_t right_call, const std::array<void*,6>& inputs) {
  if (!commands || !output || !left_call || right_call <= left_call) return false;
  {
    std::scoped_lock lock(match_mutex);
    if ((!probe.enabled && !probe.matched_request) || probe.attempted.load()) return false;
    if (probe.matched_request && (inputs[2] != probe.scenes[0] || inputs[5] != probe.scenes[1])) return false;
    if (probe.attempted.exchange(true)) return false;
  }
  std::array<wchar_t, MAX_PATH> directory{};
  const auto length = GetTempPathW(static_cast<DWORD>(directory.size()), directory.data());
  if (!length || length >= directory.size()) return false;
  probe.stem = std::wstring(directory.data(), length) + L"darktidevr-ngx-copy-" +
      std::to_wstring(GetCurrentProcessId());
  probe.left_call = left_call;
  auto description = output->GetDesc();
  if (description.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
      description.Format != DXGI_FORMAT_R8G8B8A8_UNORM || description.MipLevels != 1 ||
      description.DepthOrArraySize != 1 || description.SampleDesc.Count != 1 ||
      !description.Width || description.Width % 2 || !description.Height ||
      description.Width > D3D12_REQ_TEXTURE2D_U_OR_V_DIMENSION ||
      description.Height > D3D12_REQ_TEXTURE2D_U_OR_V_DIMENSION) {
    log("descriptor_failed", E_INVALIDARG, right_call); return false;
  }
  ComPtr<ID3D12Device> device;
  auto result = output->GetDevice(IID_PPV_ARGS(&device));
  if (FAILED(result)) { log("device_failed", result, right_call); return false; }
  probe.width = static_cast<unsigned>(description.Width); probe.height = description.Height;
  device->GetCopyableFootprints(&description, 0, 1, 0, &probe.footprint, nullptr, nullptr, &probe.bytes);
  // Allocation ceiling only; resolution is always the actual runtime output.
  if (!probe.bytes || probe.bytes > 512ULL*1024*1024) {
    log("allocation_bound", E_OUTOFMEMORY, right_call); return false;
  }
  description.Flags = D3D12_RESOURCE_FLAG_NONE;
  D3D12_HEAP_PROPERTIES heap{}; heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  result = device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &description,
      D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&probe.owned));
  if (FAILED(result)) { log("texture_failed", result, right_call); return false; }
  D3D12_RESOURCE_DESC buffer{}; buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
  buffer.Width = probe.bytes; buffer.Height = 1; buffer.DepthOrArraySize = 1;
  buffer.MipLevels = 1; buffer.SampleDesc.Count = 1; buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  heap.Type = D3D12_HEAP_TYPE_READBACK;
  result = device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE, &buffer,
      D3D12_RESOURCE_STATE_COPY_DEST, nullptr, IID_PPV_ARGS(&probe.readback));
  if (FAILED(result)) { log("readback_failed", result, right_call); return false; }
  probe.source = output;
  D3D12_RESOURCE_BARRIER source{};
  source.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  source.Transition = {output, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE};
  commands->ResourceBarrier(1, &source);
  commands->CopyResource(probe.owned.Get(), output);
  std::swap(source.Transition.StateBefore, source.Transition.StateAfter);
  commands->ResourceBarrier(1, &source);
  D3D12_RESOURCE_BARRIER owned{}; owned.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  owned.Transition = {probe.owned.Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COPY_SOURCE};
  commands->ResourceBarrier(1, &owned);
  D3D12_TEXTURE_COPY_LOCATION from{}, to{};
  from.pResource = probe.owned.Get(); from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
  to.pResource = probe.readback.Get(); to.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
  to.PlacedFootprint = probe.footprint;
  commands->CopyTextureRegion(&to, 0, 0, 0, &from, nullptr);
  probe.call.store(right_call, std::memory_order_release);
  log("staged", S_OK, right_call);
  return true;
}

void complete_ngx_output_copy(std::uint64_t right_call) {
  if (!right_call || probe.call.load(std::memory_order_acquire) != right_call ||
      probe.exported.exchange(true)) return;
  // Fence has already completed. File I/O and pixel scanning never run on Present.
  probe.worker = std::jthread([right_call] { export_pixels(right_call); });
}
}
