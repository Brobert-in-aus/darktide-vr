#pragma once
#include <Windows.h>
#include <cstdint>

namespace darktidevr::producer {
using ComputePresentReader = std::uint64_t (*)();
bool install_compute_dispatch_probe(HMODULE module, ComputePresentReader reader);
}
