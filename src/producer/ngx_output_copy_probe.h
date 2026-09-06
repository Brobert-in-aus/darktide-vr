#pragma once
#include <cstdint>
struct ID3D12GraphicsCommandList;
struct ID3D12Resource;
namespace darktidevr::producer {
void configure_ngx_output_copy(bool enabled);
// Caller has proven a complete adjacent stereo pair and UAV output state.
void stage_ngx_output_copy(ID3D12GraphicsCommandList* commands, ID3D12Resource* output,
                           std::uint64_t left_call, std::uint64_t right_call);
// Called only after the observed queue fence covering right_call completes.
void complete_ngx_output_copy(std::uint64_t right_call);
}
