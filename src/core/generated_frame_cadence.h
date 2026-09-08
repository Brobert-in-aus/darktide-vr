#pragma once
#include <algorithm>
#include <cstdint>

namespace darktidevr::core {
// Source intervals use producer GetTickCount64 milliseconds and publication
// sequences. Display deadlines alone use the runtime prediction clock in ns.
// Skipped publications must not turn viewer ingestion cadence into source rate.
struct GeneratedFrameCadence {
  std::uint64_t last_source_tick{}, last_source_sequence{};
  std::int64_t source_period{}, original_due{};
  void observe_source(std::uint64_t tick_ms, std::uint64_t sequence) {
    if (!tick_ms || !sequence) {
      last_source_tick = last_source_sequence = 0;
      source_period = 0;
      return;
    }
    if (sequence == last_source_sequence && tick_ms == last_source_tick) return;
    if (sequence > last_source_sequence && tick_ms == last_source_tick) {
      // Coarse timestamps can repeat. Keep the original anchor so the next
      // positive interval still includes all intervening publications.
      return;
    }
    if (last_source_tick && tick_ms > last_source_tick &&
        sequence > last_source_sequence && tick_ms-last_source_tick < 250) {
      const auto interval = static_cast<std::int64_t>(
          (tick_ms-last_source_tick)*1'000'000 / (sequence-last_source_sequence));
      source_period = interval > 0
          ? (source_period ? (source_period*3+interval)/4 : interval) : 0;
    } else source_period = 0;
    last_source_tick = tick_ms;
    last_source_sequence = sequence;
  }
  void generated(std::int64_t time, std::int64_t display_period) {
    const auto period = std::max<std::int64_t>(1, display_period);
    const auto half_source = source_period ? source_period / 2 : period;
    // Select the nearest display slot rather than always rounding upward.
    const auto slots = std::max<std::int64_t>(1, (half_source + period / 2) / period);
    original_due = time + slots * period;
  }
  bool original_ready(std::int64_t time) const { return time >= original_due; }
};
}
