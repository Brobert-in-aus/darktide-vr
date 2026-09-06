#pragma once
#include <array>
#include <cstdint>

namespace darktidevr::producer {
// Caller serializes access. Address identities only; owns no D3D12 objects.
// A successful Reset invalidates unmatched observations from the old recording.
class NgxCommandObservations {
 public:
  bool add(std::uintptr_t commands, std::uint64_t call) {
    if (!commands || !call) return false;
    for (const auto& entry : entries_) if (entry.call == call) return false;
    for (auto& entry : entries_) if (!entry.commands) {
      entry = {commands, call};
      return true;
    }
    return false;
  }
  template<class Visitor>
  void consume(std::uintptr_t commands, Visitor visitor) {
    if (!commands) return;
    for (auto& entry : entries_) if (entry.commands == commands) {
      const auto call = entry.call;
      entry = {};
      visitor(call);
    }
  }
 private:
  struct Entry { std::uintptr_t commands{}; std::uint64_t call{}; };
  std::array<Entry, 256> entries_{};
};
}
