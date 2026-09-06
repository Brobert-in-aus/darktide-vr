#pragma once
#include <cstdint>
#include <array>
struct ID3D12GraphicsCommandList;
struct ID3D12Resource;
namespace darktidevr::producer {
void configure_ngx_output_copy(bool enabled);
// A UI readback arms an exact-owner comparison. Reusing either owner before
// evaluation expires it, so an unrelated later frame cannot satisfy the probe.
void observe_ngx_copy_frame(ID3D12Resource* left_scene, ID3D12Resource* right_scene);
void arm_ngx_copy_ui_match(ID3D12Resource* left_scene, ID3D12Resource* right_scene,
    std::uint64_t pose);
// Caller has proven a complete stereo pair and UAV output state. SR calls may
// interleave between the paired FG calls. True requires queue-fence observation.
bool stage_ngx_output_copy(ID3D12GraphicsCommandList* commands, ID3D12Resource* output,
    std::uint64_t left_call, std::uint64_t right_call, const std::array<void*,6>& inputs);
// Called only after the observed queue fence covering right_call completes.
void complete_ngx_output_copy(std::uint64_t right_call);
}
