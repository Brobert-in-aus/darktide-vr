#pragma once
#include <Windows.h>
#include <cstdint>
struct ID3D12CommandList;
struct ID3D12CommandQueue;
struct D3D12_RESOURCE_BARRIER;

namespace darktidevr::producer {
// Optional next-launch diagnostic, registered between MH_Initialize/EnableHook.
// Observes the NGX runtime export, never the caller-validated feature export.
bool install_ngx_output_probe(HMODULE capture_module);
void arm_ngx_output_probe(std::uint64_t batch, std::uint64_t present);
void observe_ngx_command_reset(void* commands);
std::uint64_t observe_ngx_queue_submit(ID3D12CommandQueue* queue, unsigned count,
                              ID3D12CommandList* const* commands);
void signal_ngx_queue_completion(ID3D12CommandQueue* queue, std::uint64_t ticket);
void poll_ngx_queue_completion();
void observe_ngx_output_barriers(void* commands, unsigned count,
                                 const D3D12_RESOURCE_BARRIER* barriers);
}
