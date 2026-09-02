#pragma once

#include <Windows.h>

#include <iostream>

namespace darktidevr::tests {

inline int skip_if_live_xr_session() {
  const auto mutex = OpenMutexW(
      SYNCHRONIZE, FALSE, L"Local\\DarktideVR_XR_Harness_SingleWriter");
  if (!mutex) {
    return 0;
  }
  CloseHandle(mutex);
  std::cout << "live_session_guard=skip reason=xr_runner_active\n";
  return 77;
}

}  // namespace darktidevr::tests
