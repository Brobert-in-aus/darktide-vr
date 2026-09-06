#include "producer/ngx_command_observations.h"
#include "producer/ngx_output_state.h"
#include "producer/ngx_output_pair_state.h"
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
  using Pair = darktidevr::producer::NgxOutputPairState;
  Pair pairs;
  Pair::Key left{1, 10, 2, 100, 20, 30, 40, 50, 60};
  auto right = left;
  right.call = 2; right.lifetime = 11;
  state = {}; state.transition(0, ~std::uint32_t{}, 8);
  pairs.left(left, state);
  if (!pairs.right(right) || pairs.right(right)) return 18;
  for (unsigned mismatch = 0; mismatch < 10; ++mismatch) {
    pairs.left(left, state);
    auto other = right;
    switch (mismatch) {
      case 0: ++other.call; break;
      case 1: other.lifetime = left.lifetime; break;
      case 2: ++other.batch; break;
      case 3: ++other.present; break;
      case 4: ++other.commands; break;
      case 5: ++other.output; break;
      case 6: ++other.thread; break;
      case 7: ++other.width; break;
      case 8: ++other.height; break;
      case 9: other.lifetime = 0; break;
    }
    if (pairs.right(other) || pairs.right(right)) return 19;
  }
  pairs.left(left, state);
  pairs.invalidate(left.commands);
  if (pairs.right(right)) return 20;
  pairs.left(left, state);
  pairs.observe(left.commands, [](auto& pending) { pending.state.alias(); });
  if (pairs.right(right)) return 21;
  pairs.left(left, state);
  pairs.observe(left.commands, [](auto& pending) {
    pending.state.transition(0, ~std::uint32_t{}, 1024);
  });
  const auto updated = pairs.right(right);
  if (!updated || updated->state.state != 1024) return 22;
  pairs.left(left, {});
  if (pairs.right(right)) return 23;
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
