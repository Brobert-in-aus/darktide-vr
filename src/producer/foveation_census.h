#pragma once
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>

// Which render targets Darktide's shading actually goes into, and how much of
// it goes into each.
//
// Foveation reduces SHADING work, so the shading rate has to be set on the
// passes that shade. Two plausible guesses are both wrong: the eye final is
// the resolved output and the work is done by the time it is bound, and the
// main passes run at the DLSS internal resolution rather than the eye extent.
// Rather than guess, count.
//
// **What this does not measure.** Draws and vertices are not pixels, and
// foveation saves pixels: a depth prepass or a shadow cascade can carry an
// enormous vertex count and shade nothing at all. The ranking is therefore by
// draw count, the less wrong of the two; the vertex total is printed beside
// it; and the log says outright that neither is a pixel count. This census
// finds the candidate SHAPES. Which of them is expensive is a GPU-timing
// question and this cannot answer it.
//
// It is observation only: it binds nothing, changes no render state, and
// cannot make the game look wrong.
namespace darktidevr::producer {

// A distinct render target, keyed on the resource extent AND the viewport.
// The usual way an engine implements a dynamic or upscaled internal resolution
// is a smaller viewport into a full-size target, and keying on the extent
// alone would then report one shape for every pass and answer nothing --
// which is the entire question this exists to ask (review, 18 September).
struct FoveationCensusEntry {
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint32_t format{};
  std::uint32_t viewport_width{};
  std::uint32_t viewport_height{};
  std::atomic<std::uint64_t> binds{};
  std::atomic<std::uint64_t> draws{};
  std::atomic<std::uint64_t> vertices{};
  // The innermost marker in force when the shape was first seen. Engines label
  // their passes, so this is usually the pass name.
  std::array<char, 48> marker{};
};

class FoveationCensus {
 public:
  static constexpr std::size_t kCapacity = 32;
  static constexpr std::size_t kNone = kCapacity;
  // Command lists this THREAD is tracking. D3D12 lets one thread record one
  // list at a time but not two at once, and engines interleave (a shadow list
  // and a main list), so this is a small per-thread cache rather than one
  // current value. Per thread, so the draw path takes no lock at all: a global
  // mutex there would serialise the engine's parallel recording, which would
  // not corrupt the counts but could slow the frame enough for dynamic
  // resolution to move the very extents being measured.
  static constexpr std::size_t kLocalLists = 8;

  // The colour target bound on this list. The viewport arrives from a
  // different hook, so neither alone identifies the shape and the shape is
  // resolved at the first draw that follows.
  void bind(const void* list, std::uint32_t width, std::uint32_t height,
            std::uint32_t format, const char* marker) {
    auto& slot = slot_for(list, width != 0U && height != 0U);
    if (slot.list == nullptr) {
      return;
    }
    slot.width = width;
    slot.height = height;
    slot.format = format;
    slot.marker = marker;
    slot.resolved = kNone;
    slot.counted_bind = false;
  }

  void viewport(const void* list, std::uint32_t width, std::uint32_t height) {
    auto& slot = slot_for(list, false);
    if (slot.list == nullptr) {
      return;
    }
    slot.viewport_width = width;
    slot.viewport_height = height;
    slot.resolved = kNone;
  }

  void draw(const void* list, std::uint32_t vertex_or_index_count,
            std::uint32_t instance_count) {
    auto& slot = slot_for(list, false);
    if (slot.list == nullptr || slot.width == 0U || slot.height == 0U) {
      // No colour target: a depth-only or compute-adjacent pass. Charging its
      // draws to whatever was bound before would inflate exactly the number
      // this exists to measure.
      unattributed_draws_.fetch_add(1U, std::memory_order_relaxed);
      return;
    }
    if (slot.resolved == kNone) {
      slot.resolved = find_or_add(slot);
      if (slot.resolved == kNone) {
        unattributed_draws_.fetch_add(1U, std::memory_order_relaxed);
        return;
      }
      if (!slot.counted_bind) {
        slot.counted_bind = true;
        entries_[slot.resolved].binds.fetch_add(1U, std::memory_order_relaxed);
      }
    }
    auto& entry = entries_[slot.resolved];
    entry.draws.fetch_add(1U, std::memory_order_relaxed);
    entry.vertices.fetch_add(
        static_cast<std::uint64_t>(vertex_or_index_count) *
            (instance_count == 0U ? 1U : instance_count),
        std::memory_order_relaxed);
  }

