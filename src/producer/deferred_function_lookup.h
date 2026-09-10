#pragma once
#include <cstdint>

namespace darktidevr::producer {
// Caller serializes access. Retry delayed feature availability without a
// per-frame resolver call or accepting an address from a failed query.
class DeferredFunctionLookup {
 public:
  struct Result { int status; void* address; };
  template<class Resolver>
  void* resolve(std::uint64_t now_ms, Resolver&& resolver) {
    if (address_) return address_;
    if (attempts_ >= 8 || (attempts_ &&
        (now_ms < last_attempt_ || now_ms - last_attempt_ < 1000))) return nullptr;
    last_attempt_ = now_ms;
    ++attempts_;
    const auto result = resolver();
    if (result.status == 0 && result.address) address_ = result.address;
    return address_;
  }
  unsigned attempts() const noexcept { return attempts_; }
 private:
  void* address_{};
  std::uint64_t last_attempt_{};
  unsigned attempts_{};
};
}
