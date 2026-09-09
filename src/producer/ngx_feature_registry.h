#pragma once
#include <array>
#include <cstdint>
#include <mutex>

namespace darktidevr::producer {
class NgxFeatureRegistry {
 public:
  struct CreationFlags { bool queried{}; std::uint32_t result{}; int value{}; };
  struct Identity { std::uint32_t kind{}; std::uint64_t lifetime{}; CreationFlags creation_flags{}; };
  Identity created(const void* handle, std::uint32_t kind, std::uint32_t result,
                   CreationFlags flags) {
    std::scoped_lock lock(mutex_);
    if (!handle || result != 1) return {};
    Entry* free = nullptr;
    for (auto& entry : entries_) {
      if (entry.handle == handle) {
        // A second successful creation without observed release may be a
        // cached/shared handle. Do not invent its reference-count semantics.
        entry.identity = {};
        return {};
      }
      if (!entry.handle && !free) free = &entry;
    }
    if (!free) return {}; // Never evict a live identity to make a new one fit.
    free->handle = handle;
    free->identity = {kind, ++next_lifetime_, flags};
    return free->identity;
  }
  Identity created(const void* handle, std::uint32_t kind, std::uint32_t result) {
    return created(handle, kind, result, {});
  }
  void releasing(const void* handle) {
    std::scoped_lock lock(mutex_);
    for (auto& entry : entries_) if (entry.handle == handle) entry = {};
    // Even a failed release invalidates our observation. Reusing a potentially
    // partially released handle requires a newly observed successful creation.
  }
  Identity lookup(const void* handle) const {
    std::scoped_lock lock(mutex_);
    if (handle) for (const auto& entry : entries_)
      if (entry.handle == handle) return entry.identity;
    return {};
  }
 private:
  struct Entry { const void* handle{}; Identity identity{}; };
  mutable std::mutex mutex_;
  std::array<Entry,128> entries_{};
  std::uint64_t next_lifetime_{};
};
}
