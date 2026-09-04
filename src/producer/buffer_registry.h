#pragma once

#include "producer/object_lifetime.h"
#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
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
  std::vector<BufferResourceInfo> resources;

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
        })) {
      return;
    }
    std::scoped_lock lock(mutex);
    resources.push_back(BufferResourceInfo{resource, address, size, type});
  }
};
}  // namespace darktidevr::producer
