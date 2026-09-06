#pragma once
#include <cstdint>
#include <mutex>

namespace darktidevr::producer {
// Timing context only. It never labels an evaluation as belonging to a pose.
class NgxCaptureWindow {
 public:
  struct Context {
    std::uint64_t batch{}, present{}, first_call{};
    bool eligible{};
  };
  void configure(bool wait_for_submission) {
    std::scoped_lock lock(mutex_);
    open_ = !wait_for_submission;
    context_ = {};
  }
  bool open(std::uint64_t batch, std::uint64_t present, std::uint64_t first_call) {
    std::scoped_lock lock(mutex_);
    // Later batches cannot replenish a spent budget or relabel in-flight calls.
    if (open_ || !batch || !present) return false;
    context_ = {batch, present, first_call, false};
    open_ = true;
    return true;
  }
  Context snapshot(std::uint64_t call, std::uint64_t call_limit) const {
    std::scoped_lock lock(mutex_);
    auto context = context_;
    context.eligible = open_ && call > context.first_call &&
        call - context.first_call <= call_limit;
    return context;
  }
 private:
  mutable std::mutex mutex_;
  Context context_{};
  bool open_{};
};
}
