#pragma once
#include <cstdint>
namespace darktidevr::producer {
// Evidence for the whole resource within one evaluation, never a global state cache.
struct NgxOutputState {
  bool known{};
  bool ambiguous{};
  bool incomplete_transition{};
  std::uint32_t state{};
  unsigned transitions{};
  void transition(std::uint32_t flags, std::uint32_t subresource,
                  std::uint32_t after, bool single_subresource = false) {
    ++transitions;
    if (flags || (subresource != ~std::uint32_t{} &&
                  !(single_subresource && subresource == 0))) incomplete_transition = true;
    // An explicit whole-resource transition after an alias barrier establishes
    // a new state. A split/partial transition remains conservatively unresolved.
    ambiguous = incomplete_transition;
    known = !ambiguous;
    state = after;
  }
  void alias() { ambiguous = true; known = false; }
};
}
