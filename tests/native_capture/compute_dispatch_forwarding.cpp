#include "../../src/producer/compute_dispatch_probe.cpp"
#include <cstring>
#include <iostream>
#include <stdexcept>

namespace {
using namespace darktidevr::producer::compute_probe;
std::array<std::byte, 0x300> test_context{};
std::array<std::byte, 0x100> test_payload{};
unsigned dispatch_calls{}, bind_calls{};
void check(bool value) { if (!value) throw std::runtime_error("compute forwarding mismatch"); }
bool mock_bind(void* a, void* b, void* c, void* d, bool alternate, bool secondary,
               std::uint32_t stage, void* root) {
  check(a == test_payload.data() && b == test_context.data() && c == a && d == b &&
        alternate && stage == 0xfedcba98 && root == a && GetLastError() == 0x1234);
  ++bind_calls;
  SetLastError(0x2345);
  return secondary;
}
void mock_dispatch(void* context, void* payload, std::uint64_t sort, bool alternate, std::uint32_t flags) {
  check(context == test_context.data() && payload == test_payload.data() &&
        sort == 0xfedcba9876543210ULL && alternate && flags == 0x87654321 && GetLastError() == 0x1234);
  ++dispatch_calls;
  for (bool result : {false, true}) {
    SetLastError(0x1234);
    check(bind_hook(payload, context, payload, context, true, result, 0xfedcba98, payload) == result);
    check(GetLastError() == 0x2345);
  }
  const std::uint64_t root = 789;
  std::memcpy(test_context.data() + 0x278, &root, sizeof(root));
  SetLastError(0x3456);
}
}
int main() {
  using namespace darktidevr::producer::compute_probe;
  dispatch_original = mock_dispatch;
  bind_original = mock_bind;
  present_reader = +[] { return std::uint64_t{77}; };
  next_poll = ~ULONGLONG{};
  const auto invoke = [] {
    SetLastError(0x1234);
    dispatch_hook(test_context.data(), test_payload.data(), 0xfedcba9876543210ULL, true, 0x87654321);
    check(GetLastError() == 0x3456 && current == nullptr && !binding_active);
  };
  invoke();
  check(dispatch_calls == 1 && bind_calls == 2 && admitted == 0);
  armed = true;
  invoke();
  check(dispatch_calls == 2 && bind_calls == 4 && completed == 1);
  const auto& r = records[0];
  check(r.metadata_valid && r.flags_valid && r.root_before_valid && r.root_after_valid &&
      r.root_before == 789 && r.root_after == 789 && r.present == 77 && r.binding_calls == 2 &&
      r.binding_successes == 1 && r.binding_ticks >= 0 && r.end - r.begin >= r.binding_ticks);
  admitted = record_limit;
  invoke();
  check(dispatch_calls == 3 && bind_calls == 6 && completed == 1);
  std::uint32_t value{};
  check(!read_at(reinterpret_cast<void*>(~std::uintptr_t{}), 4, &value, 4));
  check(!read_at(nullptr, 4, &value, 4));
  std::cout << "PASS five/eight argument forwarding, bool returns, errors, nested timing and bounds\n";
}
