#pragma once
#include <Windows.h>
#include <cstddef>
#include <cstring>

namespace darktidevr::producer {
// Failure may leave a partial destination. Callers must discard it on false.
// This catches inaccessible memory, not concurrent writes or stale readable data.
inline bool safe_copy_bytes(void* destination, const void* source,
                            std::size_t size) {
  __try {
    std::memcpy(destination, source, size);
    return true;
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    return false;
  }
}
}  // namespace darktidevr::producer
