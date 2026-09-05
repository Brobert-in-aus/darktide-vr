#include "core/streamline_input_lifetime.h"
#include <iostream>
#include <stdexcept>

void check(bool value) {
  if (!value) throw std::runtime_error("Streamline input lifetime violation");
}

int main() {
  using darktidevr::core::StreamlineInputLifetime;
  StreamlineInputLifetime state;
  check(!state.begin(0));
  check(state.begin(1));
  check(!state.begin(2));
  check(!state.record_ticket(1, 0, 100, 5));
  check(!state.release(1));
  // An aborted batch can retire only after its installed tags are cleared.
  check(state.mark_tags_cleared(1));
  check(state.release(1));
  check(!state.begin(1)); // No stale ticket can attach to a reused identity.
  check(state.begin(2));
  check(!state.mark_tags_cleared(1));
  check(state.mark_presented(2));
  check(!state.mark_presented(2));
  check(state.mark_tags_cleared(2));
  check(!state.can_release());
  check(!state.record_ticket(2, 2, 100, 5));
  check(!state.record_ticket(2, 0, 0, 5));
  check(!state.record_ticket(2, 0, 100, ~std::uint64_t{}));
  check(state.record_ticket(2, 0, 100, 5));
  check(state.record_ticket(2, 0, 100, 5));
  check(!state.record_ticket(2, 0, 101, 5));
  check(!state.observe_completion(1, 0, 100, 5));
  check(!state.observe_completion(2, 0, 101, 5));
  check(!state.observe_completion(2, 0, 100, 4));
  check(!state.observe_completion(2, 0, 100, ~std::uint64_t{}));
  check(state.observe_completion(2, 0, 100, 6));
  check(!state.can_release());
  check(state.record_ticket(2, 1, 200, 9));
  check(!state.observe_completion(2, 1, 200, 8));
  check(state.observe_completion(2, 1, 200, 9));
  check(state.release(2));
  // A shared fence is legal, but both eye values must complete independently.
  check(state.begin(3));
  check(state.mark_presented(3));
  check(state.record_ticket(3, 0, 100, 0));
  check(state.record_ticket(3, 1, 100, 10));
  check(state.observe_completion(3, 0, 100, 0));
  check(!state.observe_completion(3, 1, 100, 9));
  check(state.observe_completion(3, 1, 100, 10));
  check(!state.can_release());
  check(state.mark_tags_cleared(3));
  check(state.release(3));
  std::cout << "streamline_input_lifetime=pass\n";
}
