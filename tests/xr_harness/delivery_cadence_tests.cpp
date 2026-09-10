#include "core/delivery_cadence.h"
#include <cstdlib>
#include <iostream>

void require(bool value, const char* message) {
  if (!value) { std::cerr << message << '\n'; std::exit(1); }
}
int main() {
  darktidevr::core::DeliveryCadence cadence;
  constexpr std::int64_t period = 8333333;
  cadence.observe(0, true, true);
  cadence.observe(period, true, true);
  cadence.observe(2 * period, true, false);
  cadence.observe(3 * period, true, false);
  cadence.reset_window();
  cadence.observe(4 * period, true, false);
  cadence.observe(5 * period, true, true);
  auto result = cadence.window();
  require(result.repeats == 1 && result.repeat_run_peak == 3 && result.ended_repeat_runs == 1,
          "report boundary hid a repeat burst");
  require(result.gaps == 1 && result.maximum_gap_ns == 4 * period,
          "distinct delivery gap excluded repeated slots");
  cadence.reset_window();
  cadence.observe(6 * period, false, false);
  cadence.observe(100 * period, true, true);
  require(cadence.window().gaps == 0, "fallback bridged unrelated image timelines");
  cadence.observe(99 * period, true, true);
  require(cadence.window().clock_breaks == 1 && cadence.window().gaps == 0,
          "clock regression created an invalid gap");
  cadence.break_continuity();
  cadence.reset_window();
  cadence.observe(-period, true, true);
  cadence.observe(period, true, true);
  require(cadence.window().maximum_gap_ns == 2 * period, "signed timeline crossing was lost");
  return 0;
}