  // The list is being reset: whatever it had is gone, and the pointer may be
  // reused for a different list. Free the slot rather than leaving it
  // occupied, or a thread cycling through lists fills its cache and evicts
  // live bindings for ever.
  void release(const void* list) {
    auto& local = cache();
    refresh(local);
    for (std::size_t i = 0; i < local.count; ++i) {
      if (local.slots[i].list == list) {
        local.slots[i] = local.slots[local.count - 1];
        local.slots[local.count - 1] = {};
        --local.count;
        return;
      }
    }
  }

  std::size_t size() const { return used_.load(std::memory_order_acquire); }
  std::uint64_t unattributed_draws() const {
    return unattributed_draws_.load(std::memory_order_relaxed);
  }
  std::uint64_t overflowed_shapes() const {
    return overflowed_.load(std::memory_order_relaxed);
  }
  // Bindings pushed out of a thread's cache. Their draws are charged to
  // whatever replaces them, so a nonzero count means some of the numbers are
  // wrong and roughly by how much. Counting it is the difference between a
  // wrong answer and a wrong answer that says so.
  std::uint64_t evicted_bindings() const {
    return evicted_.load(std::memory_order_relaxed);
  }

  void clear() {
    std::scoped_lock lock(mutex_);
    for (auto& entry : entries_) {
      entry.width = 0;
      entry.height = 0;
      entry.format = 0;
      entry.viewport_width = 0;
      entry.viewport_height = 0;
      entry.binds.store(0, std::memory_order_relaxed);
      entry.draws.store(0, std::memory_order_relaxed);
      entry.vertices.store(0, std::memory_order_relaxed);
      entry.marker = {};
    }
    used_.store(0, std::memory_order_release);
    unattributed_draws_.store(0, std::memory_order_relaxed);
    overflowed_.store(0, std::memory_order_relaxed);
    evicted_.store(0, std::memory_order_relaxed);
    // Every thread's cache now names shapes that no longer exist. There is no
    // way to reach another thread's storage, so bump a generation and let each
    // thread notice for itself.
    generation_.fetch_add(1U, std::memory_order_release);
  }

  // One line per shape, busiest first. Returns the characters written, never
  // including a terminating NUL.
  int write(char* out, int capacity) const {
    if (out == nullptr || capacity <= 0) {
      return 0;
    }
    const auto used = used_.load(std::memory_order_acquire);
    std::array<std::size_t, kCapacity> order{};
    for (std::size_t i = 0; i < used; ++i) {
      order[i] = i;
    }
    for (std::size_t i = 1; i < used; ++i) {
      const auto key = order[i];
      auto j = i;
      while (j > 0 &&
             entries_[order[j - 1]].draws.load(std::memory_order_relaxed) <
                 entries_[key].draws.load(std::memory_order_relaxed)) {
        order[j] = order[j - 1];
        --j;
      }
      order[j] = key;
    }
    int written = 0;
    const auto emit = [&](const char* format, auto... arguments) {
      if (written >= capacity) {
        return false;
      }
      const auto count = std::snprintf(
          out + written, static_cast<std::size_t>(capacity - written), format,
          arguments...);
      if (count <= 0) {
        return false;
      }
      // snprintf returns what it WOULD have written. Adding that on a
      // truncated line walks the count past the buffer, and the caller then
      // writes the stray NUL and whatever follows it.
      if (count >= capacity - written) {
        written = capacity - 1;
        return false;
      }
      written += count;
      return true;
    };
    for (std::size_t i = 0; i < used; ++i) {
      const auto& entry = entries_[order[i]];
      if (!emit("DARKTIDEVR_FOVEATION_CENSUS shape=%ux%u viewport=%ux%u "
                "format=%u binds=%llu draws=%llu vertices=%llu marker=%s\r\n",
                entry.width, entry.height, entry.viewport_width,
                entry.viewport_height, entry.format,
                static_cast<unsigned long long>(
                    entry.binds.load(std::memory_order_relaxed)),
                static_cast<unsigned long long>(
                    entry.draws.load(std::memory_order_relaxed)),
                static_cast<unsigned long long>(
                    entry.vertices.load(std::memory_order_relaxed)),
                entry.marker.data())) {
        break;
      }
    }
    emit("DARKTIDEVR_FOVEATION_CENSUS shapes=%u unattributed_draws=%llu "
         "overflowed_shapes=%llu evicted_bindings=%llu "
         "note=draws_and_vertices_are_not_pixels\r\n",
         static_cast<unsigned>(used),
         static_cast<unsigned long long>(
             unattributed_draws_.load(std::memory_order_relaxed)),
         static_cast<unsigned long long>(
             overflowed_.load(std::memory_order_relaxed)),
         static_cast<unsigned long long>(
             evicted_.load(std::memory_order_relaxed)));
    return written;
  }

