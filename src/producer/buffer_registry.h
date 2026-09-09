#pragma once

#include "producer/object_lifetime.h"
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <vector>

namespace darktidevr::producer {
struct BufferResourceInfo {
  ID3D12Resource* resource{};
  std::uint64_t gpu_start{};
  std::uint64_t size{};
  D3D12_HEAP_TYPE heap_type{D3D12_HEAP_TYPE_CUSTOM};
  std::byte* mapped_base{};
  UINT mapped_subresource{};
  bool mapped{};
  std::array<void*, 16> last_map_stack{};
  USHORT last_map_stack_count{};
  std::byte* staging_base{};
  std::uint64_t staging_size{};
};

// Registry state survives until all object observers have been released.
// Records disappear with their GPU owner; the registry does not retain owners.
struct BufferRegistry : std::enable_shared_from_this<BufferRegistry> {
  std::mutex mutex;
  // Caller holds mutex. Mapping metadata may change; identity/extent changes
  // go through track. A span prevents callers from bypassing structural expiry.
  std::span<BufferResourceInfo> records_locked() { return resources; }

  // Caller holds mutex. Cache exact addresses, not ranges: overlapping newer
  // allocations must retain the reverse-scan winner. Read live metadata by
  // index so Map/Unmap changes remain visible without caching raw pointers.
  std::optional<BufferResourceInfo> resolve_locked(std::uint64_t address) {
    const auto bucket = (address >> 8) ^ (address >> 16) ^
                        (address >> 24) ^ (address >> 32);
    auto& cached = lookup_[bucket % lookup_.size()];
    if (cached.valid && cached.address == address) {
      return cached.index < resources.size()
          ? std::optional<BufferResourceInfo>{resources[cached.index]}
          : std::nullopt;
    }
    cached = {address, resources.size(), true};
    for (std::size_t index = resources.size(); index != 0; --index) {
      const auto& resource = resources[index - 1];
      if (address >= resource.gpu_start &&
          address - resource.gpu_start < resource.size) {
        cached.index = index - 1;
        return resource;
      }
    }
    return std::nullopt;
  }

  void track(ID3D12Resource* resource, std::uint64_t address,
             std::uint64_t size, D3D12_HEAP_TYPE type) {
    static constexpr GUID key =
        {0x4848e921, 0x0abb, 0x4370, {0xb1, 0x44, 0x29, 0xb2, 0x7a, 0x5b, 0xc9, 0x7f}};
    const auto registry = shared_from_this();
    if (!observe_lifetime(resource, key, [registry, resource] {
          std::scoped_lock lock(registry->mutex);
          std::erase_if(registry->resources, [resource](const auto& item) {
            return item.resource == resource;
          });
          registry->lookup_ = {};
        })) {
      return;
    }
    std::scoped_lock lock(mutex);
    resources.push_back(BufferResourceInfo{resource, address, size, type});
    lookup_ = {};
  }

 private:
  std::vector<BufferResourceInfo> resources;
  struct Lookup {
    std::uint64_t address{};
    std::size_t index{};
    bool valid{};
  };
  std::array<Lookup, 64> lookup_{};
};
}  // namespace darktidevr::producer
