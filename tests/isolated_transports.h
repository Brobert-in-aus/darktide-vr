#pragma once

#include <Windows.h>
#include <stdexcept>

namespace darktidevr::tests {
inline void isolate_transports() {
  if (!SetEnvironmentVariableW(L"DARKTIDEVR_TEST_TRANSPORTS", L"1")) {
    throw std::runtime_error("Could not isolate test transports");
  }
}
}  // namespace darktidevr::tests
