#pragma once
#include <d3d12.h>
#include <array>
#include <initializer_list>
#include <string_view>

namespace darktidevr::producer {
// Resource names can change, so read the object each time instead of caching
// pointer identities. Short names avoid allocation and the size-query roundtrip.
template<class Fallback>
int match_resource_name(ID3D12Object* resource,
                        std::initializer_list<std::string_view> names,
                        Fallback&& fallback) {
  if (!resource) return -1;
  const auto match = [&](std::string_view value) {
    int index = 0;
    for (const auto name : names) {
      if (value == name) return index;
      ++index;
    }
    return -1;
  };
  std::array<wchar_t, 65> wide{};
  UINT bytes = 64 * sizeof(wchar_t);
  const auto wide_result = resource->GetPrivateData(
      WKPDID_D3DDebugObjectNameW, &bytes, wide.data());
  if (wide_result == DXGI_ERROR_MORE_DATA) return match(fallback());
  if (SUCCEEDED(wide_result) && bytes >= sizeof(wchar_t) && wide[0]) {
    std::array<char, 65> ascii{};
    std::size_t length = 0;
    while (length < 64 && wide[length]) {
      // Non-ASCII wide names cannot equal the ASCII engine hash identifiers.
      if (static_cast<unsigned>(wide[length]) > 127) return match(fallback());
      ascii[length] = static_cast<char>(wide[length]);
      ++length;
    }
    return match(std::string_view(ascii.data(), length));
  }
  std::array<char, 128> narrow{};
  bytes = static_cast<UINT>(narrow.size());
  const auto narrow_result = resource->GetPrivateData(
      WKPDID_D3DDebugObjectName, &bytes, narrow.data());
  if (narrow_result == DXGI_ERROR_MORE_DATA) return match(fallback());
  if (FAILED(narrow_result) || bytes == 0) return -1;
  while (bytes && narrow[bytes - 1] == '\0') --bytes;
  return match(std::string_view(narrow.data(), bytes));
}
}
