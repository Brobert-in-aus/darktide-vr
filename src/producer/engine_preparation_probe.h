#pragma once
#include <Windows.h>
#include <cstdint>

namespace darktidevr::producer {
using PreparationPresentReader = std::uint64_t (*)();
bool install_engine_preparation_probe(HMODULE module, PreparationPresentReader reader);
}
