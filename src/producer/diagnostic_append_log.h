#pragma once

#include <Windows.h>

#include <limits>
#include <mutex>
#include <string_view>

namespace darktidevr::producer {

// PSO creation and first-bind callbacks run on different renderer threads.
// FILE_SHARE_READ intentionally allows observers, but not another writer:
// serialize the complete open/write/close interval, not just WriteFile.
inline bool append_diagnostic_record(const wchar_t* path,
                                     std::string_view record) {
  if (record.empty() || record.size() > (std::numeric_limits<DWORD>::max)()) {
    return false;
  }
  static std::mutex append_mutex;
  std::scoped_lock lock(append_mutex);
  const auto file = CreateFileW(path, FILE_APPEND_DATA, FILE_SHARE_READ,
      nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  DWORD written{};
  const auto ok = WriteFile(file, record.data(),
      static_cast<DWORD>(record.size()), &written, nullptr);
  const auto closed = CloseHandle(file);
  return ok && closed && written == record.size();
}

}  // namespace darktidevr::producer
