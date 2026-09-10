#pragma once
#include <unknwn.h>
#include <wrl/client.h>
#include <cstdint>
#include <cstdio>

namespace darktidevr::producer {
// Streamline v2.7.30 ProgrammingGuide section 5.3. Query only a live command
// interface during a bounded SR observation. No private proxy layout or global
// slGetNativeInterface call is needed. Unsupported queries remain unknown.
inline constexpr GUID kStreamlineNativeInterface{
    0xadec44e2, 0x61f0, 0x45c3, {0xad,0x9f,0x1b,0x37,0x37,0x92,0x84,0xff}};

struct StreamlineNativeIdentity {
  bool queried{};
  std::uint32_t result{};
  std::uintptr_t native{};
};

inline StreamlineNativeIdentity observe_streamline_native_identity(IUnknown* incoming) {
  if (!incoming) return {};
  Microsoft::WRL::ComPtr<IUnknown> native;
  const auto result = incoming->QueryInterface(kStreamlineNativeInterface,
      reinterpret_cast<void**>(native.GetAddressOf()));
  // Only the numeric identity escapes. Balance the acquired reference before
  // returning; never dereference this address outside the synchronous callback.
  return {true, static_cast<std::uint32_t>(result),
          SUCCEEDED(result) ? reinterpret_cast<std::uintptr_t>(native.Get()) : 0};
}

inline int format_streamline_native_identity(char* output, std::size_t capacity,
    std::uint64_t call, const StreamlineNativeIdentity& identity) {
  return std::snprintf(output, capacity,
      "NGX_SR_COMMAND_IDENTITY call=%llu queried=%u result=%08x native=%llx attribution_verified=0\n",
      static_cast<unsigned long long>(call), identity.queried ? 1U : 0U,
      identity.result, static_cast<unsigned long long>(identity.native));
}
}