 private:
  struct Slot {
    const void* list{};
    std::uint32_t width{};
    std::uint32_t height{};
    std::uint32_t format{};
    std::uint32_t viewport_width{};
    std::uint32_t viewport_height{};
    const char* marker{};
    std::size_t resolved{kNone};
    bool counted_bind{};
  };
  struct LocalCache {
    std::array<Slot, kLocalLists> slots{};
    std::size_t count{};
    std::size_t victim{};
    std::uint64_t generation{};
  };
  // A slot returned when the caller has nothing to record into: writing to it
  // is harmless and it keeps every path branch-light.
  static Slot& nowhere() {
    thread_local Slot discard;
    discard = {};
    return discard;
  }

  static LocalCache& cache() {
    // One per recording thread. A command list is recorded by a single thread,
    // so nothing here is shared and nothing needs a lock.
    thread_local LocalCache local;
    return local;
  }

  void refresh(LocalCache& local) const {
    const auto generation = generation_.load(std::memory_order_acquire);
    if (local.generation != generation) {
      local = LocalCache{};
      local.generation = generation;
    }
  }

  Slot& slot_for(const void* list, bool create) {
    auto& local = cache();
    refresh(local);
    for (std::size_t i = 0; i < local.count; ++i) {
      if (local.slots[i].list == list) {
        return local.slots[i];
      }
    }
    if (!create) {
      return nowhere();
    }
    if (local.count < kLocalLists) {
      local.slots[local.count] = Slot{};
      local.slots[local.count].list = list;
      return local.slots[local.count++];
    }
    // Out of slots: overwrite the oldest and COUNT it.
    evicted_.fetch_add(1U, std::memory_order_relaxed);
    const auto victim = local.victim;
    local.victim = (local.victim + 1U) % kLocalLists;
    local.slots[victim] = Slot{};
    local.slots[victim].list = list;
    return local.slots[victim];
  }

  std::size_t find_or_add(const Slot& slot) {
    const auto matches = [&](const FoveationCensusEntry& entry) {
      return entry.width == slot.width && entry.height == slot.height &&
             entry.format == slot.format &&
             entry.viewport_width == slot.viewport_width &&
             entry.viewport_height == slot.viewport_height;
    };
    const auto used = used_.load(std::memory_order_acquire);
    for (std::size_t i = 0; i < used; ++i) {
      if (matches(entries_[i])) {
        return i;
      }
    }
    std::scoped_lock lock(mutex_);
    // Another thread may have added it between the scan and the lock.
    const auto locked_used = used_.load(std::memory_order_relaxed);
    for (std::size_t i = used; i < locked_used; ++i) {
      if (matches(entries_[i])) {
        return i;
      }
    }
    if (locked_used >= kCapacity) {
      overflowed_.fetch_add(1U, std::memory_order_relaxed);
      return kNone;
    }
    auto& entry = entries_[locked_used];
    entry.width = slot.width;
    entry.height = slot.height;
    entry.format = slot.format;
    entry.viewport_width = slot.viewport_width;
    entry.viewport_height = slot.viewport_height;
    if (slot.marker != nullptr) {
      std::size_t i = 0;
      for (; i + 1 < entry.marker.size() && slot.marker[i] != '\0'; ++i) {
        // Tabs and newlines would break the log's own line format.
        const auto character = slot.marker[i];
        entry.marker[i] = (character == '\t' || character == '\r' ||
                           character == '\n') ? ' ' : character;
      }
      entry.marker[i] = '\0';
    }
    // Published last: a reader that sees the new count must see the fields.
    used_.store(locked_used + 1, std::memory_order_release);
    return locked_used;
  }

  mutable std::mutex mutex_;
  std::array<FoveationCensusEntry, kCapacity> entries_{};
  std::atomic<std::size_t> used_{};
  std::atomic<std::uint64_t> unattributed_draws_{};
  std::atomic<std::uint64_t> overflowed_{};
  std::atomic<std::uint64_t> evicted_{};
  // Unique per instance, not merely per clear(). The per-thread cache is a
  // function-local thread_local shared by every census on that thread, so a
  // fresh instance starting at the same generation as a stale cache would
  // inherit its bindings. Production has one census and would never notice; a
  // test would, and did.
  std::atomic<std::uint64_t> generation_{next_generation()};

  static std::uint64_t next_generation() {
    static std::atomic<std::uint64_t> counter{1};
    return counter.fetch_add(1, std::memory_order_relaxed);
  }
};

}  // namespace darktidevr::producer
