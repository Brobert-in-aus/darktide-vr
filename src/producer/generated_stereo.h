#pragma once
#include <cstdint>
#include <array>
struct ID3D12GraphicsCommandList;
struct ID3D12Resource;
struct ID3D12CommandQueue;
struct ID3D12CommandList;
namespace darktidevr::producer {
void configure_generated_stereo(bool enabled);
bool generated_stereo_enabled();
void generated_stereo_evaluation(bool complete, bool paired);
void generated_stereo_health(std::uint64_t present, std::uint64_t original_ready,
    bool foreground, std::uint64_t present_ms);
void generated_stereo_context(std::uint64_t previous_pose, std::uint64_t current_pose,
    std::uint64_t generation, std::uint64_t rendered_ready, const std::array<void*,6>& inputs);
void stage_generated_stereo(ID3D12GraphicsCommandList* commands, ID3D12Resource* output,
    std::uint64_t right_call, const std::array<void*,6>& inputs);
void submit_generated_stereo(ID3D12CommandQueue* queue, unsigned count, ID3D12CommandList* const* lists);
void reset_generated_stereo(void* commands);
std::uint64_t stage_original_stereo(ID3D12GraphicsCommandList* commands, ID3D12Resource* packed_final,
    std::uint64_t present, std::uint64_t pose, std::uint64_t generation);
bool submit_original_stereo(ID3D12CommandQueue* queue, std::uint64_t sequence);
}
