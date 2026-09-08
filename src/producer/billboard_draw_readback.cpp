#include "billboard_draw_readback.h"
#include <wrl/client.h>
#include <array>
#include <cstring>
#include <limits>
#include <mutex>

namespace darktidevr::producer {
using Microsoft::WRL::ComPtr;
struct BillboardDrawReadback::Impl {
  struct Shot {
    Id id{};
    std::uint64_t vs{}, ps{}, fence_value{};
    ComPtr<ID3D12GraphicsCommandList> commands;
    ComPtr<ID3D12Resource> source, before, after;
    ComPtr<ID3D12CommandQueue> queue;
    ComPtr<ID3D12Fence> fence;
    D3D12_PLACED_SUBRESOURCE_FOOTPRINT footprint{};
    UINT64 bytes{};
    unsigned in_flight{};
    bool complete{}, retired{}, published{}, poisoned{};
  };
  std::mutex mutex;
  std::array<std::unique_ptr<Shot>, 3> shots;

  static void copy(Shot& shot, ID3D12GraphicsCommandList* commands,
                   ID3D12Resource* target) noexcept {
    D3D12_RESOURCE_BARRIER barrier{};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = shot.source.Get();
    barrier.Transition.Subresource = 0;
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_RENDER_TARGET;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_COPY_SOURCE;
    commands->ResourceBarrier(1, &barrier);
    D3D12_TEXTURE_COPY_LOCATION src{}, dst{};
    src.pResource = shot.source.Get();
    src.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
    dst.pResource = target;
    dst.Type = D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
    dst.PlacedFootprint = shot.footprint;
    commands->CopyTextureRegion(&dst, 0, 0, 0, &src, nullptr);
    barrier.Transition.StateBefore = D3D12_RESOURCE_STATE_COPY_SOURCE;
    barrier.Transition.StateAfter = D3D12_RESOURCE_STATE_RENDER_TARGET;
    commands->ResourceBarrier(1, &barrier);
  }
};

BillboardDrawReadback::BillboardDrawReadback() : impl_(std::make_unique<Impl>()) {}
BillboardDrawReadback::~BillboardDrawReadback() = default;

BillboardDrawReadback::Id BillboardDrawReadback::begin(
    ID3D12GraphicsCommandList* commands, ID3D12Resource* source,
    std::uint64_t vs, std::uint64_t ps) noexcept {
  try {
    if (!commands || !source || !vs || !ps ||
        commands->GetType() != D3D12_COMMAND_LIST_TYPE_DIRECT) return 0;
    const auto desc = source->GetDesc();
    if (desc.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
        desc.DepthOrArraySize != 1 || desc.MipLevels != 1 ||
        desc.SampleDesc.Count != 1 || desc.Width == 0 || desc.Height == 0 ||
        desc.Width > 4096 || desc.Height > 4096 ||
        !(desc.Flags & D3D12_RESOURCE_FLAG_ALLOW_RENDER_TARGET)) return 0;
    if (desc.Format != DXGI_FORMAT_R11G11B10_FLOAT &&
        desc.Format != DXGI_FORMAT_R8G8B8A8_UNORM &&
        desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) return 0;
    std::scoped_lock lock(impl_->mutex);
    std::size_t slot = impl_->shots.size();
    for (std::size_t i = 0; i < impl_->shots.size(); ++i) {
      if (impl_->shots[i]) {
        if (impl_->shots[i]->vs == vs && impl_->shots[i]->ps == ps) return 0;
      } else if (slot == impl_->shots.size()) slot = i;
    }
    if (slot == impl_->shots.size()) return 0;
    auto shot = std::make_unique<Impl::Shot>();
    ComPtr<ID3D12Device> device;
    if (FAILED(source->GetDevice(IID_PPV_ARGS(&device)))) return 0;
    ComPtr<ID3D12Device> command_device;
    if (FAILED(commands->GetDevice(IID_PPV_ARGS(&command_device))) ||
        device.Get() != command_device.Get()) return 0;
    device->GetCopyableFootprints(&desc, 0, 1, 0, &shot->footprint,
                                 nullptr, nullptr, &shot->bytes);
    if (!shot->bytes || shot->bytes > 32ULL * 1024 * 1024) return 0;
    D3D12_HEAP_PROPERTIES heap{};
    heap.Type = D3D12_HEAP_TYPE_READBACK;
    D3D12_RESOURCE_DESC buffer{};
    buffer.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER;
    buffer.Width = shot->bytes;
    buffer.Height = 1;
    buffer.DepthOrArraySize = 1;
    buffer.MipLevels = 1;
    buffer.SampleDesc.Count = 1;
    buffer.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    for (auto* target : {std::addressof(shot->before), std::addressof(shot->after)}) {
      if (FAILED(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_NONE,
          &buffer, D3D12_RESOURCE_STATE_COPY_DEST, nullptr,
          IID_PPV_ARGS(target->ReleaseAndGetAddressOf())))) return 0;
    }
    if (FAILED(device->CreateFence(0, D3D12_FENCE_FLAG_NONE,
                                  IID_PPV_ARGS(&shot->fence)))) return 0;
    shot->id = slot + 1;
    shot->vs = vs;
    shot->ps = ps;
    shot->commands = commands;
    shot->source = source;
    // Store ownership before recording any reference into the command list.
    impl_->shots[slot] = std::move(shot);
    auto& stored = *impl_->shots[slot];
    Impl::copy(stored, commands, stored.before.Get());
    return stored.id;
  } catch (...) { return 0; }
}

