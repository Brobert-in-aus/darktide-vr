#pragma once

#include <algorithm>
#include <cstdint>

namespace darktidevr::core {

// Submitted-image cadence on the runtime timeline, not photon latency.
class DeliveryCadence {
 public:
  struct Window {
    std::uint64_t distinct{}, repeats{}, ended_repeat_runs{}, repeat_run_peak{};
    std::uint64_t gaps{}, maximum_gap_ns{}, clock_breaks{};
  };

  void observe(std::int64_t display_time, bool shared, bool distinct) noexcept {
    if (!shared) { break_continuity(); return; }
    if (have_time_ && display_time <= previous_time_) {
      ++window_.clock_breaks;
      break_continuity();
    }
    previous_time_ = display_time;
    have_time_ = true;
    if (!distinct) {
      ++window_.repeats;
      ++repeat_run_;
      window_.repeat_run_peak = (std::max)(window_.repeat_run_peak, repeat_run_);
      return;
    }
    ++window_.distinct;
    if (repeat_run_) ++window_.ended_repeat_runs;
    repeat_run_ = 0;
    if (have_distinct_) {
      // Unsigned subtraction also handles a valid timeline crossing zero.
      const auto gap = static_cast<std::uint64_t>(display_time) -
                       static_cast<std::uint64_t>(last_distinct_time_);
      ++window_.gaps;
      window_.maximum_gap_ns = (std::max)(window_.maximum_gap_ns, gap);
    }
    last_distinct_time_ = display_time;
    have_distinct_ = true;
  }

  void break_continuity() noexcept {
    have_time_ = have_distinct_ = false;
    repeat_run_ = 0;
  }
  void reset_window() noexcept { window_ = {}; }
  [[nodiscard]] const Window& window() const noexcept { return window_; }

 private:
  Window window_{};
  std::int64_t previous_time_{}, last_distinct_time_{};
  std::uint64_t repeat_run_{};
  bool have_time_{}, have_distinct_{};
};

} // namespace darktidevr::core
