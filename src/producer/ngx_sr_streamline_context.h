#pragma once
#include <cstdint>
#include <cstddef>
#include <cstdio>

namespace darktidevr::producer {
struct NgxSrStreamlineContext {
  bool available{};
  std::uint32_t viewport{};
  std::uint64_t call{};
  const void* frame{};
  void* commands{};
};

// Caller supplies thread-local storage. Nested unrelated evaluations clear the
// current label for their duration, then restore the outer context exactly.
class NgxSrStreamlineScope {
 public:
  NgxSrStreamlineScope(NgxSrStreamlineContext& current,
                      const NgxSrStreamlineContext& next)
      : current_(current), prior_(current) { current_ = next; }
  ~NgxSrStreamlineScope() { current_ = prior_; }
  NgxSrStreamlineScope(const NgxSrStreamlineScope&) = delete;
  NgxSrStreamlineScope& operator=(const NgxSrStreamlineScope&) = delete;
 private:
  NgxSrStreamlineContext& current_;
  NgxSrStreamlineContext prior_;
};

inline int format_ngx_sr_streamline_context(char* output, std::size_t capacity,
    std::uint64_t call, const NgxSrStreamlineContext& context) {
  return std::snprintf(output, capacity,
      "NGX_SR_STREAMLINE call=%llu available=%u sl_call=%llu viewport=%u frame=%p commands=%p attribution_verified=0\n",
      static_cast<unsigned long long>(call), context.available ? 1U : 0U,
      static_cast<unsigned long long>(context.call), context.viewport,
      context.frame, context.commands);
}
}
