#pragma once
#include <iosfwd>
#include <memory>
#include <cstdint>
struct ID3D11Device;

namespace darktidevr::xr {
// Opt-in, process-local instrumentation. Keeps captured devices alive until
// this scope ends; it is deliberately unsuitable for performance measurements.
class RuntimeD3D11Diagnostics {
 public:
  explicit RuntimeD3D11Diagnostics(bool enabled, bool probe_adapters=false);
  ~RuntimeD3D11Diagnostics();
  RuntimeD3D11Diagnostics(const RuntimeD3D11Diagnostics&) = delete;
  RuntimeD3D11Diagnostics& operator=(const RuntimeD3D11Diagnostics&) = delete;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
void report_runtime_d3d11_diagnostics(std::ostream& output);
void probe_runtime_d3d11_import_adapters(std::ostream& output);
struct SharedTextureProbe {
  std::int32_t result{};
  std::uint32_t width{},height{},format{},misc_flags{};
};
SharedTextureProbe probe_shared_texture(ID3D11Device* device,std::uintptr_t handle);
}
