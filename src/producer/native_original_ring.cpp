#include "producer/native_original_ring.h"
#include "core/shared_generated_frame_state.h"
#include "core/shared_object_name.h"
#include "core/shared_surface_policy.h"
#include <wrl/client.h>
#include <array>
#include <atomic>
#include <cstdio>
#include <mutex>
#include <string>

namespace darktidevr::producer {
using Microsoft::WRL::ComPtr;
struct NativeOriginalRing::Impl {
  struct Commands {
    ComPtr<ID3D12CommandAllocator> allocator;
    ComPtr<ID3D12GraphicsCommandList> list;
    ComPtr<ID3D12Resource> source;
    std::uint64_t completed_at{};
  };
  struct Slot {
    ComPtr<ID3D12Resource> texture;
    HANDLE handle{};
    std::array<Commands, 2> commands;
  };
  std::mutex mutex;
  std::array<Slot, core::kSharedGeneratedFrameSlotCount> slots;
  ComPtr<ID3D12Device> device;
  ComPtr<ID3D12CommandQueue> queue;
  ComPtr<ID3D12Fence> ready, consumed, work_done;
  HANDLE ready_handle{}, consumed_handle{};
  std::unique_ptr<core::SharedGeneratedFrameStateWriter> writer;
  UINT width{}, height{};
  DXGI_FORMAT format{};
  std::uint64_t sequence{}, work_sequence{};
  Tag pending_tag{};
  bool pending{}, failed{};
  HANDLE log{INVALID_HANDLE_VALUE};
  std::atomic<unsigned> reports{};

  Impl() {
    wchar_t temporary[MAX_PATH]{};
    const auto length = GetTempPathW(MAX_PATH, temporary);
    if (length && length < MAX_PATH) {
      const auto path = std::wstring(temporary) + L"darktidevr-native-original-ring-" +
                        std::to_wstring(GetCurrentProcessId()) + L".log";
      log = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ, nullptr,
                        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    }
  }

  ~Impl() {
    if (log != INVALID_HANDLE_VALUE) CloseHandle(log);
    for (auto& slot : slots) if (slot.handle) CloseHandle(slot.handle);
    if (ready_handle) CloseHandle(ready_handle);
    if (consumed_handle) CloseHandle(consumed_handle);
  }

