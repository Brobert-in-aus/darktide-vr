#pragma once
#include <atomic>
#include <cstdint>

namespace darktidevr::producer {
// Reserve before preparing diagnostic arguments. Once full, callers only read
// the counter; rejected events neither allocate payloads nor write a shared line.
class BoundedDiagnostic {
 public:
  explicit BoundedDiagnostic(std::uint64_t limit) : limit_(limit) {}
  template<class Callback> void run(Callback&& callback) {
    auto count = count_.load(std::memory_order_relaxed);
    while (count < limit_) {
      if (count_.compare_exchange_weak(count, count + 1,
                                      std::memory_order_relaxed)) {
        callback();
        return;
      }
    }
  }
 private:
  const std::uint64_t limit_;
  std::atomic<std::uint64_t> count_{};
};
}
