#pragma once
#include <Windows.h>
#include <cstdint>

namespace darktidevr::producer {
struct ParticleEyeContext {
  std::uint64_t present{}, pose{}, queued{}, arms{}, resets{};
  int eye{-1};
};
using ParticleEyeReader = ParticleEyeContext (*)();
// Register after MH_Initialize, before MH_EnableHook. Missing opt-in flag is a
// no-op. Runtime eye tags are context, not independently proven GPU attribution.
bool install_particle_submission_probe(HMODULE module, ParticleEyeReader reader);
}
