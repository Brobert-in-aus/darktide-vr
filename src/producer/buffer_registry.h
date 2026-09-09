#pragma once

#include "producer/object_lifetime.h"
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <limits>
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
    if (resources.empty()) return std::nullopt;
    // The reverse scan already finds the newest allocation immediately. Keep
    // that cheap case ahead of hashing and preserve its overlap precedence.
    const auto& newest = resources.back();
    if (address >= newest.gpu_start && address - newest.gpu_start < newest.size)
      return newest;
    const auto bucket = (address >> 8) ^ (address >> 16) ^
                        (address >> 24) ^ (address >> 32);
    auto& cached = lookup_[bucket % lookup_.size()];
    if (cached.valid && cached.address == address) {
      return cached.index < resources.size()
          ? std::optional<BufferResourceInfo>{resources[cached.index]}
          : std::nullopt;
    }
    cached = {address, resources.size(), true};
    for (std::size_t index = resources.size() - 1; index != 0; --index) {
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
          registry->range_lookup_ = {};
          if (registry->resources.empty()) {
            registry->minimum_address_ = (std::numeric_limits<std::uint64_t>::max)();
            registry->maximum_end_ = 0;
          }
        })) {
      return;
    }
    std::scoped_lock lock(mutex);
    resources.push_back(BufferResourceInfo{resource, address, size, type});
    minimum_address_ = (std::min)(minimum_address_, address);
    const auto maximum = (std::numeric_limits<std::uint64_t>::max)();
    const auto end = size > maximum - address ? maximum : address + size;
    maximum_end_ = (std::max)(maximum_end_, end);
    lookup_ = {};
    range_lookup_ = {};
  }

  // A full-range read can select an older, larger overlapping allocation.
  // Keep its cache separate from point lookup, with length in the exact key.
  // Caller holds mutex; return current mapping metadata, not a cached copy.
  std::optional<BufferResourceInfo> resolve_range_locked(
      std::uint64_t address, std::uint64_t bytes) {
    if (resources.empty()) return std::nullopt;
    const auto contains = [address, bytes](const BufferResourceInfo& resource) {
      return address >= resource.gpu_start && bytes <= resource.size &&
             address - resource.gpu_start <= resource.size - bytes;
    };
    if (contains(resources.back())) return resources.back();
    // Bounds expand until the registry becomes empty. Retired extremes may
    // cause extra scans but can never exclude a live allocation. Include the
    // one-past endpoint for zero-length reads and saturate overflowing extents.
    if (address < minimum_address_ || address > maximum_end_) return std::nullopt;
    const auto bucket = (address >> 8) ^ (address >> 16) ^
                        (address >> 24) ^ (address >> 32) ^ bytes;
    auto& cached = range_lookup_[bucket % range_lookup_.size()];
    if (cached.valid && cached.address == address && cached.bytes == bytes) {
      return cached.index < resources.size()
          ? std::optional<BufferResourceInfo>{resources[cached.index]}
          : std::nullopt;
    }
    cached = {address, bytes, resources.size(), true};
    for (std::size_t index = resources.size() - 1; index != 0; --index) {
      if (contains(resources[index - 1])) {
        cached.index = index - 1;
        return resources[index - 1];
      }
    }
    return std::nullopt;
  }

 private:
  std::vector<BufferResourceInfo> resources;
  std::uint64_t minimum_address_{(std::numeric_limits<std::uint64_t>::max)()};
  std::uint64_t maximum_end_{};
  struct Lookup {
    std::uint64_t address{};
    std::size_t index{};
    bool valid{};
  };
  std::array<Lookup, 64> lookup_{};
  struct RangeLookup {
    std::uint64_t address{}, bytes{};
    std::size_t index{};
    bool valid{};
  };
  std::array<RangeLookup, 64> range_lookup_{};
};
}  // namespace darktidevr::producer
