#include "producer/ngx_command_observations.h"
#include "producer/ngx_output_state.h"
#include <vector>
using darktidevr::producer::NgxCommandObservations;
int main() {
  darktidevr::producer::NgxOutputState state;
  if (state.known) return 9;
  state.transition(0, ~std::uint32_t{}, 8);
  if (!state.known || state.state != 8) return 10;
  state.transition(0, 0, 0);
  state.transition(0, ~std::uint32_t{}, 8);
  if (state.known || !state.ambiguous) return 11;
  state = {};
  state.transition(1, ~std::uint32_t{}, 8);
  if (state.known) return 12;
  state = {};
  state.transition(0, ~std::uint32_t{}, 8);
  state.alias();
  if (state.known) return 13;
  state.transition(0, ~std::uint32_t{}, 1024);
  state.transition(0, ~std::uint32_t{}, 8);
  if (!state.known || state.ambiguous || state.state != 8) return 16;
  state.alias();
  state.transition(1, ~std::uint32_t{}, 8);
  state.transition(0, ~std::uint32_t{}, 8);
  if (state.known) return 17;
  state = {};
  state.transition(0, 0, 8, true);
  if (!state.known) return 14;
  state.transition(0, 1, 8, true);
  if (state.known) return 15;
  NgxCommandObservations observations;
  if (observations.add(0, 1) || observations.add(1, 0)) return 1;
  if (!observations.add(10, 1) || !observations.add(10, 2) ||
      observations.add(20, 2) || !observations.add(20, 3)) return 2;
  std::vector<std::uint64_t> submitted;
  observations.consume(10, [&](auto call) { submitted.push_back(call); });
  observations.consume(10, [&](auto call) { submitted.push_back(call); });
  if (submitted != std::vector<std::uint64_t>{1,2}) return 3;
  // Reset consumes the old recording without counting it as a submission.
  observations.consume(20, [](auto) {});
  if (!observations.add(20, 4)) return 4;
  observations.consume(20, [&](auto call) { submitted.push_back(call); });
  if (submitted != std::vector<std::uint64_t>{1,2,4}) return 5;
  for (unsigned i = 1; i <= 256; ++i) if (!observations.add(i, i)) return 6;
  if (observations.add(257, 257)) return 7;
  observations.consume(128, [](auto) {});
  if (!observations.add(257, 257)) return 8;
  return 0;
}
