#pragma once
#include <Windows.h>
#include <cstdint>

namespace darktidevr::producer {
// Optional next-launch diagnostic, registered between MH_Initialize/EnableHook.
// Observes the NGX runtime export, never the caller-validated feature export.
bool install_ngx_output_probe(HMODULE capture_module);
void arm_ngx_output_probe(std::uint64_t batch, std::uint64_t present);
}
