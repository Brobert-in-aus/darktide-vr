#pragma once
#include <Windows.h>

namespace darktidevr::producer {
// Optional next-launch diagnostic, registered between MH_Initialize/EnableHook.
// Observes the NGX runtime export, never the caller-validated feature export.
bool install_ngx_output_probe(HMODULE capture_module);
}
