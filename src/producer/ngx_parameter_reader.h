#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

struct ID3D12Resource;

namespace darktidevr::producer::ngx {
// Windows x64 MSVC ABI, checked against Streamline v2.7.30's NGX headers.
// MSVC reverses the overload group: declaration order is NOT vtable order.
inline constexpr std::size_t kGetD3D12ResourceSlot = 9;
inline constexpr std::size_t kGetUnsignedSlot = 12;
inline constexpr std::uint32_t kSuccess = 1;

template <class Value>
std::uint32_t read_parameter(const void* parameters, const char* name,
                             Value* output, std::size_t slot) {
  // This is an ABI adapter, not a pointer validator. Only a live NGX callback
  // with a verified runtime/parameter implementation may use it. Do not retain
  // the parameter object or returned resource pointer beyond that callback.
  using Get = std::uint32_t (*)(const void*, const char*, Value*);
  const std::byte* table{};
  std::memcpy(&table, parameters, sizeof(table));
  Get get{};
  std::memcpy(&get, table + slot * sizeof(void*), sizeof(get));
  return get(parameters, name, output);
}

inline std::uint32_t read_resource(const void* parameters, const char* name,
                                   ID3D12Resource** output) {
  return read_parameter(parameters, name, output, kGetD3D12ResourceSlot);
}
inline std::uint32_t read_unsigned(const void* parameters, const char* name,
                                   unsigned int* output) {
  return read_parameter(parameters, name, output, kGetUnsignedSlot);
}
}  // namespace darktidevr::producer::ngx
