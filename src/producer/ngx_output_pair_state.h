#pragma once
#include "producer/ngx_output_state.h"
#include <cstdint>
#include <optional>

namespace darktidevr::producer {
// One pending left evaluation, not a persistent resource-state cache. Caller
// serializes access and observes every intervening barrier/reset/submission.
class NgxOutputPairState {
 public:
  struct Key {
    std::uint64_t call{}, lifetime{}, batch{}, present{};
    std::uintptr_t commands{}, output{};
    std::uint32_t thread{}, width{}, height{};
  };
  struct Seed { Key key; NgxOutputState state; };
  void left(Key key, NgxOutputState state) {
    pending_.reset();
    if (key.call && key.lifetime && key.batch && key.present && key.commands &&
        key.output && key.thread && key.width && key.height && state.known && !state.ambiguous)
      pending_ = Seed{key, state};
  }
  std::optional<Seed> right(Key key) {
    const auto pending = pending_;
    pending_.reset();
    if (!pending) return {};
    const auto& prior = pending->key;
    if (key.call != prior.call + 1 || !key.lifetime || key.lifetime == prior.lifetime ||
        key.batch != prior.batch || key.present != prior.present ||
        key.commands != prior.commands || key.output != prior.output ||
        key.thread != prior.thread || key.width != prior.width || key.height != prior.height ||
        !pending->state.known || pending->state.ambiguous) return {};
    return pending;
  }
  void invalidate(std::uintptr_t commands) {
    if (pending_ && pending_->key.commands == commands) pending_.reset();
  }
  void clear() { pending_.reset(); }
  template<class Visitor> void observe(std::uintptr_t commands, Visitor visitor) {
    if (pending_ && pending_->key.commands == commands) visitor(*pending_);
  }
 private:
  std::optional<Seed> pending_;
};
}
