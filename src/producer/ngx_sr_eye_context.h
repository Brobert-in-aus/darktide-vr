#pragma once
#include <cstdint>
#include <cstdio>

namespace darktidevr::producer {
// A snapshot of the application's pending capture tag, not GPU eye attribution.
struct NgxSrEyeContext {
  int eye{-1};
  std::uint64_t pose{}, queued{}, arms{}, resets{};
};
using NgxSrEyeContextReader = NgxSrEyeContext (*)();

inline int format_ngx_sr_eye_context(char* output, std::size_t capacity,
    std::uint64_t call, const char* phase, bool available,
    const NgxSrEyeContext& context) {
  return std::snprintf(output, capacity,
      "NGX_SR_CONTEXT call=%llu phase=%s available=%u eye=%d pose=%llu "
      "queued=%llu arms=%llu resets=%llu attribution_verified=0\n",
      static_cast<unsigned long long>(call), phase, available ? 1U : 0U,
      context.eye, static_cast<unsigned long long>(context.pose),
      static_cast<unsigned long long>(context.queued),
      static_cast<unsigned long long>(context.arms),
      static_cast<unsigned long long>(context.resets));
}
}
