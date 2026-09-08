#pragma once

#include <Windows.h>

#include <chrono>
#include <cstdint>
#include <thread>

namespace darktidevr::xr {

struct Win32PairWait {
  using Handle = HANDLE;
  static Handle create() noexcept {
    return CreateWaitableTimerExW(nullptr, nullptr, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                                 TIMER_MODIFY_STATE | SYNCHRONIZE);
  }
  static bool arm(Handle timer) noexcept {
    LARGE_INTEGER due{};
    due.QuadPart = -5000;  // Relative 500 microseconds in 100 ns units.
    return SetWaitableTimerEx(timer, &due, 0, nullptr, nullptr, nullptr, 0) != FALSE;
  }
  static bool wait(Handle timer) noexcept {
    // Bound an unexpected timer failure. No APC, periodic timer or wake request.
    return WaitForSingleObject(timer, 100) == WAIT_OBJECT_0;
  }
  static void close(Handle timer) noexcept { CloseHandle(timer); }
  static void fallback() { std::this_thread::sleep_for(std::chrono::microseconds(500)); }
};

// One owner on the frame thread. A failed timer is retired once and every
// subsequent poll sleeps normally; failure must never turn this into a spin loop.
template <typename Api = Win32PairWait>
class PairPollWait {
 public:
  explicit PairPollWait(bool enabled) : timer_(enabled ? Api::create() : nullptr) {
    if (enabled && !timer_) ++failures_;
  }
  ~PairPollWait() { if (timer_) Api::close(timer_); }
  PairPollWait(const PairPollWait&) = delete;
  PairPollWait& operator=(const PairPollWait&) = delete;

  void wait() {
    if (timer_) {
      if (Api::arm(timer_) && Api::wait(timer_)) return;
      Api::close(timer_);
      timer_ = nullptr;
      ++failures_;
    }
    Api::fallback();
  }

  [[nodiscard]] bool precise() const noexcept { return timer_ != nullptr; }
  [[nodiscard]] std::uint64_t failures() const noexcept { return failures_; }

 private:
  typename Api::Handle timer_{};
  std::uint64_t failures_{};
};

}  // namespace darktidevr::xr
