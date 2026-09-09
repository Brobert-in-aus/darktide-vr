#include <cstddef>
#include <cstdint>

// Offline analysis only: no graphics API, hooks, file I/O or process state.
extern "C" __declspec(dllexport) unsigned dtvr_analysis_hash_version() { return 1; }
extern "C" __declspec(dllexport) int dtvr_analysis_fnv1a64(
    const unsigned char* data, std::size_t bytes, std::uint64_t* output) {
  if (!output || (!data && bytes != 0)) return 1;
  std::uint64_t value = 14695981039346656037ULL;
  for (std::size_t i = 0; i < bytes; ++i) {
    value ^= data[i];
    value *= 1099511628211ULL;
  }
  *output = value;
  return 0;
}
