#pragma once
#include <cstdint>
namespace darktidevr::producer {
// Evidence for the whole resource within one evaluation, never a global state cache.
struct NgxOutputState {
  bool known{};
  bool ambiguous{};
  std::uint32_t state{};
  unsigned transitions{};
  void transition(std::uint32_t flags, std::uint32_t subresource,
                  std::uint32_t after) {
    ++transitions;
    if (flags || subresource != ~std::uint32_t{}) ambiguous = true;
    known = !ambiguous;
    state = after;
  }
  void alias() { ambiguous = true; known = false; }
};
}
