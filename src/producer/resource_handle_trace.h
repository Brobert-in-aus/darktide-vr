#pragma once
#include <Windows.h>

namespace darktidevr::producer {
// Optional diagnostic. Register after MH_Initialize and before MH_EnableHook.
// Missing flag leaves the engine untouched; a requested but unverified hook fails.
bool install_resource_handle_trace(HMODULE capture_module);
}
