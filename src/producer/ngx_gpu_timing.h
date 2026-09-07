#pragma once
#include <d3d12.h>
#include <cstdint>
namespace darktidevr::producer {
struct NgxGpuTimingWorkload {
  std::uint64_t feature_lifetime{};
  unsigned eye_width{}, eye_height{};
  bool operator==(const NgxGpuTimingWorkload&) const = default;
};
void configure_ngx_gpu_timing(bool enabled);
unsigned begin_ngx_gpu_timing(ID3D12GraphicsCommandList* commands, unsigned eye,
    const NgxGpuTimingWorkload& workload);
void mark_ngx_gpu_timing(unsigned token, ID3D12GraphicsCommandList* commands);
void end_ngx_gpu_timing(unsigned token, ID3D12GraphicsCommandList* commands, bool success);
void submit_ngx_gpu_timing(ID3D12CommandQueue* queue, unsigned count, ID3D12CommandList* const* lists);
void reset_ngx_gpu_timing(void* commands);
}
