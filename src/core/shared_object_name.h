#pragma once

#include <Windows.h>
#include <string>

namespace darktidevr::core {

// Test executables opt in before loading transports (including the native DLL).
// The PID keeps simultaneous invocations separate; production names stay stable.
inline std::wstring shared_object_name(const wchar_t* name) {
  if (GetEnvironmentVariableW(L"DARKTIDEVR_TEST_TRANSPORTS", nullptr, 0) == 0) {
    return name;
  }
  return std::wstring(name) + L"-test-" + std::to_wstring(GetCurrentProcessId());
}

}  // namespace darktidevr::core
