#pragma once

#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <utility>

namespace darktidevr::harness {

// Starts idle. The callback owns error reporting and must not throw. Disabling
// permits an already-started capture to finish; no new capture starts while idle.
// Members are ordered so the worker joins before its synchronization state dies.
class CaptureWorker {
 public:
  explicit CaptureWorker(std::function<void()> capture,
                         std::chrono::milliseconds interval = std::chrono::milliseconds(33))
      : capture_(std::move(capture)), interval_(checked_interval(interval)),
        thread_([this](std::stop_token stop) { run(stop); }) {}

  CaptureWorker(const CaptureWorker&) = delete;
  CaptureWorker& operator=(const CaptureWorker&) = delete;

  void set_enabled(bool enabled) {
    bool changed;
    {
      std::scoped_lock lock(mutex_);
      changed = enabled_ != enabled;
      enabled_ = enabled;
    }
    if (changed) condition_.notify_all();
  }

 private:
  static std::chrono::milliseconds checked_interval(std::chrono::milliseconds interval) {
    if (interval.count() <= 0) throw std::invalid_argument("Capture interval must be positive");
    return interval;
  }

  void run(std::stop_token stop) {
    std::unique_lock lock(mutex_);
    // The predicate waits return the predicate, not the stop state: an enabled
    // worker would otherwise keep capturing after a stop request and the
    // joining destructor would never return.
    while (!stop.stop_requested()) {
      condition_.wait(lock, stop, [this] { return enabled_; });
      if (stop.stop_requested()) break;
      // Schedule from this attempt, without a catch-up burst after a slow capture.
      const auto next = std::chrono::steady_clock::now() + interval_;
      lock.unlock();
      capture_();
      lock.lock();
      condition_.wait_until(lock, stop, next, [this] { return !enabled_; });
    }
  }

  std::function<void()> capture_;
  const std::chrono::milliseconds interval_;
  std::mutex mutex_;
  std::condition_variable_any condition_;
  bool enabled_{};
  std::jthread thread_;
};

}  // namespace darktidevr::harness