  bool initialize(ID3D12CommandQueue* selected_queue, ID3D12Resource* source,
                  const D3D12_RESOURCE_DESC& input) {
    if (FAILED(source->GetDevice(IID_PPV_ARGS(&device)))) return false;
    queue = selected_queue;
    width = static_cast<UINT>(input.Width);
    height = input.Height;
    format = static_cast<DXGI_FORMAT>(core::canonical_shared_copy_format(input.Format));
    auto output = input;
    output.Width *= 2;
    output.Format = format;
    output.Flags = D3D12_RESOURCE_FLAG_NONE;
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_DEFAULT;
    for (unsigned i = 0; i < slots.size(); ++i) {
      auto& slot = slots[i];
      const auto name = core::shared_object_name(
          (L"Local\\DarktideVR-original-stereo-" + std::to_wstring(i)).c_str());
      if (FAILED(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_SHARED,
              &output, D3D12_RESOURCE_STATE_COMMON, nullptr,
              IID_PPV_ARGS(&slot.texture))) ||
          FAILED(device->CreateSharedHandle(slot.texture.Get(), nullptr,
              GENERIC_ALL, name.c_str(), &slot.handle))) return false;
    }
    if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED, IID_PPV_ARGS(&ready))) ||
        FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_SHARED, IID_PPV_ARGS(&consumed))) ||
        FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&work_done))) ||
        FAILED(device->CreateSharedHandle(ready.Get(), nullptr, GENERIC_ALL,
            core::shared_object_name(L"Local\\DarktideVR-original-stereo-ready").c_str(), &ready_handle)) ||
        FAILED(device->CreateSharedHandle(consumed.Get(), nullptr, GENERIC_ALL,
            core::shared_object_name(L"Local\\DarktideVR-original-stereo-consumed").c_str(), &consumed_handle))) return false;
    try {
      writer = std::make_unique<core::SharedGeneratedFrameStateWriter>(
          L"Local\\DarktideVR-original-frame-state-v1");
    } catch (...) { return false; }
    return true;
  }

  Result capture(ID3D12CommandQueue* selected_queue, Execute execute,
                 ID3D12Resource* source, D3D12_RESOURCE_STATES state,
                 unsigned eye, Tag tag) {
    std::scoped_lock lock(mutex);
    if (failed) return Result::failed;
    if (!selected_queue || !execute || !source || eye > 1 || !tag.present ||
        !tag.pose || !tag.generation || selected_queue->GetDesc().Type != D3D12_COMMAND_LIST_TYPE_DIRECT)
      return Result::invalid;
    const auto input = source->GetDesc();
    if (input.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
        !input.Width || input.Width > D3D12_REQ_TEXTURE2D_U_OR_V_DIMENSION / 2 ||
        !input.Height || input.Height > D3D12_REQ_TEXTURE2D_U_OR_V_DIMENSION ||
        input.DepthOrArraySize != 1 || input.MipLevels != 1 ||
        input.SampleDesc.Count != 1 ||
        (input.Format != DXGI_FORMAT_R8G8B8A8_UNORM &&
         input.Format != DXGI_FORMAT_R8G8B8A8_UNORM_SRGB &&
         input.Format != DXGI_FORMAT_R8G8B8A8_TYPELESS))
      return Result::invalid;
    if (!writer) {
      if (eye != 0) return Result::invalid;
      if (!initialize(selected_queue, source, input)) {
        failed = true;
        return Result::failed;
      }
    }
    if (selected_queue != queue.Get() || input.Width != width || input.Height != height ||
        core::canonical_shared_copy_format(input.Format) != static_cast<std::uint32_t>(format))
      return Result::invalid;
    const auto done = work_done->GetCompletedValue();
    const auto acknowledged = consumed->GetCompletedValue();
    if (done == UINT64_MAX || acknowledged == UINT64_MAX ||
        ready->GetCompletedValue() == UINT64_MAX) {
      failed = true;
      return Result::failed;
    }
    const auto next = sequence + 1;
    auto& slot = slots[core::generated_frame_slot(next)];
    if (eye == 0) {
      // Incomplete old pairs were never published. Their allocators still
      // require GPU completion before the same slot can be staged again.
      pending = false;
      if ((next > slots.size() && acknowledged < next - slots.size()) ||
          slot.commands[0].completed_at > done || slot.commands[1].completed_at > done)
        return Result::busy;
    } else if (!pending || pending_tag.pose != tag.pose ||
               pending_tag.generation != tag.generation) {
      pending = false;
      return Result::invalid;
    }
    auto& commands = slot.commands[eye];
    if (commands.completed_at > done) return Result::busy;
    if (!commands.allocator) {
      if (FAILED(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
              IID_PPV_ARGS(&commands.allocator))) ||
          FAILED(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
              commands.allocator.Get(), nullptr, IID_PPV_ARGS(&commands.list)))) {
        failed = true;
        return Result::failed;
      }
    } else if (FAILED(commands.allocator->Reset()) ||
               FAILED(commands.list->Reset(commands.allocator.Get(), nullptr))) {
      failed = true;
      return Result::failed;
    }
    commands.source = source; // Keep source ownership through GPU completion.
    std::array<D3D12_RESOURCE_BARRIER, 2> barriers{};
    for (auto& barrier : barriers) barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barriers[0].Transition = {slot.texture.Get(), D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_DEST};
    barriers[1].Transition = {source, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        state, D3D12_RESOURCE_STATE_COPY_SOURCE};
    const UINT count = state == D3D12_RESOURCE_STATE_COPY_SOURCE ? 1 : 2;
    commands.list->ResourceBarrier(count, barriers.data());
    D3D12_TEXTURE_COPY_LOCATION from{}, to{};
    from.pResource = source;
    from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    to.pResource = slot.texture.Get();
    to.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    commands.list->CopyTextureRegion(&to, eye * width, 0, 0, &from, nullptr);
    for (auto& barrier : barriers) std::swap(barrier.Transition.StateBefore, barrier.Transition.StateAfter);
    commands.list->ResourceBarrier(count, barriers.data());
    if (FAILED(commands.list->Close())) { failed = true; return Result::failed; }
    ID3D12CommandList* lists[]{commands.list.Get()};
    execute(selected_queue, 1, lists);
    commands.completed_at = ++work_sequence;
    if (FAILED(selected_queue->Signal(work_done.Get(), work_sequence))) {
      failed = true;
      return Result::failed;
    }
    if (eye == 0) {
      pending = true;
      pending_tag = tag;
      return Result::staged;
    }
    pending = false;
    if (FAILED(selected_queue->Signal(ready.Get(), next)) ||
        !writer->publish(next, tag.present, 0, width * 2, height,
            static_cast<std::uint32_t>(format), tag.pose, tag.pose,
            tag.generation, GetTickCount64(), next)) {
      failed = true;
      return Result::failed;
    }
    sequence = next;
    return Result::published;
  }
};

NativeOriginalRing::NativeOriginalRing() : impl_(std::make_unique<Impl>()) {}
NativeOriginalRing::~NativeOriginalRing() = default;
NativeOriginalRing::Result NativeOriginalRing::capture(ID3D12CommandQueue* queue,
    Execute execute, ID3D12Resource* source, D3D12_RESOURCE_STATES state,
    unsigned eye, Tag tag) {
  const auto result = impl_->capture(queue, execute, source, state, eye, tag);
  // Startup-only evidence; exhaustion avoids formatting/resource queries.
  if (impl_->reports.load(std::memory_order_relaxed) < 32 &&
      impl_->reports.fetch_add(1, std::memory_order_relaxed) < 32 &&
      impl_->log != INVALID_HANDLE_VALUE) {
    const auto description = source ? source->GetDesc() : D3D12_RESOURCE_DESC{};
    char line[256]{};
    const auto length = std::snprintf(line, sizeof(line),
        "eye=%u present=%llu pose=%llu generation=%llu result=%u width=%llu height=%u format=%u state=%u\n",
        eye, static_cast<unsigned long long>(tag.present), static_cast<unsigned long long>(tag.pose),
        static_cast<unsigned long long>(tag.generation), static_cast<unsigned>(result),
        static_cast<unsigned long long>(description.Width), description.Height,
        static_cast<unsigned>(description.Format), static_cast<unsigned>(state));
    DWORD written{};
    if (length > 0 && length < static_cast<int>(sizeof(line)))
      WriteFile(impl_->log, line, static_cast<DWORD>(length), &written, nullptr);
  }
  return result;
}
}  // namespace darktidevr::producer
