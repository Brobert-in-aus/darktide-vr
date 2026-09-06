#pragma once
#include <algorithm>
#include <cstdint>

namespace darktidevr::core {
// All times use the runtime's predicted display clock, in nanoseconds.
// Estimate source cadence independently of compositor repeats, then place the
// following original half a source interval after its interpolated image.
struct GeneratedFrameCadence {
  std::int64_t last_source{}, source_period{}, original_due{};
  void observe_source(std::int64_t time) {
    const auto interval = time - last_source;
    if (last_source && interval > 0 && interval < 250'000'000)
      source_period = source_period ? (source_period * 3 + interval) / 4 : interval;
    else source_period = 0;
    last_source = time;
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