void BillboardDrawReadback::end(Id id, ID3D12GraphicsCommandList* commands) noexcept {
  try {
    std::scoped_lock lock(impl_->mutex);
    if (!id || id > impl_->shots.size()) return;
    auto& shot = impl_->shots[id - 1];
    if (!shot || shot->commands.Get() != commands || shot->retired || shot->complete) return;
    Impl::copy(*shot, commands, shot->after.Get());
    shot->complete = true;
  } catch (...) {}
}

BillboardDrawReadback::Submission BillboardDrawReadback::submitting(
    ID3D12CommandQueue* queue, UINT count, ID3D12CommandList* const* lists) noexcept {
  Submission submission;
  try {
    if (!queue || !lists || !count) return submission;
    std::scoped_lock lock(impl_->mutex);
    for (auto& shot : impl_->shots) {
      if (!shot || shot->retired) continue;
      for (UINT i = 0; i < count; ++i) {
        if (lists[i] != shot->commands.Get()) continue;
        if (shot->queue && shot->queue.Get() != queue) shot->poisoned = true;
        else shot->queue = queue;
        ++shot->in_flight;
        submission.ids[submission.count++] = shot->id;
        break;
      }
    }
  } catch (...) {}
  return submission;
}

void BillboardDrawReadback::submitted(ID3D12CommandQueue* queue,
                                     const Submission& submission) noexcept {
  try {
    std::scoped_lock lock(impl_->mutex);
    for (const auto id : submission.ids) {
      if (!id || id > impl_->shots.size()) continue;
      auto& shot = impl_->shots[id - 1];
      if (!shot || !shot->in_flight) continue;
      --shot->in_flight;
      if (!queue || shot->queue.Get() != queue) { shot->poisoned = true; continue; }
      // Serialize value assignment and Signal together, including repeated
      // submissions from different CPU threads onto the same queue.
      ++shot->fence_value;
      if (FAILED(queue->Signal(shot->fence.Get(), shot->fence_value))) shot->poisoned = true;
    }
  } catch (...) {}
}

void BillboardDrawReadback::retired(ID3D12GraphicsCommandList* commands) noexcept {
  try {
    std::scoped_lock lock(impl_->mutex);
    for (auto& shot : impl_->shots) {
      if (shot && shot->commands.Get() == commands) shot->retired = true;
    }
  } catch (...) {}
}

std::vector<BillboardDrawReadback::Pixels> BillboardDrawReadback::collect() noexcept {
  std::vector<Pixels> result;
  try {
    std::scoped_lock lock(impl_->mutex);
    result.reserve(impl_->shots.size());
    for (auto& shot : impl_->shots) {
      if (!shot || !shot->retired || !shot->complete || shot->poisoned ||
          shot->published || shot->in_flight || !shot->fence_value) continue;
      const auto completed = shot->fence->GetCompletedValue();
      if (completed == std::numeric_limits<UINT64>::max()) { shot->poisoned = true; continue; }
      if (completed < shot->fence_value) continue;
      Pixels pixels;
      pixels.id = shot->id;
      pixels.vertex_shader = shot->vs;
      pixels.pixel_shader = shot->ps;
      pixels.width = shot->footprint.Footprint.Width;
      pixels.height = shot->footprint.Footprint.Height;
      pixels.row_pitch = shot->footprint.Footprint.RowPitch;
      pixels.format = shot->footprint.Footprint.Format;
      // Allocate before mapping: exceptions must never leave a resource mapped.
      pixels.before.resize(static_cast<std::size_t>(shot->bytes));
      pixels.after.resize(static_cast<std::size_t>(shot->bytes));
      bool valid = true;
      for (const bool after : {false, true}) {
        auto* resource = after ? shot->after.Get() : shot->before.Get();
        auto& output = after ? pixels.after : pixels.before;
        void* mapped{};
        D3D12_RANGE read{0, output.size()};
        if (FAILED(resource->Map(0, &read, &mapped))) { valid = false; break; }
        // Copy actual texels only. Row padding is undefined GPU memory and
        // must not be exported or mistaken for changed pixels by analysis.
        const auto* input = static_cast<const std::uint8_t*>(mapped);
        for (UINT row = 0; row < pixels.height; ++row) {
          const auto offset = static_cast<std::size_t>(row) * pixels.row_pitch;
          std::memcpy(output.data() + offset, input + offset,
                      static_cast<std::size_t>(pixels.width) * 4);
        }
        D3D12_RANGE written{0, 0};
        resource->Unmap(0, &written);
      }
      shot->published = true;
      if (valid) result.push_back(std::move(pixels));
    }
  } catch (...) {}
  return result;
}
}  // namespace darktidevr::producer
