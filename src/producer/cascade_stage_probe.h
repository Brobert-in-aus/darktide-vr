#pragma once
#include <Windows.h>
#include <cstdint>

namespace darktidevr::producer {
using CascadeContextReader = void (*)(std::uint64_t*, std::uint64_t*);
bool install_cascade_stage_probe(HMODULE module, CascadeContextReader reader);
}
