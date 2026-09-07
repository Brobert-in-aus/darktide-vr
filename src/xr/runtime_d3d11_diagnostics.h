#pragma once
#include <iosfwd>
#include <memory>

namespace darktidevr::xr {
// Opt-in, process-local instrumentation. Keeps captured devices alive until
// this scope ends; it is deliberately unsuitable for performance measurements.
class RuntimeD3D11Diagnostics {
 public:
  explicit RuntimeD3D11Diagnostics(bool enabled);
  ~RuntimeD3D11Diagnostics();
  RuntimeD3D11Diagnostics(const RuntimeD3D11Diagnostics&) = delete;
  RuntimeD3D11Diagnostics& operator=(const RuntimeD3D11Diagnostics&) = delete;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
void report_runtime_d3d11_diagnostics(std::ostream& output);
}
